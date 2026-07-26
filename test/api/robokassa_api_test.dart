import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// A representative `OpStateExt` answer, in the namespace Robokassa uses.
const String _paidStateXml = '''
<?xml version="1.0" encoding="utf-8"?>
<OperationStateResponse xmlns="http://merchant.roboxchange.com/WebService/">
  <Result>
    <Code>0</Code>
    <Description>Успешно</Description>
  </Result>
  <State>
    <Code>100</Code>
    <RequestDate>2026-07-25T12:00:00.000+03:00</RequestDate>
    <StateDate>2026-07-25T12:01:30.000+03:00</StateDate>
  </State>
  <Info>
    <IncCurrLabel>BankCard</IncCurrLabel>
    <IncSum>100.00</IncSum>
    <IncAccount>444444******4444</IncAccount>
    <PaymentMethod>
      <Code>BankCard</Code>
      <Description>Банковская карта</Description>
    </PaymentMethod>
    <OutCurrLabel>RUB</OutCurrLabel>
    <OutSum>95.00</OutSum>
    <OpKey>op-key-1</OpKey>
  </Info>
</OperationStateResponse>
''';

/// Builds a response the way Robokassa actually answers: UTF-8 bytes.
///
/// `http.Response(String, …)` latin-1 encodes, which cannot represent the
/// Cyrillic in these fixtures.
http.Response _xmlResponse(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: const <String, String>{'content-type': 'text/xml'},
);

