import 'dart:convert';

import 'package:meta/meta.dart';

import 'enums.dart';

/// Rounds [value] to two decimal places and renders it the way Robokassa's
/// own SDKs do (Gson / `JSONEncoder` render a `Double`, so an integral amount
/// keeps its `.0`).
///
/// Receipt amounts are documented as "целая часть не более 8 знаков, дробная
/// часть не более 2 знаков", so rounding here also removes binary-float noise
/// such as `0.30000000000000004` that would otherwise change the signature.
String formatReceiptAmount(double value) {
  final rounded = double.parse(value.toStringAsFixed(2));
  return rounded.toString();
}

/// A single line of a fiscal receipt (позиция чека).
@immutable
class ReceiptItem {
  /// Creates a receipt line.
  ///
  /// Either [sum] or [cost] must be supplied: [sum] is the total for the whole
  /// [quantity], [cost] is the price of one unit and Robokassa derives the
  /// total as `cost * quantity`.
  const ReceiptItem({
    required this.name,
    required this.quantity,
    this.sum,
    this.cost,
    this.nomenclatureCode,
    this.paymentMethod,
    this.paymentObject,
    this.tax,
  }) : assert(
         sum != null || cost != null,
         'A receipt item needs either `sum` (total) or `cost` (per unit).',
       );

  /// Название товара. Maximum 128 characters.
  ///
  /// Special characters such as quotes must be escaped by the caller — the
  /// JSON encoder escapes them for transport, but Robokassa's fiscal backend
  /// also imposes its own restrictions.
  final String name;

  /// Количество товаров.
  final num quantity;

  /// Полная сумма за итоговое количество данного товара, in roubles.
  final double? sum;

  /// Полная сумма за единицу товара, in roubles. May be sent instead of [sum].
  final double? cost;

  /// Маркировка товара (код маркировки) for goods requiring labelling.
  final String? nomenclatureCode;

  /// Признак способа расчёта. Falls back to the dashboard default when null.
  final PaymentMethod? paymentMethod;

  /// Признак предмета расчёта. Falls back to the dashboard default when null.
  final PaymentObject? paymentObject;

  /// Налоговая ставка for this line.
  final Tax? tax;

  /// Serialises this line.
  ///
  /// Key order is fixed and matches the field declaration order of the
  /// official Android SDK's `ReceiptItem`, because the encoded JSON is hashed
  /// into `SignatureValue` — reordering keys would invalidate the signature.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (sum != null) 'sum': num.parse(formatReceiptAmount(sum!)),
      'quantity': quantity,
      if (cost != null) 'cost': num.parse(formatReceiptAmount(cost!)),
      if (nomenclatureCode != null) 'nomenclature_code': nomenclatureCode,
      if (paymentMethod != null) 'payment_method': paymentMethod!.wireValue,
      if (paymentObject != null) 'payment_object': paymentObject!.wireValue,
      if (tax != null) 'tax': tax!.wireValue,
    };
  }

  /// Rebuilds a line from its JSON representation.
  factory ReceiptItem.fromJson(Map<String, Object?> json) {
    double? readAmount(Object? raw) => switch (raw) {
      null => null,
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

    return ReceiptItem(
      name: json['name']! as String,
      quantity: json['quantity'] as num? ?? 1,
      sum: readAmount(json['sum']),
      cost: readAmount(json['cost']),
      nomenclatureCode: json['nomenclature_code'] as String?,
      paymentMethod: PaymentMethod.tryParse(json['payment_method'] as String?),
      paymentObject: PaymentObject.tryParse(json['payment_object'] as String?),
      tax: Tax.tryParse(json['tax'] as String?),
    );
  }

  /// The total this line contributes to the order, whether expressed via [sum]
  /// or via [cost] × [quantity].
  double get total =>
      sum ?? double.parse((cost! * quantity).toStringAsFixed(2));

  @override
  String toString() => 'ReceiptItem(${jsonEncode(toJson())})';

  @override
  bool operator ==(Object other) =>
      other is ReceiptItem &&
      other.name == name &&
      other.quantity == quantity &&
      other.sum == sum &&
      other.cost == cost &&
      other.nomenclatureCode == nomenclatureCode &&
      other.paymentMethod == paymentMethod &&
      other.paymentObject == paymentObject &&
      other.tax == tax;

  @override
  int get hashCode => Object.hash(
    name,
    quantity,
    sum,
    cost,
    nomenclatureCode,
    paymentMethod,
    paymentObject,
    tax,
  );
}

/// A fiscal receipt (фискальный чек) attached to a payment.
///
/// When a receipt is present it participates in `SignatureValue`, so its
/// serialisation must be byte-stable. [toJsonString] guarantees that.
@immutable
class Receipt {
  /// Creates a receipt from its [items] and optional taxation system [sno].
  ///
  /// [items] must not be empty; that is checked by [validate] rather than by
  /// an assert, because `List.length` is not a constant expression and the
  /// constructor has to stay `const`.
  const Receipt({required this.items, this.sno});

  /// Система налогообложения. Optional when the shop has exactly one.
  final TaxSystem? sno;

  /// Позиции чека.
  final List<ReceiptItem> items;

  /// Serialises the receipt with `sno` first, then `items` — the field order
  /// used by both official SDKs.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (sno != null) 'sno': sno!.wireValue,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }

  /// Rebuilds a receipt from its JSON representation.
  factory Receipt.fromJson(Map<String, Object?> json) {
    final rawItems = (json['items'] as List<Object?>? ?? const <Object?>[])
        .cast<Map<String, Object?>>();
    return Receipt(
      sno: TaxSystem.tryParse(json['sno'] as String?),
      items: rawItems.map(ReceiptItem.fromJson).toList(growable: false),
    );
  }

  /// Throws [ArgumentError] when the receipt could not be fiscalised.
  void validate() {
    if (items.isEmpty) {
      throw ArgumentError.value(
        items,
        'items',
        'A receipt needs at least one item.',
      );
    }
    for (final item in items) {
      if (item.name.isEmpty) {
        throw ArgumentError.value(
          item.name,
          'items.name',
          'A receipt item needs a name.',
        );
      }
      if (item.name.length > 128) {
        throw ArgumentError.value(
          item.name,
          'items.name',
          'Item names are limited to 128 characters (got ${item.name.length})',
        );
      }
      if (item.quantity <= 0) {
        throw ArgumentError.value(
          item.quantity,
          'items.quantity',
          'Item "${item.name}" needs a positive quantity',
        );
      }
    }
  }

  /// The exact JSON string that is both signed and transmitted.
  ///
  /// Compact (no whitespace), non-ASCII characters left as-is — matching
  /// `Gson().toJson()` on Android and `JSONEncoder().encode()` on iOS.
  ///
  /// Calls [validate] first: an unfiscalisable receipt would otherwise be
  /// signed and rejected by Robokassa with an opaque error.
  String toJsonString() {
    validate();
    return jsonEncode(toJson());
  }

  /// Sum of every line, useful for cross-checking against `OutSum`.
  double get total => double.parse(
    items
        .fold<double>(0, (running, item) => running + item.total)
        .toStringAsFixed(2),
  );

  @override
  String toString() => 'Receipt(${toJsonString()})';

  @override
  bool operator ==(Object other) =>
      other is Receipt &&
      other.sno == sno &&
      other.items.length == items.length &&
      List.generate(
        items.length,
        (i) => items[i] == other.items[i],
      ).every((equal) => equal);

  @override
  int get hashCode => Object.hash(sno, Object.hashAll(items));
}
