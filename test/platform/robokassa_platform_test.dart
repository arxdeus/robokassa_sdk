import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';
import 'package:robokassa_sdk/src/platform/messages.g.dart';

import 'test_api.g.dart';

/// Captures whatever the Dart side actually sends over the channel, so the
/// model → transport conversion is asserted end-to-end through Pigeon's real
/// codec rather than by poking at private helpers.
class _RecordingHostApi implements TestRobokassaHostApi {
  RkPaymentRequest? lastRequest;
  String? lastCall;

  RkPaymentResultMessage result = RkPaymentResultMessage(
    outcome: RkPaymentOutcome.success,
    invoiceId: 42,
    opKey: 'op-key-1',
    resultCode: '0',
    stateCode: '100',
  );
  bool boolResult = true;
  Exception? throwOnCall;

  void _record(String call, RkPaymentRequest request) {
    lastCall = call;
    lastRequest = request;
    final error = throwOnCall;
    if (error != null) throw error;
  }

  @override
  Future<RkPaymentResultMessage> startPayment(RkPaymentRequest request) async {
    _record('startPayment', request);
    return result;
  }

  @override
  Future<RkPaymentResultMessage> checkPaymentState(
    RkPaymentRequest request,
  ) async {
    _record('checkPaymentState', request);
    return result;
  }

  @override
  Future<bool> confirmHold(RkPaymentRequest request) async {
    _record('confirmHold', request);
    return boolResult;
  }

  @override
  Future<bool> cancelHold(RkPaymentRequest request) async {
    _record('cancelHold', request);
    return boolResult;
  }

  @override
  Future<bool> chargeRecurring(RkPaymentRequest request) async {
    _record('chargeRecurring', request);
    return boolResult;
  }

