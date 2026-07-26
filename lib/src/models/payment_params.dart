import 'package:meta/meta.dart';

import '../core/user_parameters.dart';
import 'enums.dart';
import 'receipt.dart';

/// Everything about the order being paid for.
///
/// Mirrors `OrderParams` in the official Android and iOS SDKs so values map
/// one-to-one across the platform bridge.
@immutable
class OrderParams {
  /// Creates order parameters.
  const OrderParams({
    required this.orderSum,
    this.invoiceId,
    this.previousInvoiceId,
    this.description,
    this.incCurrLabel,
    this.token,
    this.isRecurrent = false,
    this.isHold = false,
    this.outSumCurrency,
    this.expirationDate,
    this.receipt,
  }) : assert(orderSum > 0, 'orderSum must be greater than zero');

  /// Номер счёта в магазине (`InvId`).
  ///
  /// Optional, but strongly recommended — it must be unique per payment. When
  /// `null`, Robokassa allocates a number itself and the signature is built
  /// with an empty invoice operand.
  final int? invoiceId;

  /// Номер счёта первого платежа in a recurring series (`PreviousInvoiceID`).
  final int? previousInvoiceId;

  /// Требуемая к получению сумма (`OutSum`), in roubles.
  final double orderSum;

  /// Описание покупки (`Description`). Maximum 100 characters.
  final String? description;

  /// Предлагаемый способ оплаты (`IncCurrLabel`).
  final String? incCurrLabel;

  /// `OpKey` of a previous operation whose saved card should be reused
  /// (`Token`).
  final String? token;

  /// Marks the invoice as the first of a recurring series (`Recurring=true`).
  final bool isRecurrent;

  /// Requests two-stage payment — funds are held, not captured
  /// (`StepByStep=true`).
  final bool isHold;

  /// Currency the shop priced the order in (`OutSumCurrency`).
  final Currency? outSumCurrency;

  /// Срок действия счёта (`ExpirationDate`).
  final DateTime? expirationDate;

  /// Фискальный чек (`Receipt`). Participates in `SignatureValue`.
  final Receipt? receipt;

  /// Validates the fields Robokassa constrains, throwing [ArgumentError] on
  /// the first violation.
  ///
  /// Called automatically by the link builder and the native bridge.
  void validate() {
    if (orderSum <= 0) {
      throw ArgumentError.value(
        orderSum,
        'orderSum',
        'Order sum must be greater than zero',
      );
    }
    final desc = description;
    if (desc != null && desc.length > 100) {
      throw ArgumentError.value(
        desc,
        'description',
        'Description must be at most 100 characters (got ${desc.length})',
      );
    }
    if (invoiceId != null && invoiceId! < 0) {
      throw ArgumentError.value(
        invoiceId,
        'invoiceId',
        'Invoice id must not be negative',
      );
    }
    if (isRecurrent && isHold) {
      throw ArgumentError(
        'A payment cannot be both recurring (`isRecurrent`) and two-stage '
        '(`isHold`) — Robokassa rejects the combination.',
      );
    }
    receipt?.validate();
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Passing `null` keeps the current value; use the dedicated `clear*` flags
  /// where you need to unset something.
  OrderParams copyWith({
    int? invoiceId,
    int? previousInvoiceId,
    double? orderSum,
    String? description,
    String? incCurrLabel,
    String? token,
    bool? isRecurrent,
    bool? isHold,
    Currency? outSumCurrency,
    DateTime? expirationDate,
    Receipt? receipt,
  }) => OrderParams(
    invoiceId: invoiceId ?? this.invoiceId,
    previousInvoiceId: previousInvoiceId ?? this.previousInvoiceId,
    orderSum: orderSum ?? this.orderSum,
    description: description ?? this.description,
    incCurrLabel: incCurrLabel ?? this.incCurrLabel,
    token: token ?? this.token,
    isRecurrent: isRecurrent ?? this.isRecurrent,
    isHold: isHold ?? this.isHold,
    outSumCurrency: outSumCurrency ?? this.outSumCurrency,
    expirationDate: expirationDate ?? this.expirationDate,
    receipt: receipt ?? this.receipt,
  );

  @override
  String toString() =>
      'OrderParams(invoiceId: $invoiceId, orderSum: $orderSum, '
      'description: $description, isHold: $isHold, isRecurrent: $isRecurrent)';
}

/// Everything about the payer.
///
/// Mirrors `CustomerParams` in the official SDKs.
@immutable
class CustomerParams {
  /// Creates customer parameters.
  const CustomerParams({this.culture, this.email, this.ip});

  /// Язык страницы оплаты (`Culture`). Falls back to browser locale.
  final Culture? culture;

  /// Pre-fills the payer's email on the Robokassa form (`Email`).
  final String? email;

  /// Payer's IP address (`UserIp`). Recommended for anti-fraud.
  ///
  /// When set it becomes part of `SignatureValue`.
  final String? ip;

