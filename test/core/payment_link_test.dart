import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
  );
  const builder = RobokassaLinkBuilder(credentials: credentials);

  group('form fields', () {
    test('a minimal order carries the documented required set', () {
      final fields = builder.buildFormFields(
        const PaymentParams(
          order: OrderParams(
            orderSum: 11,
            invoiceId: 5,
            description: 'Test order',
          ),
        ),
      );

      expect(fields['MerchantLogin'], 'demo');
      expect(fields['OutSum'], '11.00');
      expect(fields['InvId'], '5');
      expect(fields['Description'], 'Test order');
      // Externally computed: md5("demo:11.00:5:password_1")
      expect(fields['SignatureValue'], 'defb716d86f4f999b152ee51b7c8b5e2');
      expect(fields['Encoding'], 'utf-8');
      expect(fields.containsKey('IsTest'), isFalse);
    });

    test('test credentials add IsTest=1', () {
      const testBuilder = RobokassaLinkBuilder(
        credentials: RobokassaCredentials(
          merchantLogin: 'demo',
          password1: 'password_1',
          isTest: true,
        ),
      );
      final fields = testBuilder.buildFormFields(
        const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
      );
      expect(fields['IsTest'], '1');
    });

    test(
      'an absent invoice id is omitted from the request but signed empty',
      () {
        final params = const PaymentParams(order: OrderParams(orderSum: 11));
        final fields = builder.buildFormFields(params);
        expect(fields.containsKey('InvId'), isFalse);
        expect(builder.signatureFor(params).base, 'demo:11.00::password_1');
      },
    );

    test('the sent OutSum is exactly the signed OutSum', () {
      const params = PaymentParams(
        order: OrderParams(orderSum: 149.9, invoiceId: 7),
      );
      final fields = builder.buildFormFields(params);
      expect(fields['OutSum'], '149.90');
      expect(builder.signatureFor(params).base, contains(':149.90:'));
    });

    test('stripTrailingZeros changes both the field and the signature', () {
      const stripped = RobokassaLinkBuilder(
        credentials: credentials,
        stripTrailingZeros: true,
      );
      const params = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5),
      );
      expect(stripped.buildFormFields(params)['OutSum'], '11');
      expect(stripped.signatureFor(params).base, 'demo:11:5:password_1');
      // Externally computed: md5("demo:11:5:password_1")
      expect(
        stripped.signatureFor(params).value,
        '1d2fea40f7613de53b4057909984c72f',
      );
    });

    test('flags, currency, culture and expiry all map to their parameters', () {
      final fields = builder.buildFormFields(
        PaymentParams(
          order: OrderParams(
            orderSum: 11,
            invoiceId: 5,
            isHold: true,
            outSumCurrency: Currency.usd,
            incCurrLabel: 'BankCard',
            token: 'op-key-1',
            expirationDate: DateTime.utc(2026, 7, 25, 12),
          ),
          customer: const CustomerParams(
            culture: Culture.en,
            email: 'buyer@example.com',
            ip: '203.0.113.9',
          ),
        ),
      );

      expect(fields['StepByStep'], 'true');
      expect(fields['OutSumCurrency'], 'USD');
      expect(fields['IncCurrLabel'], 'BankCard');
      expect(fields['Token'], 'op-key-1');
      expect(fields['Culture'], 'en');
      expect(fields['Email'], 'buyer@example.com');
      expect(fields['UserIp'], '203.0.113.9');
      expect(
        fields['ExpirationDate'],
        matches(r'^2026-07-25T\d{2}:\d{2}:\d{2}\.000[+-]\d{2}:\d{2}$'),
      );
      expect(fields.containsKey('Recurring'), isFalse);
    });

    test('a recurring order sets Recurring=true', () {
      final fields = builder.buildFormFields(
        const PaymentParams(
          order: OrderParams(orderSum: 11, invoiceId: 5, isRecurrent: true),
        ),
      );
      expect(fields['Recurring'], 'true');
      expect(fields.containsKey('StepByStep'), isFalse);
    });

    test('Receipt is URL-encoded once, and that exact string is signed', () {
      const params = PaymentParams(
        order: OrderParams(
          orderSum: 100,
          invoiceId: 42,
          receipt: Receipt(
            sno: TaxSystem.osn,
            items: <ReceiptItem>[
              ReceiptItem(name: 'Boots', sum: 100, quantity: 1, tax: Tax.vat20),
            ],
          ),
        ),
      );
      final fields = builder.buildFormFields(params);

      // Documented convention: the operand is single URL-encoded (`%7B` = `{`).
      expect(fields['Receipt'], startsWith('%7B%22sno%22%3A%22osn%22'));
      expect(
        Uri.decodeComponent(fields['Receipt']!),
        '{"sno":"osn","items":[{"name":"Boots","sum":100.0,"quantity":1,'
        '"tax":"vat20"}]}',
      );
      // The signed operand and the transmitted value must be byte-identical.
      expect(builder.signatureFor(params).base, contains(fields['Receipt']!));
      // Externally computed over the single-encoded pre-image.
      expect(fields['SignatureValue'], '1f5e6eba437e6e949d1a60058da79ca5');
    });

    test('rawJson mode reproduces the official SDKs instead', () {
      const rawBuilder = RobokassaLinkBuilder(
        credentials: credentials,
        receiptMode: ReceiptSignatureMode.rawJson,
      );
      const params = PaymentParams(
        order: OrderParams(
          orderSum: 100,
          invoiceId: 42,
          receipt: Receipt(
            sno: TaxSystem.osn,
            items: <ReceiptItem>[
              ReceiptItem(name: 'Boots', sum: 100, quantity: 1, tax: Tax.vat20),
            ],
          ),
        ),
      );
      final fields = rawBuilder.buildFormFields(params);
      expect(fields['Receipt'], startsWith('{"sno":"osn"'));
      // Externally computed over the raw-JSON pre-image.
      expect(fields['SignatureValue'], '702238ef515f5035a525b85a6fdeab13');
    });

    test('a hold signs StepByStep, a plain payment does not', () {
      const hold = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5, isHold: true),
      );
      expect(builder.buildFormFields(hold)['StepByStep'], 'true');
      expect(builder.signatureFor(hold).base, 'demo:11.00:5:true:password_1');
      // Externally computed: md5("demo:11.00:5:true:password_1")
      expect(
        builder.signatureFor(hold).value,
        '022c5f352b7e3b9864078a1617e05ed4',
      );

      const plain = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5),
      );
      expect(builder.signatureFor(plain).base, 'demo:11.00:5:password_1');
    });

    test('a token is signed, but Recurring and IsTest are not', () {
      const withToken = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5, token: 'op-key-1'),
      );
      expect(
        builder.signatureFor(withToken).base,
        'demo:11.00:5:op-key-1:password_1',
      );

      const recurring = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5, isRecurrent: true),
      );
      expect(builder.signatureFor(recurring).base, 'demo:11.00:5:password_1');
    });

    test('OutSumCurrency and UserIp are sent but not signed', () {
      // Neither appears in Robokassa's normative modifier list.
      const params = PaymentParams(
        order: OrderParams(
          orderSum: 11,
          invoiceId: 5,
          outSumCurrency: Currency.usd,
        ),
        customer: CustomerParams(ip: '203.0.113.9'),
      );
      final fields = builder.buildFormFields(params);
      expect(fields['OutSumCurrency'], 'USD');
      expect(fields['UserIp'], '203.0.113.9');
      expect(builder.signatureFor(params).base, 'demo:11.00:5:password_1');
    });

    test('shp_ parameters appear in the request, sorted', () {
      final fields = builder.buildFormFields(
        PaymentParams(
          order: const OrderParams(orderSum: 11, invoiceId: 5),
          userParameters: UserParameters({'item': '2', 'a': '1'}),
        ),
      );
      expect(fields['shp_a'], '1');
      expect(fields['shp_item'], '2');
      expect(fields.keys.where((k) => k.startsWith('shp_')).toList(), <String>[
        'shp_a',
        'shp_item',
      ]);
    });
  });

  group('transports', () {
    test('buildUri points at the Robokassa payment page', () {
      final uri = builder.buildUri(
        const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'auth.robokassa.ru');
      expect(uri.path, '/Merchant/Index.aspx');
      expect(uri.queryParameters['OutSum'], '11.00');
      expect(
        uri.queryParameters['SignatureValue'],
        'defb716d86f4f999b152ee51b7c8b5e2',
      );
    });

    test('a GET query carries the receipt double-encoded', () {
      const params = PaymentParams(
        order: OrderParams(
          orderSum: 100,
          invoiceId: 42,
          receipt: Receipt(
            items: <ReceiptItem>[
              ReceiptItem(name: 'Boots', sum: 100, quantity: 1),
            ],
          ),
        ),
      );
      final uri = builder.buildUri(params);

      // Raw braces never reach the wire, and `%7B` is itself escaped to
      // `%257B` — matching Robokassa's own `/ru/saving` worked example.
      expect(uri.toString(), isNot(contains('{')));
      expect(uri.toString(), contains('Receipt=%257B'));

      // One decode (which `Uri` does) yields the signed operand…
      final operand = uri.queryParameters['Receipt']!;
      expect(operand, builder.receiptFor(params));
      // …and a second yields the JSON Robokassa fiscalises.
      expect(
        Uri.decodeComponent(operand),
        '{"items":[{"name":"Boots","sum":100.0,"quantity":1}]}',
      );
    });

    test('a form body round-trips through Uri.splitQueryString', () {
      const params = PaymentParams(
        order: OrderParams(
          orderSum: 11,
          invoiceId: 5,
          description: 'Two words & a symbol',
        ),
      );
      final decoded = Uri.splitQueryString(builder.buildFormBody(params));
      expect(decoded['Description'], 'Two words & a symbol');
      expect(decoded['SignatureValue'], builder.signatureFor(params).value);
    });

    test('a saved-card link needs a token', () {
      expect(
        () => builder.buildSavedCardUri(
          const PaymentParams(order: OrderParams(orderSum: 11, invoiceId: 5)),
        ),
        throwsArgumentError,
      );

      final uri = builder.buildSavedCardUri(
        const PaymentParams(
          order: OrderParams(orderSum: 11, invoiceId: 5, token: 'op-key-1'),
        ),
      );
      expect(uri.path, '/Merchant/Payment/CoFPayment');
    });

    test('an invoice checkout link appends the id to the path', () {
      expect(
        builder.buildInvoiceCheckoutUri('abc123').toString(),
        'https://auth.robokassa.ru/Merchant/Index/abc123',
      );
    });

    test('the convenience helper matches the builder', () {
      const params = PaymentParams(
        order: OrderParams(orderSum: 11, invoiceId: 5),
      );
      expect(
        buildRobokassaPaymentLink(credentials: credentials, params: params),
        builder.buildUri(params),
      );
    });
  });

  group('validation', () {
    test('a description over 100 characters is rejected', () {
      expect(
        () => builder.buildFormFields(
          PaymentParams(
            order: OrderParams(
              orderSum: 11,
              invoiceId: 5,
              description: 'x' * 101,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a malformed email is rejected', () {
      expect(
        () => builder.buildFormFields(
          const PaymentParams(
            order: OrderParams(orderSum: 11, invoiceId: 5),
            customer: CustomerParams(email: 'not-an-email'),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('hold and recurring cannot be combined', () {
      expect(
        () => builder.buildFormFields(
          const PaymentParams(
            order: OrderParams(
              orderSum: 11,
              invoiceId: 5,
              isHold: true,
              isRecurrent: true,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a non-positive order sum is rejected at construction', () {
      expect(() => OrderParams(orderSum: 0), throwsA(isA<AssertionError>()));
    });

    test('a malformed toolbar colour is rejected', () {
      expect(
        () => builder.buildFormFields(
          const PaymentParams(
            order: OrderParams(orderSum: 11, invoiceId: 5),
            view: ViewParams(toolbarBgColor: 'red'),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        const ViewParams(toolbarBgColor: '#ff0000').validate,
        returnsNormally,
      );
    });
  });

  group('amount formatting', () {
    test('two decimals by default', () {
      expect(formatOutSum(11), '11.00');
      expect(formatOutSum(11.5), '11.50');
      expect(formatOutSum(11.567), '11.57');
      expect(formatOutSum(0.1 + 0.2), '0.30');
    });

    test('trailing zeros are stripped only for whole amounts', () {
      expect(formatOutSum(11, stripTrailingZeros: true), '11');
      expect(formatOutSum(11.5, stripTrailingZeros: true), '11.50');
    });

    test('negative and non-finite amounts are rejected', () {
      expect(() => formatOutSum(-1), throwsArgumentError);
      expect(() => formatOutSum(double.nan), throwsArgumentError);
      expect(() => formatOutSum(double.infinity), throwsArgumentError);
    });

    test('parseOutSum accepts every spelling Robokassa echoes', () {
      expect(parseOutSum('11'), 11.0);
      expect(parseOutSum('11.0'), 11.0);
      expect(parseOutSum('11.00'), 11.0);
      expect(parseOutSum('11,50'), 11.5);
      expect(parseOutSum(' 11.00 '), 11.0);
      expect(parseOutSum('abc'), isNull);
      expect(parseOutSum(null), isNull);
    });

    test('ExpirationDate renders with a numeric offset, never Z', () {
      final formatted = formatExpirationDate(DateTime.utc(2026, 7, 25, 12));
      expect(formatted, isNot(contains('Z')));
      expect(formatted, matches(r'\.\d{3}[+-]\d{2}:\d{2}$'));
      // Round-trips back to the same instant.
      expect(DateTime.parse(formatted).toUtc(), DateTime.utc(2026, 7, 25, 12));
    });
  });
}