  @override
  bool isNativeSdkAvailable() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingHostApi host;
  late Robokassa robokassa;

  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
    isTest: true,
  );

  setUp(() {
    host = _RecordingHostApi();
    TestRobokassaHostApi.setUp(host);
    robokassa = Robokassa(credentials: credentials);
  });

  tearDown(() {
    TestRobokassaHostApi.setUp(null);
    robokassa.dispose();
  });

  PaymentParams params({
    int? invoiceId = 42,
    bool isHold = false,
    bool isRecurrent = false,
    String? token,
    int? previousInvoiceId,
    Receipt? receipt,
  }) => PaymentParams(
    order: OrderParams(
      orderSum: 149.9,
      invoiceId: invoiceId,
      description: 'Pro plan',
      isHold: isHold,
      isRecurrent: isRecurrent,
      token: token,
      previousInvoiceId: previousInvoiceId,
      outSumCurrency: Currency.usd,
      expirationDate: DateTime.utc(2026, 7, 25, 12),
      receipt: receipt,
    ),
    customer: const CustomerParams(
      culture: Culture.en,
      email: 'buyer@example.com',
      ip: '203.0.113.9',
    ),
    view: const ViewParams(toolbarText: 'Checkout', toolbarBgColor: '#101010'),
    redirectUrl: 'https://shop.example.com/done',
  );

  group('request conversion', () {
    test('every field survives the round trip through the codec', () async {
      await robokassa.pay(params());

      final request = host.lastRequest!;
      expect(host.lastCall, 'startPayment');
      expect(request.mode, RkPaymentMode.simple);

      expect(request.credentials.merchantLogin, 'demo');
      expect(request.credentials.password1, 'password_1');
      expect(request.credentials.password2, 'password_2');
      expect(request.credentials.isTest, isTrue);
      expect(request.credentials.redirectUrl, 'https://shop.example.com/done');

      expect(request.order.orderSum, 149.9);
      expect(request.order.invoiceId, 42);
      expect(request.order.orderDescription, 'Pro plan');
      expect(request.order.outSumCurrency, 'USD');
      expect(
        request.order.expirationDateEpochMs,
        DateTime.utc(2026, 7, 25, 12).millisecondsSinceEpoch,
      );

      expect(request.customer.culture, 'en');
      expect(request.customer.email, 'buyer@example.com');
      expect(request.customer.ip, '203.0.113.9');

      expect(request.view.toolbarText, 'Checkout');
      expect(request.view.toolbarBgColor, '#101010');
      expect(request.view.hasToolbar, isTrue);
    });

    test('the chosen mode wins over the order flags', () async {
      // `payWithHold` must set the hold flag even though `isHold` is false.
      await robokassa.payWithHold(params());
      expect(host.lastRequest!.mode, RkPaymentMode.hold);
      expect(host.lastRequest!.order.isHold, isTrue);
      expect(host.lastRequest!.order.isRecurrent, isFalse);

      await robokassa.payRecurrentFirst(params());
      expect(host.lastRequest!.mode, RkPaymentMode.recurrent);
      expect(host.lastRequest!.order.isRecurrent, isTrue);
    });

    test('a receipt is flattened into transport records', () async {
      await robokassa.pay(
        params(
          receipt: const Receipt(
            sno: TaxSystem.usnIncome,
            items: <ReceiptItem>[
              ReceiptItem(
                name: 'Pro plan',
                sum: 149.9,
                quantity: 1,
                paymentMethod: PaymentMethod.fullPayment,
                paymentObject: PaymentObject.service,
                tax: Tax.vat20,
              ),
            ],
          ),
        ),
      );

      final receipt = host.lastRequest!.order.receipt!;
      expect(receipt.sno, 'usn_income');
      expect(receipt.items, hasLength(1));
      final item = receipt.items.first;
      expect(item.name, 'Pro plan');
      expect(item.sum, 149.9);
      expect(item.quantity, 1);
      expect(item.paymentMethod, 'full_payment');
      expect(item.paymentObject, 'service');
      expect(item.tax, 'vat20');
    });

    test('a fractional quantity is refused instead of silently truncated', () {
      // Both native SDKs type quantity as a 32-bit int; rounding 0.5 kg to 0
      // would change the fiscal document and the signature computed from it.
      expect(
        () => robokassa.pay(
          params(
            receipt: const Receipt(
              items: <ReceiptItem>[
                ReceiptItem(name: 'Coffee beans', cost: 900, quantity: 0.5),
              ],
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('result conversion', () {
    test('a success carries the opKey and decoded state codes', () async {
      final result = await robokassa.pay(params());

      expect(result.isSuccess, isTrue);
      expect(result.invoiceId, 42);
      expect(result.opKey, 'op-key-1');
      expect(result.requestResult, RequestResultCode.success);
      expect(result.stateCode, PaymentStateCode.paid);
      expect(result.isHeld, isFalse);
    });

    test('a hold result reports state 20 as held', () async {
      host.result = RkPaymentResultMessage(
        outcome: RkPaymentOutcome.success,
        invoiceId: 42,
        stateCode: '20',
        resultCode: '0',
      );
      final result = await robokassa.payWithHold(params());
      expect(result.isSuccess, isTrue);
      expect(result.isHeld, isTrue);
      expect(result.stateCode, PaymentStateCode.holdSuccess);
    });

    test('a cancellation is distinguishable from a failure', () async {
      host.result = RkPaymentResultMessage(outcome: RkPaymentOutcome.canceled);
      final result = await robokassa.pay(params());
      expect(result.isCanceled, isTrue);
      expect(result.isError, isFalse);
      expect(result.invoiceId, isNull);
    });

    test('an error surfaces its message and codes', () async {
      host.result = RkPaymentResultMessage(
        outcome: RkPaymentOutcome.error,
        resultCode: '1',
        stateCode: '10',
        errorMessage: 'Invalid signature',
      );
      final result = await robokassa.pay(params());
      expect(result.isError, isTrue);
      expect(result.errorMessage, 'Invalid signature');
      expect(result.requestResult, RequestResultCode.signatureError);
      expect(result.stateCode, PaymentStateCode.cancelledNotPaid);
      expect(result.diagnostics, contains('Invalid signature'));
    });

    test('empty strings from the platform become nulls', () async {
      host.result = RkPaymentResultMessage(
        outcome: RkPaymentOutcome.success,
        invoiceId: 0,
        opKey: '',
        stateDescription: '',
      );
      final result = await robokassa.pay(params());
      expect(result.invoiceId, isNull);
      expect(result.opKey, isNull);
      expect(result.description, isNull);
    });
  });

  group('argument guards', () {
    test('a saved-card payment without a token is refused locally', () {
      expect(() => robokassa.payWithSavedCard(params()), throwsArgumentError);
      expect(host.lastCall, isNull);
    });

    test('a saved-card payment with a token reaches the platform', () async {
      await robokassa.payWithSavedCard(params(token: 'op-key-1'));
      expect(host.lastRequest!.mode, RkPaymentMode.savedCard);
      expect(host.lastRequest!.order.token, 'op-key-1');
    });

    test('chargeRecurring needs a previous invoice', () {
      expect(() => robokassa.chargeRecurring(params()), throwsArgumentError);
      expect(host.lastCall, isNull);
    });

    test('chargeRecurring passes the parent invoice through', () async {
      expect(
        await robokassa.chargeRecurring(params(previousInvoiceId: 41)),
        isTrue,
      );
      expect(host.lastCall, 'chargeRecurring');
      expect(host.lastRequest!.order.previousInvoiceId, 41);
    });

    test('invalid params never reach the platform', () {
      expect(
        () => robokassa.pay(
          PaymentParams(
            order: OrderParams(orderSum: 10, description: 'x' * 101),
          ),
        ),
        throwsArgumentError,
      );
      expect(host.lastCall, isNull);
    });

    test('the native flow requires password #2', () {
      final publishable = Robokassa(
        credentials: const RobokassaCredentials.publishable(
          merchantLogin: 'demo',
          password1: 'password_1',
        ),
      );
      addTearDown(publishable.dispose);
      expect(() => publishable.pay(params()), throwsStateError);
    });
  });

  group('hold operations', () {
    test(
      'confirmHold and cancelHold reach their own channel methods',
      () async {
        expect(await robokassa.confirmHold(params(isHold: true)), isTrue);
        expect(host.lastCall, 'confirmHold');

        expect(await robokassa.cancelHold(params(isHold: true)), isTrue);
        expect(host.lastCall, 'cancelHold');
      },
    );

    test('a refusal is returned as false, not thrown', () async {
      host.boolResult = false;
      expect(await robokassa.confirmHold(params(isHold: true)), isFalse);
    });
  });

  group('error translation', () {
    test('a PlatformException becomes RobokassaNativeException', () async {
      host.throwOnCall = PlatformException(
        code: 'no_activity',
        message: 'No foreground Activity',
      );
      await expectLater(
        robokassa.pay(params()),
        throwsA(
          isA<RobokassaNativeException>()
              .having((e) => e.code, 'code', 'no_activity')
              .having((e) => e.message, 'message', 'No foreground Activity'),
        ),
      );
    });

    test(
      'isNativeSdkAvailable answers true when the bridge responds',
      () async {
        expect(await robokassa.isNativeSdkAvailable(), isTrue);
      },
    );

    test(
      'isNativeSdkAvailable answers false with no handler registered',
      () async {
        TestRobokassaHostApi.setUp(null);
        expect(await robokassa.isNativeSdkAvailable(), isFalse);
      },
    );

    test('checkPaymentState needs an invoice id', () {
      expect(
        () => robokassa.checkPaymentState(params(invoiceId: null)),
        throwsArgumentError,
      );
    });

    test(
      'checkPaymentState uses the native path when it is available',
      () async {
        final result = await robokassa.checkPaymentState(params());
        expect(host.lastCall, 'checkPaymentState');
        expect(result.isSuccess, isTrue);
      },
    );
  });
}