  /// Validates the email shape, throwing [ArgumentError] when malformed.
  void validate() {
    final value = email;
    if (value == null || value.isEmpty) return;
    // Deliberately permissive: Robokassa is the authority on acceptance, this
    // only catches obvious typos before a round-trip.
    final looksValid = RegExp(
      r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$',
    ).hasMatch(value);
    if (!looksValid) {
      throw ArgumentError.value(value, 'email', 'Email has invalid format');
    }
  }

  /// Returns a copy with the given fields replaced.
  CustomerParams copyWith({Culture? culture, String? email, String? ip}) =>
      CustomerParams(
        culture: culture ?? this.culture,
        email: email ?? this.email,
        ip: ip ?? this.ip,
      );

  @override
  String toString() =>
      'CustomerParams(culture: ${culture?.wireValue}, email: $email, ip: $ip)';
}

/// Appearance of the native checkout screen.
///
/// Mirrors `ViewParams` in the official SDKs. These settings affect only the
/// native WebView chrome, not the Robokassa page itself, so they have no
/// effect on a link built with `RobokassaLinkBuilder`.
@immutable
class ViewParams {
  /// Creates view parameters.
  const ViewParams({
    this.toolbarBgColor,
    this.toolbarTextColor,
    this.toolbarText,
    this.hasToolbar = true,
  });

  /// Toolbar background colour as a hex string, e.g. `#000000`.
  final String? toolbarBgColor;

  /// Toolbar text colour as a hex string, e.g. `#cccccc`.
  final String? toolbarTextColor;

  /// Toolbar title. Maximum 30 characters.
  final String? toolbarText;

  /// Whether the native screen shows a toolbar at all.
  final bool hasToolbar;

  /// Validates colours and title length, throwing [ArgumentError] on failure.
  void validate() {
    for (final entry in <String, String?>{
      'toolbarBgColor': toolbarBgColor,
      'toolbarTextColor': toolbarTextColor,
    }.entries) {
      final color = entry.value;
      if (color == null || color.isEmpty) continue;
      if (!RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(color)) {
        throw ArgumentError.value(
          color,
          entry.key,
          'Colour must be #RRGGBB or #AARRGGBB',
        );
      }
    }
    final text = toolbarText;
    if (text != null && text.length > 30) {
      throw ArgumentError.value(
        text,
        'toolbarText',
        'Toolbar text must be at most 30 characters (got ${text.length})',
      );
    }
  }

  /// Returns a copy with the given fields replaced.
  ViewParams copyWith({
    String? toolbarBgColor,
    String? toolbarTextColor,
    String? toolbarText,
    bool? hasToolbar,
  }) => ViewParams(
    toolbarBgColor: toolbarBgColor ?? this.toolbarBgColor,
    toolbarTextColor: toolbarTextColor ?? this.toolbarTextColor,
    toolbarText: toolbarText ?? this.toolbarText,
    hasToolbar: hasToolbar ?? this.hasToolbar,
  );

  @override
  String toString() =>
      'ViewParams(toolbarText: $toolbarText, hasToolbar: $hasToolbar)';
}

/// The complete description of one payment.
///
/// Mirrors `PaymentParams` in the official SDKs, plus [userParameters] for the
/// `shp_*` pass-through values the native SDKs do not model.
@immutable
class PaymentParams {
  /// Creates payment parameters.
  const PaymentParams({
    required this.order,
    this.customer = const CustomerParams(),
    this.view = const ViewParams(),
    this.userParameters = UserParameters.empty,
    this.redirectUrl,
  });

  /// Order details.
  final OrderParams order;

  /// Payer details.
  final CustomerParams customer;

  /// Native checkout appearance.
  final ViewParams view;

  /// Merchant-defined `shp_*` parameters echoed back on every callback.
  final UserParameters userParameters;

  /// Success-redirect URL configured for the shop.
  ///
  /// The Android SDK watches for this prefix in the WebView to detect that the
  /// payment flow finished. Leave `null` to rely on Robokassa's own
  /// `/Merchant/State/` redirect.
  final String? redirectUrl;

  /// Validates every nested section.
  void validate() {
    order.validate();
    customer.validate();
    view.validate();
  }

  /// Returns a copy with the given fields replaced.
  PaymentParams copyWith({
    OrderParams? order,
    CustomerParams? customer,
    ViewParams? view,
    UserParameters? userParameters,
    String? redirectUrl,
  }) => PaymentParams(
    order: order ?? this.order,
    customer: customer ?? this.customer,
    view: view ?? this.view,
    userParameters: userParameters ?? this.userParameters,
    redirectUrl: redirectUrl ?? this.redirectUrl,
  );

  @override
  String toString() =>
      'PaymentParams(order: $order, customer: $customer, view: $view, '
      'userParameters: $userParameters)';
}
