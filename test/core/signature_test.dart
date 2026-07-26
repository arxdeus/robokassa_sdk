import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

/// Every expected digest in this file was computed **outside** this package
/// (with .NET's `System.Security.Cryptography`) from the literal pre-image
/// quoted in the test name. That keeps the assertions independent of the
/// implementation: if `RobokassaSignature` assembled the wrong pre-image, the
/// hash would not match even though both sides use the same MD5.
void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
  );

  group('payment init', () {
    test('demo:11.00:5:password_1', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.base, 'demo:11.00:5:password_1');
      expect(signature.value, 'defb716d86f4f999b152ee51b7c8b5e2');
    });

    test('signs OutSum literally — 11 and 11.00 differ', () {
      final unpadded = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11',
        invoiceId: 5,
      );
      expect(unpadded.base, 'demo:11:5:password_1');
      expect(unpadded.value, '1d2fea40f7613de53b4057909984c72f');
      expect(
        unpadded.value,
        isNot('defb716d86f4f999b152ee51b7c8b5e2'),
        reason: 'a different OutSum spelling must produce a different hash',
      );
    });

    test('an absent invoice id leaves an empty operand', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: null,
      );
      expect(signature.base, 'demo:11.00::password_1');
      expect(signature.value, 'accf2c5ae44a5c3a15bd27bfda3a04dd');
    });

    test('invoiceId 0 is treated as absent', () {
      expect(
        RobokassaSignature.forPaymentInit(
          credentials: credentials,
          outSum: '11.00',
          invoiceId: 0,
        ).base,
        'demo:11.00::password_1',
      );
    });

    test('a hold signs the literal word "true" for StepByStep', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        stepByStep: true,
      );
      expect(signature.base, 'demo:11.00:5:true:password_1');
      expect(signature.value, '022c5f352b7e3b9864078a1617e05ed4');
    });

    test('Token is the last modifier before the password', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        token: 'op-key-1',
      );
      expect(signature.base, 'demo:11.00:5:op-key-1:password_1');
      expect(signature.value, '583f886fdee8c8eb71d467b4e2eec28f');
    });

    test(
      'modifiers keep their documented order regardless of argument order',
      () {
        const encodedReceipt =
            '%7B%22items%22%3A%5B%7B%22name%22%3A%22Boots%22%2C%22sum%22%3A100.0'
            '%2C%22quantity%22%3A1%7D%5D%7D';
        final signature = RobokassaSignature.forPaymentInit(
          credentials: credentials,
          outSum: '100.00',
          invoiceId: 42,
          // Deliberately named out of chain order.
          token: 'op-key-1',
          stepByStep: true,
          receipt: encodedReceipt,
        );
        // Receipt -> StepByStep -> ... -> Token -> Password#1
        expect(
          signature.base,
          'demo:100.00:42:$encodedReceipt:true:op-key-1:password_1',
        );
        expect(signature.value, '6f2f3fac40874b4bfbadfa06dd86242c');
      },
    );

    test('an absent modifier is omitted entirely, leaving no empty slot', () {
      const encodedReceipt =
          '%7B%22items%22%3A%5B%7B%22name%22%3A%22Boots%22%2C%22sum%22%3A100.0'
          '%2C%22quantity%22%3A1%7D%5D%7D';
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '100.00',
        invoiceId: 42,
        receipt: encodedReceipt,
        stepByStep: true,
        // No Token: the chain must close straight into the password, not `::`.
      );
      expect(signature.base, 'demo:100.00:42:$encodedReceipt:true:password_1');
      expect(signature.base, isNot(contains('::')));
      expect(signature.value, '655504866c996002e03d802710a9a7fd');
    });

    test('the full ReturnURL modifier chain is ordered as documented', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        receipt: 'R',
        stepByStep: true,
        resultUrl2: 'U2',
        successUrl2: 'S2',
        successUrl2Method: 'GET',
        failUrl2: 'F2',
        failUrl2Method: 'POST',
        token: 'T',
      );
      expect(
        signature.base,
        'demo:11.00:5:R:true:U2:S2:GET:F2:POST:T:password_1',
      );
    });
  });

  group('user parameters', () {
    test('a single shp_ parameter is appended after the password', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        userParameters: UserParameters({'item': '2'}),
      );
      expect(signature.base, 'demo:11.00:5:password_1:shp_item=2');
      expect(signature.value, '1d7998821beab7f5b32887e3fc7e0acc');
    });

    test('several shp_ parameters are sorted by name, not insertion order', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        // Deliberately out of order.
        userParameters: UserParameters({'item': '2', 'b': '2', 'a': '1'}),
      );
      expect(
        signature.base,
        'demo:11.00:5:password_1:shp_a=1:shp_b=2:shp_item=2',
      );
      expect(signature.value, '0be7d6e12b59280117074953f080c29b');
    });

    test('the shp_ prefix is optional on input and always emitted', () {
      final prefixed = UserParameters({'shp_a': '1', 'shp_b': '2'});
      final bare = UserParameters({'a': '1', 'b': '2'});
      expect(prefixed.signatureSegments, bare.signatureSegments);
      expect(bare.signatureSegments, <String>['shp_a=1', 'shp_b=2']);
    });

    test('keys that collide after normalisation are rejected', () {
      expect(
        () => UserParameters({'a': '1', 'shp_a': '2'}),
        throwsArgumentError,
      );
    });

    test('non-string values are stringified', () {
      expect(
        UserParameters({
          'n': 7,
          'flag': true,
          'nothing': null,
        }).signatureSegments,
        <String>['shp_flag=true', 'shp_n=7', 'shp_nothing='],
      );
    });

    test('fromRequest keeps only shp_ entries, with their original case', () {
      // Robokassa's docs use `Shp_`; its mobile SDKs use `shp_`. Rewriting the
      // case here would change the signature base and break verification, so
      // whatever arrived is what gets signed.
      final extracted = UserParameters.fromRequest(<String, Object?>{
        'OutSum': '11.00',
        'InvId': '5',
        'shp_a': '1',
        'Shp_b': '2',
        'SHP_c': '3',
      });
      expect(extracted.signatureSegments, <String>[
        'SHP_c=3',
        'Shp_b=2',
        'shp_a=1',
      ]);
    });

    test('a supplied prefix keeps its case; a missing one gets shp_', () {
      expect(UserParameters({'Shp_item': '2'}).signatureSegments, <String>[
        'Shp_item=2',
      ]);
      expect(UserParameters({'item': '2'}).signatureSegments, <String>[
        'shp_item=2',
      ]);
    });

    test('Shp_ and shp_ produce different signatures, as Robokassa warns', () {
      String baseFor(String key) => RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        userParameters: UserParameters({key: '2'}),
      ).base;

      expect(baseFor('Shp_item'), 'demo:11.00:5:password_1:Shp_item=2');
      expect(baseFor('shp_item'), 'demo:11.00:5:password_1:shp_item=2');
      expect(baseFor('Shp_item'), isNot(baseFor('shp_item')));
    });

    test('lookup is forgiving about case even though signing is not', () {
      final params = UserParameters({'Shp_orderId': '7'});
      expect(params['Shp_orderId'], '7');
      expect(params['shp_orderid'], '7');
      expect(params['orderId'], '7');
    });

    test('names Robokassa rejects are refused up front', () {
      // Docs: only Latin letters, digits and underscores after the prefix.
      expect(() => UserParameters({'order-id': '1'}), throwsArgumentError);
      expect(() => UserParameters({'shp_': '1'}), throwsArgumentError);
      expect(() => UserParameters({'заказ': '1'}), throwsArgumentError);
    });
  });

  group('callbacks', () {
    test('ResultURL uses password #2 and drops MerchantLogin', () {
      final signature = RobokassaSignature.forResultUrl(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.base, '11.00:5:password_2');
      expect(signature.value, '8472748fd7990fe64962926dd4f42d42');
    });

    test('SuccessURL is the same shape but uses password #1', () {
      final signature = RobokassaSignature.forSuccessUrl(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.base, '11.00:5:password_1');
      expect(signature.value, 'be54f986c8176fccc857921adf11c3fb');
    });

    test('ResultURL folds in shp_ parameters', () {
      final signature = RobokassaSignature.forResultUrl(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
        userParameters: UserParameters({'b': '2', 'a': '1'}),
      );
      expect(signature.base, '11.00:5:password_2:shp_a=1:shp_b=2');
      expect(signature.value, '01ed33740ec749aea4f4c494d3da4ebb');
    });

    test('ResultURL without password #2 fails loudly', () {
      const publishable = RobokassaCredentials.publishable(
        merchantLogin: 'demo',
        password1: 'password_1',
      );
      expect(
        () => RobokassaSignature.forResultUrl(
          credentials: publishable,
          outSum: '11.00',
          invoiceId: 5,
        ),
        throwsStateError,
      );
    });
  });

  group('state and hold operations', () {
    test('OpStateExt is MerchantLogin:InvoiceID:password #2', () {
      final signature = RobokassaSignature.forOperationState(
        credentials: credentials,
        invoiceId: 5,
      );
      expect(signature.base, 'demo:5:password_2');
      expect(signature.value, '9d4c6ee522d007f6c3cac58596864105');
    });

    test('hold cancel signs an empty OutSum operand — note the "::"', () {
      final signature = RobokassaSignature.forHoldCancel(
        credentials: credentials,
        invoiceId: 5,
      );
      expect(signature.base, 'demo::5:password_1');
      expect(signature.value, '4422c310764ab77315ee2231491437de');
    });

    test('hold confirm signs OutSum, unlike cancel', () {
      final signature = RobokassaSignature.forHoldConfirm(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.base, 'demo:11.00:5:password_1');
      expect(signature.value, 'defb716d86f4f999b152ee51b7c8b5e2');
    });

    test('recurring excludes PreviousInvoiceID from the signature', () {
      final signature = RobokassaSignature.forRecurring(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.base, 'demo:11.00:5:password_1');
      expect(signature.value, 'defb716d86f4f999b152ee51b7c8b5e2');
    });
  });

  group('hash algorithms', () {
    const base = 'demo:11.00:5:password_1';

    test('SHA-1', () {
      expect(
        HashAlgorithm.sha1.hash(base),
        '4e1afc0afe5e92c9984a7592b46c43ae79b200dd',
      );
    });

    test('SHA-256', () {
      expect(
        HashAlgorithm.sha256.hash(base),
        'b20b71778af6b9e94dfc0472dfb8f100db1920f1c2bdbc2a81dddcb4c70544e3',
      );
    });

    test('SHA-512', () {
      expect(
        HashAlgorithm.sha512.hash(base),
        'bd8f6c8771549f669d3c2d9fd054487e'
        '0f5d7b7512772ab48696dd2912d04a9c'
        '9cfe5b5ab0868f5502fc77a2413b6c08'
        '19766c699e826d0dc611621c89087f80',
      );
    });

    test('the credential algorithm selects the digest', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials.copyWith(algorithm: HashAlgorithm.sha256),
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.algorithm, HashAlgorithm.sha256);
      expect(
        signature.value,
        'b20b71778af6b9e94dfc0472dfb8f100db1920f1c2bdbc2a81dddcb4c70544e3',
      );
    });

    test('digest length identifies the algorithm', () {
      expect(HashAlgorithm.fromDigestLength('a' * 32), HashAlgorithm.md5);
      expect(HashAlgorithm.fromDigestLength('a' * 64), HashAlgorithm.sha256);
      expect(HashAlgorithm.fromDigestLength('a' * 33), isNull);
    });
  });

  group('comparison', () {
    test('matches() ignores case, as Robokassa does', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.matches('DEFB716D86F4F999B152EE51B7C8B5E2'), isTrue);
      expect(signature.matches('defb716d86f4f999b152ee51b7c8b5e2'), isTrue);
      expect(signature.matches('deadbeef'), isFalse);
      expect(signature.matches(null), isFalse);
    });

    test('constantTimeEquals rejects a length mismatch', () {
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('ABC', 'abc'), isTrue);
    });

    test('toString never leaks the pre-image', () {
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '11.00',
        invoiceId: 5,
      );
      expect(signature.toString(), isNot(contains('password_1')));
      expect(signature.toString(), contains('<redacted>'));
    });

    test('credentials never render their passwords', () {
      final rendered = credentials.toString();
      expect(rendered, isNot(contains('password_1')));
      expect(rendered, isNot(contains('password_2')));
      expect(rendered, contains('demo'));
    });
  });
}
