import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
  );

  // Externally computed: md5("11.00:5:password_2")
  const resultSignature = '8472748fd7990fe64962926dd4f42d42';
  // Externally computed: md5("11.00:5:password_1")
  const successSignature = 'be54f986c8176fccc857921adf11c3fb';
  // Externally computed: md5("11.00:5:password_2:shp_a=1:shp_b=2")
  const resultSignatureWithShp = '01ed33740ec749aea4f4c494d3da4ebb';
  // Externally computed: md5("100.000000:7:password_2")
  const sixDecimalSignature = '1a28022ddbef9ce98e0c2e4ee2949ea3';

  group('ResultURL', () {
    test('the six-decimal OutSum production sends verifies', () {
      // Robokassa formats OutSum with six decimals in production. The
      // signature is over the literal text, so a reparse-and-reformat
      // anywhere in the path would break verification here.
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '100.000000',
          'InvId': '7',
          'SignatureValue': sixDecimalSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );

      expect(callback.isConfirmedPayment, isTrue);
      expect(callback.outSumRaw, '100.000000');
      expect(callback.outSum, 100.0);
      expect(callback.acknowledgement, 'OK7');
    });

    test('a six-decimal OutSum is not re-formatted before hashing', () {
      // Same amount, two-decimal text: a different pre-image, so the
      // six-decimal signature must NOT verify against it.
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '100.00',
          'InvId': '7',
          'SignatureValue': sixDecimalSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );

      expect(callback.isSignatureValid, isFalse);
      expect(callback.isConfirmedPayment, isFalse);
    });

    test('a correctly signed notification verifies', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': resultSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );

      expect(callback.isSignatureValid, isTrue);
      expect(callback.isConfirmedPayment, isTrue);
      expect(callback.invoiceId, 5);
      expect(callback.outSum, 11.0);
      expect(callback.outSumRaw, '11.00');
      expect(callback.signatureError, isNull);
    });

    test('the acknowledgement body is OK + invoice number', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': resultSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.acknowledgement, 'OK5');
    });

    test('a tampered amount fails verification', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          // Attacker inflates the amount but keeps the original signature.
          'OutSum': '9999.00',
          'InvId': '5',
          'SignatureValue': resultSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isFalse);
      expect(callback.isConfirmedPayment, isFalse);
      expect(callback.signatureError, contains('Signature mismatch'));
    });

    test('a SuccessURL signature is rejected on ResultURL', () {
      // Password #1 must not be accepted where password #2 is required.
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': successSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isFalse);
    });

    test('shp_ parameters participate in verification', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'shp_b': '2',
          'shp_a': '1',
          'SignatureValue': resultSignatureWithShp,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
      expect(callback.userParameters['a'], '1');
      expect(callback.userParameters['shp_b'], '2');
    });

    test('dropping a shp_ parameter breaks verification', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'shp_a': '1',
          'SignatureValue': resultSignatureWithShp,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isFalse);
    });

    test('parameter names are matched case-insensitively', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'outsum': '11.00',
          'invid': '5',
          'signaturevalue': resultSignature,
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
    });

    test('an uppercase signature from Robokassa is accepted', () {
      final callback = RobokassaCallback.parse(
        <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': resultSignature.toUpperCase(),
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
    });

    test('a missing signature is reported, not crashed on', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{'OutSum': '11.00', 'InvId': '5'},
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isFalse);
      expect(callback.signatureError, contains('no SignatureValue'));
    });

    test('a missing OutSum is reported', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{'InvId': '5', 'SignatureValue': resultSignature},
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isFalse);
      expect(callback.signatureError, contains('OutSum'));
    });

    test('extra fields Robokassa sends are surfaced', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': resultSignature,
          'IncCurrLabel': 'BankCard',
          'EMail': 'buyer@example.com',
          'Fee': '0.55',
          'PaymentMethod': 'BankCard',
        },
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.incCurrLabel, 'BankCard');
      expect(callback.email, 'buyer@example.com');
      expect(callback.fee, 0.55);
      expect(callback.paymentMethod, 'BankCard');
      expect(callback.raw, containsPair('IncCurrLabel', 'BankCard'));
    });
  });

  group('SuccessURL', () {
    test('verifies against password #1', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': successSignature,
          'Culture': 'ru',
        },
        kind: RobokassaCallbackKind.success,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
      expect(callback.culture, 'ru');
    });

    test('a valid SuccessURL is still not a confirmed payment', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': successSignature,
        },
        kind: RobokassaCallbackKind.success,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
      expect(
        callback.isConfirmedPayment,
        isFalse,
        reason: 'only a ResultURL notification proves payment',
      );
    });

    test('works with publishable credentials — no password #2 needed', () {
      const publishable = RobokassaCredentials.publishable(
        merchantLogin: 'demo',
        password1: 'password_1',
      );
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'SignatureValue': successSignature,
        },
        kind: RobokassaCallbackKind.success,
        credentials: publishable,
      );
      expect(callback.isSignatureValid, isTrue);
    });
  });

  group('FailURL', () {
    test('is parsed without a signature and never counts as confirmed', () {
      final callback = RobokassaCallback.parse(
        const <String, String>{
          'OutSum': '11.00',
          'InvId': '5',
          'Culture': 'ru',
        },
        kind: RobokassaCallbackKind.fail,
        credentials: credentials,
      );
      expect(callback.invoiceId, 5);
      expect(callback.isSignatureValid, isFalse);
      expect(callback.isConfirmedPayment, isFalse);
      expect(callback.signatureError, isNull);
    });
  });

  group('transports', () {
    test('parses a full callback URI', () {
      final callback = RobokassaCallback.parseUri(
        Uri.parse(
          'https://shop.example.com/robokassa/result'
          '?OutSum=11.00&InvId=5&SignatureValue=$resultSignature',
        ),
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
    });

    test('parses a form-encoded POST body', () {
      final callback = RobokassaCallback.parseFormBody(
        'OutSum=11.00&InvId=5&SignatureValue=$resultSignature',
        kind: RobokassaCallbackKind.result,
        credentials: credentials,
      );
      expect(callback.isSignatureValid, isTrue);
    });
  });
}