void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
  );

  group('parseOperationStateXml', () {
    test('reads every field from a paid operation', () {
      final state = parseOperationStateXml(_paidStateXml);

      expect(state.requestResult, RequestResultCode.success);
      expect(state.stateCode, PaymentStateCode.paid);
      expect(state.description, 'Успешно');
      expect(state.opKey, 'op-key-1');
      expect(state.incCurrLabel, 'BankCard');
      expect(state.incSum, 100.0);
      expect(state.incAccount, '444444******4444');
      expect(state.paymentMethodCode, 'BankCard');
      expect(state.outCurrLabel, 'RUB');
      expect(state.outSum, 95.0);
      expect(state.stateDate, isNotNull);
      expect(state.isPaid, isTrue);
      expect(state.shouldKeepPolling, isFalse);
    });

    test('recognises a held operation', () {
      final state = parseOperationStateXml(
        _paidStateXml.replaceFirst('<Code>100</Code>', '<Code>20</Code>'),
      );
      expect(state.stateCode, PaymentStateCode.holdSuccess);
      expect(state.isHeld, isTrue);
      expect(state.isPaid, isFalse);
    });

    test('an unpaid operation asks to keep polling', () {
      final state = parseOperationStateXml(
        _paidStateXml.replaceFirst('<Code>100</Code>', '<Code>5</Code>'),
      );
      expect(state.stateCode, PaymentStateCode.initializedNotPaid);
      expect(state.shouldKeepPolling, isTrue);
      expect(state.stateCode.isPending, isTrue);
      expect(state.stateCode.isTerminal, isFalse);
    });

    test('a bad signature is surfaced as a request-level failure', () {
      final state = parseOperationStateXml(
        _paidStateXml
            .replaceFirst('<Code>0</Code>', '<Code>1</Code>')
            .replaceFirst('<Code>100</Code>', '<Code>-1</Code>'),
      );
      expect(state.requestResult, RequestResultCode.signatureError);
      expect(state.requestResult.isSuccess, isFalse);
      expect(state.isPaid, isFalse);
    });

    test('a document without a namespace parses too', () {
      final state = parseOperationStateXml(
        '<OperationStateResponse><Result><Code>0</Code></Result>'
        '<State><Code>100</Code></State></OperationStateResponse>',
      );
      expect(state.requestResult, RequestResultCode.success);
      expect(state.stateCode, PaymentStateCode.paid);
    });

    test('malformed XML raises FormatException, not a null dereference', () {
      expect(
        () => parseOperationStateXml('<not-closed'),
        throwsFormatException,
      );
    });

    test('an HTML error page raises FormatException', () {
      expect(
        () => parseOperationStateXml('<html><body>502</body></html>'),
        throwsFormatException,
      );
    });

    test(
      'an unknown state code degrades safely instead of claiming success',
      () {
        final state = parseOperationStateXml(
          _paidStateXml.replaceFirst('<Code>100</Code>', '<Code>777</Code>'),
        );
        expect(state.stateCode, PaymentStateCode.notInitialized);
        expect(state.isPaid, isFalse);
      },
    );
  });

  group('getPaymentState', () {
    test('posts the documented fields and signature', () async {
      late http.Request captured;
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((request) async {
          captured = request;
          return _xmlResponse(_paidStateXml);
        }),
      );

      final state = await api.getPaymentState(5);

      expect(captured.method, 'POST');
      expect(captured.url, kOperationStateUrl);
      final fields = Uri.splitQueryString(captured.body);
      expect(fields['MerchantLogin'], 'demo');
      expect(fields['InvoiceID'], '5');
      // This endpoint names the field `Signature`, not `SignatureValue`.
      expect(fields.containsKey('SignatureValue'), isFalse);
      // Externally computed: md5("demo:5:password_2")
      expect(fields['Signature'], '9d4c6ee522d007f6c3cac58596864105');
      expect(state.isPaid, isTrue);

      api.close();
    });

    test(
      'a 5xx becomes RobokassaApiException with the body attached',
      () async {
        final api = RobokassaApi(
          credentials: credentials,
          httpClient: MockClient(
            (request) async => http.Response('upstream exploded', 503),
          ),
        );
        await expectLater(
          api.getPaymentState(5),
          throwsA(
            isA<RobokassaApiException>()
                .having((e) => e.statusCode, 'statusCode', 503)
                .having((e) => e.body, 'body', contains('upstream exploded')),
          ),
        );
        api.close();
      },
    );

    test('publishable credentials cannot query state', () async {
      final api = RobokassaApi(
        credentials: const RobokassaCredentials.publishable(
          merchantLogin: 'demo',
          password1: 'password_1',
        ),
        httpClient: MockClient((_) async => _xmlResponse(_paidStateXml)),
      );
      await expectLater(api.getPaymentState(5), throwsStateError);
      api.close();
    });

    test('a Cyrillic body is decoded as UTF-8 even without a charset', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(_paidStateXml),
            200,
            // Deliberately no charset — `http` would otherwise assume latin-1.
            headers: const <String, String>{'content-type': 'text/xml'},
          ),
        ),
      );
      final state = await api.getPaymentState(5);
      expect(state.description, 'Успешно');
      api.close();
    });
  });

  group('hold operations', () {
    test('confirmHold signs OutSum and reports success', () async {
      late http.Request captured;
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('{"success":true}', 200);
        }),
      );

      expect(await api.confirmHold(invoiceId: 5, outSum: 11), isTrue);
      expect(captured.url, kHoldConfirmUrl);
      final fields = Uri.splitQueryString(captured.body);
      expect(fields['OutSum'], '11.00');
      expect(fields['InvoiceID'], '5');
      // Externally computed: md5("demo:11.00:5:password_1")
      expect(fields['SignatureValue'], 'defb716d86f4f999b152ee51b7c8b5e2');

      api.close();
    });

    test('cancelHold sends OutSum but signs an empty operand', () async {
      late http.Request captured;
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('{"success":true}', 200);
        }),
      );

      expect(await api.cancelHold(invoiceId: 5, outSum: 11), isTrue);
      final fields = Uri.splitQueryString(captured.body);
      expect(fields['OutSum'], '11.00');
      // Externally computed: md5("demo::5:password_1")
      expect(fields['SignatureValue'], '4422c310764ab77315ee2231491437de');

      api.close();
    });

    test('a refusal raises rather than silently returning false', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient(
          (_) async => http.Response('{"success":false,"desc":"nope"}', 200),
        ),
      );
      await expectLater(
        api.confirmHold(invoiceId: 5, outSum: 11),
        throwsA(
          isA<RobokassaApiException>().having(
            (e) => e.body,
            'body',
            contains('nope'),
          ),
        ),
      );
      api.close();
    });
  });

  group('chargeRecurring', () {
    test(
      'sends PreviousInvoiceID but excludes it from the signature',
      () async {
        late http.Request captured;
        final api = RobokassaApi(
          credentials: credentials,
          httpClient: MockClient((request) async {
            captured = request;
            return http.Response('OK5', 200);
          }),
        );

        expect(
          await api.chargeRecurring(
            invoiceId: 5,
            previousInvoiceId: 4,
            outSum: 11,
          ),
          isTrue,
        );
        final fields = Uri.splitQueryString(captured.body);
        expect(fields['PreviousInvoiceID'], '4');
        // Same pre-image as a plain confirm — PreviousInvoiceID is not signed.
        expect(fields['SignatureValue'], 'defb716d86f4f999b152ee51b7c8b5e2');

        api.close();
      },
    );
  });

  group('createInvoice', () {
    test('returns the invoice id and its checkout URL', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"invoiceID":"abc123","errorCode":0,"errorMessage":null}',
            200,
          ),
        ),
      );

      final invoice = await api.createInvoice(
        const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
      );
      expect(invoice.invoiceId, 'abc123');
      expect(
        invoice.checkoutUrl.toString(),
        'https://auth.robokassa.ru/Merchant/Index/abc123',
      );

      api.close();
    });

    test('a non-zero errorCode raises with Robokassa message', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"invoiceID":null,"errorCode":7,"errorMessage":"bad signature"}',
            200,
          ),
        ),
      );
      await expectLater(
        api.createInvoice(
          const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
        ),
        throwsA(
          isA<RobokassaApiException>().having(
            (e) => e.message,
            'message',
            'bad signature',
          ),
        ),
      );
      api.close();
    });

    test('a non-JSON body raises rather than crashing', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((_) async => http.Response('<html/>', 200)),
      );
      await expectLater(
        api.createInvoice(
          const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
        ),
        throwsA(isA<RobokassaApiException>()),
      );
      api.close();
    });
  });

  group('awaitPaymentState', () {
    test('polls until the operation leaves its pending state', () async {
      var calls = 0;
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((_) async {
          calls++;
          return _xmlResponse(
            calls < 3
                ? _paidStateXml.replaceFirst(
                    '<Code>100</Code>',
                    '<Code>5</Code>',
                  )
                : _paidStateXml,
          );
        }),
      );

      final state = await api.awaitPaymentState(
        5,
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      );
      expect(calls, 3);
      expect(state.isPaid, isTrue);
      api.close();
    });

    test('returns the last state rather than throwing on timeout', () async {
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient(
          (_) async => _xmlResponse(
            _paidStateXml.replaceFirst('<Code>100</Code>', '<Code>5</Code>'),
          ),
        ),
      );

      final state = await api.awaitPaymentState(
        5,
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(milliseconds: 10),
      );
      expect(state.stateCode, PaymentStateCode.initializedNotPaid);
      api.close();
    });

    test('survives a transient transport failure', () async {
      var calls = 0;
      final api = RobokassaApi(
        credentials: credentials,
        httpClient: MockClient((_) async {
          calls++;
          if (calls == 1) return http.Response('gateway timeout', 504);
          return _xmlResponse(_paidStateXml);
        }),
      );

      final state = await api.awaitPaymentState(
        5,
        interval: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 5),
      );
      expect(state.isPaid, isTrue);
      expect(calls, 2);
      api.close();
    });
  });
}
