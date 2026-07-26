import 'package:meta/meta.dart';

import '../models/payment_params.dart';
import 'amount.dart';
import 'credentials.dart';
import 'endpoints.dart';
import 'receipt_encoding.dart';
import 'signature.dart';
import 'user_parameters.dart';

/// Turns [PaymentParams] into a signed Robokassa checkout request.
///
/// The same parameter map serves three transports:
///
/// * [buildUri] — a link you can open in a browser or hand to a customer.
/// * [buildFormFields] — fields for an auto-submitting HTML form.
/// * [buildFormBody] — an `application/x-www-form-urlencoded` POST body.
///
/// All three sign identical values, so a link and a form for the same order
/// carry the same `SignatureValue`.
///
/// ```dart
/// final builder = RobokassaLinkBuilder(
///   credentials: RobokassaCredentials.publishable(
///     merchantLogin: 'demo',
///     password1: 'password_1',
///   ),
/// );
/// final uri = builder.buildUri(PaymentParams(
///   order: OrderParams(orderSum: 149.90, invoiceId: 1042, description: 'Pro plan'),
/// ));
/// ```
@immutable
class RobokassaLinkBuilder {
  /// Creates a builder bound to one shop's [credentials].
  const RobokassaLinkBuilder({
    required this.credentials,
    this.stripTrailingZeros = false,
    this.encoding = 'utf-8',
    this.receiptMode = ReceiptSignatureMode.urlEncoded,
  });

  /// Shop identity and passwords. Only password #1 is required.
  final RobokassaCredentials credentials;

  /// Renders whole amounts as `100` instead of `100.00`.
  ///
  /// Whatever you pick here must match how your server signs `ResultURL`
  /// callbacks, because Robokassa echoes `OutSum` in the form it received it.
  final bool stripTrailingZeros;

  /// Value of the `Encoding` parameter.
  ///
  /// Always sent explicitly: current docs say the default is UTF-8 while
  /// archived versions said Windows-1251, so relying on the default is a
  /// coin-flip.
  final String encoding;

  /// Whether the `Receipt` operand is signed URL-encoded or as raw JSON.
  ///
  /// See [ReceiptSignatureMode]; the default follows Robokassa's docs.
  final ReceiptSignatureMode receiptMode;

  /// The exact `OutSum` string this builder will sign and send for [params].
  String outSumFor(PaymentParams params) => formatOutSum(
    params.order.orderSum,
    stripTrailingZeros: stripTrailingZeros,
  );

  /// The exact `Receipt` string this builder will sign and send, or `null`.
  String? receiptFor(PaymentParams params) {
    final receipt = params.order.receipt;
    return receipt == null ? null : receiptMode.render(receipt.toJsonString());
  }

  /// The signature for [params], exposed for logging and tests.
  RobokassaSignature signatureFor(PaymentParams params) {
    params.validate();
    return RobokassaSignature.forPaymentInit(
      credentials: credentials,
      outSum: outSumFor(params),
      invoiceId: params.order.invoiceId,
      receipt: receiptFor(params),
      stepByStep: params.order.isHold,
      token: params.order.token,
      userParameters: params.userParameters,
    );
  }

  /// Every request parameter, in the order Robokassa documents.
  ///
  /// The `Receipt` value here is byte-identical to the signed operand, which
  /// is the invariant that makes verification work whichever
  /// [ReceiptSignatureMode] is in force. The transport helpers below apply
  /// exactly one further encoding pass, and Robokassa strips it back off.
  Map<String, String> buildFormFields(PaymentParams params) {
    final order = params.order;
    final customer = params.customer;
    final signature = signatureFor(params);
    final receipt = receiptFor(params);

    return <String, String>{
      'MerchantLogin': credentials.merchantLogin,
      'OutSum': outSumFor(params),
      if (order.invoiceId != null && order.invoiceId! > 0)
        'InvId': order.invoiceId!.toString(),
      if (order.description != null && order.description!.isNotEmpty)
        'Description': order.description!,
      'SignatureValue': signature.value,
      // Sent but NOT signed: neither appears in Robokassa's normative modifier
      // list, and the docs that describe them are archived 2021 pages.
      if (order.outSumCurrency != null)
        'OutSumCurrency': order.outSumCurrency!.wireValue,
      if (customer.ip != null && customer.ip!.isNotEmpty)
        'UserIp': customer.ip!,
      'Receipt': ?receipt,
      if (order.incCurrLabel != null && order.incCurrLabel!.isNotEmpty)
        'IncCurrLabel': order.incCurrLabel!,
      if (customer.culture != null) 'Culture': customer.culture!.wireValue,
      if (encoding.isNotEmpty) 'Encoding': encoding,
      if (customer.email != null && customer.email!.isNotEmpty)
        'Email': customer.email!,
      if (order.expirationDate != null)
        'ExpirationDate': formatExpirationDate(order.expirationDate!),
      if (order.token != null && order.token!.isNotEmpty) 'Token': order.token!,
      if (order.isRecurrent) 'Recurring': 'true',
      if (order.isHold) 'StepByStep': 'true',
      if (credentials.isTest) 'IsTest': '1',
      ...params.userParameters.toQueryParameters(),
    };
  }

  /// A ready-to-open checkout link.
  ///
  /// `Uri` percent-encodes every value, including the receipt JSON.
  ///
  /// Long receipts can push a `GET` URL past what intermediaries accept; use
  /// [buildFormFields] with a `POST` when you attach many receipt lines.
  Uri buildUri(PaymentParams params) =>
      kPaymentPageUrl.replace(queryParameters: buildFormFields(params));

  /// An `application/x-www-form-urlencoded` body for a `POST` to
  /// [kPaymentPageUrl].
  String buildFormBody(PaymentParams params) =>
      encodeFormBody(buildFormFields(params));

  /// A link that pays with a previously saved card.
  ///
  /// Requires `order.token` — the `OpKey` returned by the earlier payment that
  /// saved the card.
  Uri buildSavedCardUri(PaymentParams params) {
    if (params.order.token == null || params.order.token!.isEmpty) {
      throw ArgumentError(
        'Paying by saved card needs `order.token` (the OpKey of the operation '
        'whose card should be reused).',
      );
    }
    return kSavedCardPaymentUrl.replace(
      queryParameters: buildFormFields(params),
    );
  }

  /// Checkout link for an invoice already created via
  /// [kCreateInvoiceUrl].
  Uri buildInvoiceCheckoutUri(String invoiceId) =>
      kInvoiceCheckoutBaseUrl.resolve(invoiceId);
}

/// Percent-encodes [fields] as an `application/x-www-form-urlencoded` body.
///
/// Uses `Uri.encodeQueryComponent`, which encodes space as `+` — what
/// Robokassa's ASP.NET back end expects for form bodies.
String encodeFormBody(Map<String, String> fields) => fields.entries
    .map(
      (e) =>
          '${Uri.encodeQueryComponent(e.key)}='
          '${Uri.encodeQueryComponent(e.value)}',
    )
    .join('&');

/// Convenience: build a checkout link in one call.
///
/// Equivalent to constructing a [RobokassaLinkBuilder] and calling
/// [RobokassaLinkBuilder.buildUri].
Uri buildRobokassaPaymentLink({
  required RobokassaCredentials credentials,
  required PaymentParams params,
  bool stripTrailingZeros = false,
}) => RobokassaLinkBuilder(
  credentials: credentials,
  stripTrailingZeros: stripTrailingZeros,
).buildUri(params);

/// Re-exported so callers can build `shp_` maps without a second import.
typedef RobokassaUserParameters = UserParameters;
