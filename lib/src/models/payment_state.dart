import 'package:meta/meta.dart';

/// Outcome of a *state query* — did Robokassa understand and answer the
/// request? Corresponds to `<Result><Code>` in the `OpStateExt` XML and to
/// `CheckRequestCode` / `PaymentResult` in the native SDKs.
///
/// This says nothing about whether the customer paid; that is
/// [PaymentStateCode].
enum RequestResultCode {
  /// Идёт обработка запроса.
  checking('-1', 'Request is still being processed'),

  /// Запрос обработан успешно.
  success('0', 'Request processed successfully'),

  /// Неверная цифровая подпись запроса.
  signatureError('1', 'Invalid request signature'),

  /// Магазин не найден или не активирован.
  shopError('2', 'Shop with this MerchantLogin not found, or not activated'),

  /// Операция с таким InvoiceID не найдена.
  invoiceNotFound('3', 'No operation found with this InvoiceID'),

  /// Найдены две операции с таким InvoiceID.
  invoiceDuplicated(
    '4',
    'Two operations share this InvoiceID — usually a test payment reusing a '
        'production invoice number',
  ),

  /// Операция прервана по таймауту.
  timeout('999', 'Operation timed out'),

  /// Внутренняя ошибка сервиса.
  serverError('1000', 'Robokassa internal service error');

  const RequestResultCode(this.code, this.description);

  /// The numeric code as it appears in the XML.
  final String code;

  /// Human-readable explanation, in English.
  final String description;

  /// `true` when Robokassa answered the query successfully.
  bool get isSuccess => this == RequestResultCode.success;

  /// Parses a `<Result><Code>` value; unknown codes yield `null`.
  static RequestResultCode? tryParse(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    for (final value in RequestResultCode.values) {
      if (value.code == trimmed) return value;
    }
    return null;
  }
}

/// State of the payment itself. Corresponds to `<State><Code>` in the
/// `OpStateExt` XML and to `CheckPayStateCode` / `PaymentState` natively.
enum PaymentStateCode {
  /// Операция не инициализирована.
  notInitialized('-1', 'Operation was never initialised'),

  /// Операция инициализирована, деньги не получены.
  initializedNotPaid(
    '5',
    'Initialised but unpaid — the customer has not paid yet, or the payment '
        'system has not confirmed the payment',
  ),

  /// Операция отменена, деньги не получены.
  cancelledNotPaid(
    '10',
    'Cancelled and unpaid — the customer declined, or the operation expired',
  ),

  /// Средства захолдированы.
  holdSuccess('20', 'Funds are held (two-stage payment awaiting capture)'),

  /// Деньги получены, идёт зачисление магазину.
  paidNotTransferred(
    '50',
    'Paid — funds received, being credited to the shop balance. Sitting here '
        'for more than ~20 minutes indicates a settlement problem',
  ),

  /// Деньги возвращены покупателю.
  refunded('60', 'Refunded to the customer'),

  /// Исполнение операции приостановлено.
  suspended(
    '80',
    'Suspended — an anomaly occurred, or the security system paused it. '
        'Robokassa support resolves these manually',
  ),

  /// Платёж проведён успешно.
  paid('100', 'Paid successfully and credited to the shop balance');

  const PaymentStateCode(this.code, this.description);

  /// The numeric code as it appears in the XML.
  final String code;

  /// Human-readable explanation, in English.
  final String description;

  /// `true` when money has definitively reached the shop.
  bool get isPaid => this == PaymentStateCode.paid;

  /// `true` when funds are held and awaiting capture or release.
  bool get isHeld => this == PaymentStateCode.holdSuccess;

  /// `true` when the operation can still change state, so polling should
  /// continue.
  bool get isPending =>
      this == PaymentStateCode.notInitialized ||
      this == PaymentStateCode.initializedNotPaid ||
      this == PaymentStateCode.paidNotTransferred;

  /// `true` when the operation reached a state it will not leave on its own.
  bool get isTerminal => !isPending;

  /// `true` when the outcome is a failure for the merchant.
  bool get isFailure =>
      this == PaymentStateCode.cancelledNotPaid ||
      this == PaymentStateCode.refunded ||
      this == PaymentStateCode.suspended;

  /// Parses a `<State><Code>` value; unknown codes yield `null`.
  static PaymentStateCode? tryParse(String? code) {
    if (code == null) return null;
    final trimmed = code.trim();
    for (final value in PaymentStateCode.values) {
      if (value.code == trimmed) return value;
    }
    return null;
  }
}

/// The full answer from the `OpStateExt` payment-state web service.
@immutable
class PaymentState {
  /// Creates a payment state snapshot.
  const PaymentState({
    required this.requestResult,
    required this.stateCode,
    this.description,
    this.opKey,
    this.stateDate,
    this.incCurrLabel,
    this.incSum,
    this.incAccount,
    this.paymentMethodCode,
    this.outCurrLabel,
    this.outSum,
    this.rawXml,
  });

  /// Whether the *query* succeeded.
  final RequestResultCode requestResult;

  /// Whether the *payment* succeeded.
  final PaymentStateCode stateCode;

  /// `<Result><Description>` — Robokassa's own message, usually Russian.
  final String? description;

  /// `<Info><OpKey>` — operation identifier.
  ///
  /// Keep this: it is the `Token` you pass to charge the customer's saved card
  /// again without re-entering the number.
  final String? opKey;

  /// `<State><RequestDate>` / `<State><StateDate>` when Robokassa supplies it.
  final DateTime? stateDate;

  /// Payment method the customer actually used.
  final String? incCurrLabel;

  /// Amount the customer paid, including Robokassa's fee.
  final double? incSum;

  /// Customer's account/wallet identifier, when disclosed.
  final String? incAccount;

  /// `<Info><PaymentMethod><Code>`.
  final String? paymentMethodCode;

  /// Currency credited to the shop.
  final String? outCurrLabel;

  /// Amount credited to the shop, after fees.
  final double? outSum;

  /// The raw XML, for diagnostics.
  final String? rawXml;

  /// `true` when the query succeeded *and* the payment is complete.
  bool get isPaid => requestResult.isSuccess && stateCode.isPaid;

  /// `true` when the query succeeded *and* funds are held awaiting capture.
  bool get isHeld => requestResult.isSuccess && stateCode.isHeld;

  /// `true` when it is worth querying again shortly.
  bool get shouldKeepPolling =>
      requestResult == RequestResultCode.checking ||
      (requestResult.isSuccess && stateCode.isPending);

  @override
  String toString() =>
      'PaymentState(result: ${requestResult.code}/${requestResult.name}, '
      'state: ${stateCode.code}/${stateCode.name}, opKey: $opKey'
      '${description == null ? '' : ', description: $description'})';
}
