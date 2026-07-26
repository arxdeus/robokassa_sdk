import 'package:flutter_test/flutter_test.dart';
import 'package:robokassa_sdk/robokassa_sdk.dart';

void main() {
  const credentials = RobokassaCredentials(
    merchantLogin: 'demo',
    password1: 'password_1',
    password2: 'password_2',
  );

  group('serialisation', () {
    test(
      'key order matches the official SDKs — the signature depends on it',
      () {
        const receipt = Receipt(
          sno: TaxSystem.osn,
          items: <ReceiptItem>[
            ReceiptItem(name: 'Boots', sum: 100, quantity: 1, tax: Tax.vat20),
          ],
        );
        expect(
          receipt.toJsonString(),
          '{"sno":"osn","items":[{"name":"Boots","sum":100.0,"quantity":1,'
          '"tax":"vat20"}]}',
        );
      },
    );

    test('sno is omitted when absent', () {
      const receipt = Receipt(
        items: <ReceiptItem>[ReceiptItem(name: 'Boots', sum: 100, quantity: 1)],
      );
      expect(receipt.toJsonString(), isNot(contains('sno')));
      expect(
        receipt.toJsonString(),
        '{"items":[{"name":"Boots","sum":100.0,"quantity":1}]}',
      );
    });

    test('every optional field renders in declaration order', () {
      const receipt = Receipt(
        items: <ReceiptItem>[
          ReceiptItem(
            name: 'Boots',
            sum: 60,
            quantity: 2,
            cost: 30,
            paymentMethod: PaymentMethod.fullPayment,
            paymentObject: PaymentObject.commodity,
            tax: Tax.vat20,
          ),
        ],
      );
      expect(
        receipt.toJsonString(),
        '{"items":[{"name":"Boots","sum":60.0,"quantity":2,"cost":30.0,'
        '"payment_method":"full_payment","payment_object":"commodity",'
        '"tax":"vat20"}]}',
      );
    });

    test('non-ASCII item names are emitted unescaped', () {
      const receipt = Receipt(
        items: <ReceiptItem>[
          ReceiptItem(name: 'Ботинки детские', sum: 100, quantity: 1),
        ],
      );
      expect(receipt.toJsonString(), contains('"Ботинки детские"'));
      expect(receipt.toJsonString(), isNot(contains(r'\u')));
    });

    test('binary float noise is rounded away before signing', () {
      // 0.1 + 0.2 == 0.30000000000000004; left alone it would corrupt the hash.
      const receipt = Receipt(
        items: <ReceiptItem>[
          ReceiptItem(name: 'Noise', sum: 0.1 + 0.2, quantity: 1),
        ],
      );
      expect(receipt.toJsonString(), contains('"sum":0.3'));
      expect(receipt.toJsonString(), isNot(contains('0.30000000000000004')));
    });

    test('round-trips through JSON', () {
      const original = Receipt(
        sno: TaxSystem.usnIncome,
        items: <ReceiptItem>[
          ReceiptItem(
            name: 'Boots',
            sum: 60,
            quantity: 2,
            cost: 30,
            nomenclatureCode: 'ABC123',
            paymentMethod: PaymentMethod.prepayment,
            paymentObject: PaymentObject.service,
            tax: Tax.vat110,
          ),
        ],
      );
      expect(Receipt.fromJson(original.toJson()), original);
    });
  });

  group('signature integration', () {
    test('a receipt is hashed as its raw JSON', () {
      const receipt = Receipt(
        sno: TaxSystem.osn,
        items: <ReceiptItem>[
          ReceiptItem(name: 'Boots', sum: 100, quantity: 1, tax: Tax.vat20),
        ],
      );
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '100.00',
        invoiceId: 42,
        receipt: ReceiptSignatureMode.rawJson.render(receipt.toJsonString()),
      );
      // Pre-image hashed externally:
      // demo:100.00:42:{"sno":"osn","items":[{"name":"Boots","sum":100.0,
      // "quantity":1,"tax":"vat20"}]}:password_1
      expect(signature.value, '702238ef515f5035a525b85a6fdeab13');
    });

    test('cost-and-quantity lines hash as documented', () {
      const receipt = Receipt(
        items: <ReceiptItem>[
          ReceiptItem(
            name: 'Boots',
            sum: 60,
            quantity: 2,
            cost: 30,
            paymentMethod: PaymentMethod.fullPayment,
            paymentObject: PaymentObject.commodity,
            tax: Tax.vat20,
          ),
        ],
      );
      final signature = RobokassaSignature.forPaymentInit(
        credentials: credentials,
        outSum: '100.00',
        invoiceId: 42,
        receipt: ReceiptSignatureMode.rawJson.render(receipt.toJsonString()),
      );
      expect(signature.value, '593a7845635957d3f1ddb545cba4994b');
    });
  });

  group('totals and validation', () {
    test('total sums explicit line totals', () {
      const receipt = Receipt(
        items: <ReceiptItem>[
          ReceiptItem(name: 'A', sum: 10.5, quantity: 1),
          ReceiptItem(name: 'B', sum: 20.25, quantity: 3),
        ],
      );
      expect(receipt.total, 30.75);
    });

    test('a cost-only line derives its total as cost * quantity', () {
      const item = ReceiptItem(name: 'A', cost: 12.5, quantity: 4);
      expect(item.total, 50.0);
    });

    test('a line needs either sum or cost', () {
      expect(
        () => ReceiptItem(name: 'A', quantity: 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('an empty receipt is rejected when it is used', () {
      // The constructor stays `const`, so emptiness is caught on validate.
      const empty = Receipt(items: <ReceiptItem>[]);
      expect(empty.validate, throwsArgumentError);
      expect(empty.toJsonString, throwsArgumentError);
    });

    test('an over-long item name is rejected', () {
      final receipt = Receipt(
        items: <ReceiptItem>[ReceiptItem(name: 'x' * 129, sum: 1, quantity: 1)],
      );
      expect(receipt.validate, throwsArgumentError);
    });

    test('a non-positive quantity is rejected', () {
      const receipt = Receipt(
        items: <ReceiptItem>[ReceiptItem(name: 'A', sum: 1, quantity: 0)],
      );
      expect(receipt.validate, throwsArgumentError);
    });
  });

  group('enum wire values', () {
    test('every Tax value round-trips', () {
      for (final tax in Tax.values) {
        expect(Tax.tryParse(tax.wireValue), tax);
      }
    });

    test('every PaymentObject value round-trips', () {
      for (final object in PaymentObject.values) {
        expect(PaymentObject.tryParse(object.wireValue), object);
      }
    });

    test('every PaymentMethod value round-trips', () {
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.tryParse(method.wireValue), method);
      }
    });

    test('every TaxSystem value round-trips', () {
      for (final system in TaxSystem.values) {
        expect(TaxSystem.tryParse(system.wireValue), system);
      }
    });

    test('Android enum names mirror the Kotlin constants', () {
      expect(Tax.none.androidEnumName, 'NONE');
      expect(Tax.vat0.androidEnumName, 'VAT_0');
      expect(Tax.vat120.androidEnumName, 'VAT_120');
      expect(PaymentMethod.fullPrepayment.androidEnumName, 'FULL_PREPAYMENT');
      expect(
        PaymentObject.nonOperatingGain.androidEnumName,
        'NON_OPERATING_GAIN',
      );
      expect(TaxSystem.usnIncomeOutcome.androidEnumName, 'USN_INCOME_OUTCOME');
    });

    test('Culture translates to each platform spelling', () {
      expect(Culture.en.wireValue, 'en');
      // Upstream iOS spells English "eng".
      expect(Culture.en.iosCaseName, 'eng');
      expect(Culture.en.androidEnumName, 'EN');
      expect(Culture.ru.iosCaseName, 'ru');
      expect(Culture.tryParse('eng'), Culture.en);
      expect(Culture.tryParse('RU'), Culture.ru);
      expect(Culture.tryParse('de'), isNull);
    });

    test('Currency parses case-insensitively', () {
      expect(Currency.tryParse('usd'), Currency.usd);
      expect(Currency.tryParse('KZT'), Currency.kzt);
      expect(Currency.tryParse('GBP'), isNull);
    });

    test('unknown wire values parse to null rather than throwing', () {
      expect(Tax.tryParse('vat99'), isNull);
      expect(PaymentObject.tryParse(null), isNull);
    });
  });
}
