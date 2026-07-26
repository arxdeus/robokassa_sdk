import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// Compiles and runs the snippets from README.md so the documentation cannot
/// drift away from the public API. If this file stops compiling, the README is
/// wrong — fix both together.
void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'my_shop',
    password1: 'password_1',
    password2: 'password_2',
    isTest: true,
  );

  test('README "Quick start" builds valid params', () {
    const params = PaymentParams(
      order: OrderParams(
        invoiceId: 1042,
        orderSum: 149.90,
        description: 'Pro plan, 1 month',
        receipt: Receipt(
          items: <ReceiptItem>[
            ReceiptItem(
              name: 'Pro plan',
              sum: 149.90,
              quantity: 1,
              tax: Tax.vat20,
            ),
          ],
        ),
      ),
      customer: CustomerParams(email: 'buyer@example.com', culture: Culture.ru),
    );

    expect(params.validate, returnsNormally);
    expect(params.order.receipt!.total, 149.90);
  });

  test('README "Payment links" produces a Robokassa URL', () {
    const params = PaymentParams(
      order: OrderParams(invoiceId: 1042, orderSum: 149.90),
    );
    final uri = RobokassaLinkBuilder(credentials: credentials).buildUri(params);

    expect(uri.host, 'auth.robokassa.ru');
    expect(uri.path, '/Merchant/Index.aspx');
    expect(uri.queryParameters['SignatureValue'], isNotEmpty);
    expect(uri.queryParameters['IsTest'], '1');
  });

  test('README "Verifying payments" acknowledges a genuine notification', () {
    // Build a notification the way Robokassa would, then verify it the way the
    // README's handler does.
    final signature = RobokassaSignature.forResultUrl(
      credentials: credentials,
      outSum: '149.90',
      invoiceId: 1042,
    );
    final formFields = <String, String>{
      'OutSum': '149.90',
      'InvId': '1042',
      'SignatureValue': signature.value,
    };

    final callback = RobokassaCallback.parse(
      formFields,
      kind: RobokassaCallbackKind.result,
      credentials: credentials,
    );

    expect(callback.isConfirmedPayment, isTrue);
    expect(callback.acknowledgement, 'OK1042');
    expect(callback.invoiceId, 1042);
    expect(callback.outSum, 149.90);
  });

  test('README "publishable" credentials refuse password #2 work', () {
    const publishable = RobokassaCredentials.publishable(
      merchantLogin: 'my_shop',
      password1: 'password_1',
    );
    // Links still work…
    expect(
      () => RobokassaLinkBuilder(credentials: publishable).buildUri(
        const PaymentParams(order: OrderParams(orderSum: 1, invoiceId: 1)),
      ),
      returnsNormally,
    );
    // …but anything needing password #2 fails loudly rather than silently.
    expect(
      () => RobokassaSignature.forOperationState(
        credentials: publishable,
        invoiceId: 1,
      ),
      throwsStateError,
    );
  });

  test('README modifier order matches the implementation', () {
    final signature = RobokassaSignature.forPaymentInit(
      credentials: credentials,
      outSum: '149.90',
      invoiceId: 1042,
      receipt: 'RECEIPT',
      stepByStep: true,
      resultUrl2: 'RESULT2',
      successUrl2: 'SUCCESS2',
      successUrl2Method: 'GET',
      failUrl2: 'FAIL2',
      failUrl2Method: 'POST',
      token: 'TOKEN',
      userParameters: UserParameters({'b': '2', 'a': '1'}),
    );

    expect(
      signature.base,
      'my_shop:149.90:1042:'
      'RECEIPT:true:RESULT2:SUCCESS2:GET:FAIL2:POST:TOKEN:'
      'password_1:shp_a=1:shp_b=2',
    );
  });
}
