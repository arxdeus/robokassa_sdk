import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/amount.dart';
import '../core/credentials.dart';
import '../core/endpoints.dart';
import '../core/payment_link.dart';
import '../core/receipt_encoding.dart';
import '../core/signature.dart';
import '../core/user_parameters.dart';
import '../models/payment_params.dart';
import '../models/payment_state.dart';
import '../models/receipt.dart';
import 'state_xml.dart';

/// Raised when Robokassa answers, but with a failure.
class RobokassaApiException implements Exception {
  /// Creates an API exception.
  const RobokassaApiException(
    this.message, {
    this.statusCode,
    this.body,
    this.endpoint,
  });

  /// What went wrong.
  final String message;

  /// HTTP status, when the failure was at the transport level.
  final int? statusCode;

  /// Response body, for diagnostics.
  final String? body;

  /// Endpoint that produced the failure.
  final Uri? endpoint;

  @override
  String toString() {
    final parts = <String>[
      'RobokassaApiException: $message',
      if (endpoint != null) 'endpoint: $endpoint',
      if (statusCode != null) 'status: $statusCode',
      if (body != null && body!.isNotEmpty)
        'body: ${body!.length > 500 ? '${body!.substring(0, 500)}…' : body}',
    ];
    return parts.join(' | ');
  }
}

/// A newly created invoice returned by `Indexjson.aspx`.
class CreatedInvoice {
  /// Creates an invoice descriptor.
  const CreatedInvoice({
    required this.invoiceId,
    this.errorCode = 0,
    this.errorMessage,
  });

  /// Robokassa's own invoice identifier, used to build the checkout URL.
  final String invoiceId;

  /// `errorCode` from the JSON body; `0` means success.
  final int errorCode;

  /// `errorMessage` from the JSON body.
  final String? errorMessage;

  /// The checkout page for this invoice.
  Uri get checkoutUrl => kInvoiceCheckoutBaseUrl.resolve(invoiceId);

  @override
  String toString() =>
      'CreatedInvoice(invoiceId: $invoiceId, errorCode: $errorCode'
      '${errorMessage == null ? '' : ', errorMessage: $errorMessage'})';
}

/// Direct HTTP access to Robokassa's merchant interfaces.
///
/// Everything here is pure Dart and works on any platform, including tests and
/// server-side Dart. The native checkout flow lives in `Robokassa` instead.
///
/// ## Where to run this
///
/// [getPaymentState] needs password #2, and [confirmHold], [cancelHold] and
/// [chargeRecurring] move real money with password #1. Running them from a
/// phone means shipping those secrets in the app bundle. Prefer your own
/// back end; use this class in-app only for test-mode work or when you have
/// accepted that risk.
class RobokassaApi {
  /// Creates an API client.
  ///
  /// Pass [httpClient] to inject a mock in tests or a configured client with
  /// retries and timeouts in production. When you supply one, you own its
  /// lifetime — [close] leaves it open.
  RobokassaApi({
    required this.credentials,
    http.Client? httpClient,
    this.receiptMode = ReceiptSignatureMode.urlEncoded,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  /// Shop identity and passwords.
  final RobokassaCredentials credentials;

  /// Whether `Receipt` is signed URL-encoded or as raw JSON.
  ///
  /// Must match whatever [RobokassaLinkBuilder] used for the original payment.
  final ReceiptSignatureMode receiptMode;

  /// Renders [receipt] as the operand that is both signed and transmitted.
  String? _receiptOperand(Receipt? receipt) =>
      receipt == null ? null : receiptMode.render(receipt.toJsonString());

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Closes the underlying HTTP client, unless it was injected.
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  /// Queries the state of [invoiceId] via `OpStateExt`.
  ///
  /// Requires password #2. Throws [RobokassaApiException] on a transport
  /// failure and [FormatException] when the XML is unreadable.
  ///
  /// Note this reports on the *shop's* invoice number, so it only works when
  /// you supplied `InvId` yourself.
  Future<PaymentState> getPaymentState(int invoiceId) async {
    final signature = RobokassaSignature.forOperationState(
      credentials: credentials,
      invoiceId: invoiceId,
    );
    final body = <String, String>{
      'MerchantLogin': credentials.merchantLogin,
      'InvoiceID': invoiceId.toString(),
      // This endpoint names the field `Signature`, not `SignatureValue`.
      'Signature': signature.value,
    };
    final response = await _post(kOperationStateUrl, body);
    return parseOperationStateXml(response);
  }

  /// Captures a two-stage payment previously placed on hold.
  ///
  /// [outSum] may be lower than the held amount to capture only part of it; in
  /// that case pass a [receipt] restated to match, or Robokassa rejects the
  /// capture as inconsistent with the fiscal document.
  ///
  /// Returns `true` when Robokassa confirms the capture.
  Future<bool> confirmHold({
    required int invoiceId,
    required double outSum,
    Receipt? receipt,
    UserParameters userParameters = UserParameters.empty,
  }) async {
    final formatted = formatOutSum(outSum);
    final receiptOperand = _receiptOperand(receipt);
    final signature = RobokassaSignature.forHoldConfirm(
      credentials: credentials,
      outSum: formatted,
      invoiceId: invoiceId,
      receipt: receiptOperand,
      userParameters: userParameters,
    );
    final body = <String, String>{
      'MerchantLogin': credentials.merchantLogin,
      'OutSum': formatted,
      'InvoiceID': invoiceId.toString(),
      'Receipt': ?receiptOperand,
      'SignatureValue': signature.value,
      ...userParameters.toQueryParameters(),
    };
    final response = await _post(kHoldConfirmUrl, body);
    return _isAffirmative(response, kHoldConfirmUrl);
  }

  /// Releases a two-stage payment previously placed on hold.
  ///
  /// Returns `true` when Robokassa confirms the release.
  Future<bool> cancelHold({
    required int invoiceId,
    double? outSum,
    UserParameters userParameters = UserParameters.empty,
  }) async {
    final signature = RobokassaSignature.forHoldCancel(
      credentials: credentials,
      invoiceId: invoiceId,
      userParameters: userParameters,
    );
    final body = <String, String>{
      'MerchantLogin': credentials.merchantLogin,
      // Sent for the shop's own bookkeeping; deliberately NOT signed — the
      // cancel signature carries an empty OutSum operand (`Login::InvId:…`).
      if (outSum != null) 'OutSum': formatOutSum(outSum),
      'InvoiceID': invoiceId.toString(),
      'SignatureValue': signature.value,
      ...userParameters.toQueryParameters(),
    };
    final response = await _post(kHoldCancelUrl, body);
    return _isAffirmative(response, kHoldCancelUrl);
  }

  /// Charges a recurring payment against [previousInvoiceId].
  ///
  /// [previousInvoiceId] must reference an invoice that was originally created
  /// with `Recurring=true` and paid successfully. [invoiceId] is the new,
  /// unique invoice number for this charge.
  ///
  /// Returns `true` when Robokassa accepts the charge (it answers `OK`).
  Future<bool> chargeRecurring({
    required int invoiceId,
    required int previousInvoiceId,
    required double outSum,
    Receipt? receipt,
    String? description,
    UserParameters userParameters = UserParameters.empty,
  }) async {
    if (description != null && description.length > 100) {
      throw ArgumentError.value(
        description,
        'description',
        'Description must be at most 100 characters '
            '(got ${description.length})',
      );
    }
    final formatted = formatOutSum(outSum);
    final receiptOperand = _receiptOperand(receipt);
    final signature = RobokassaSignature.forRecurring(
      credentials: credentials,
      outSum: formatted,
      invoiceId: invoiceId,
      receipt: receiptOperand,
      userParameters: userParameters,
    );
    final body = <String, String>{
      'MerchantLogin': credentials.merchantLogin,
      'OutSum': formatted,
      'InvoiceID': invoiceId.toString(),
      'PreviousInvoiceID': previousInvoiceId.toString(),
      if (description != null && description.isNotEmpty)
        'Description': description,
      'Receipt': ?receiptOperand,
      'SignatureValue': signature.value,
      ...userParameters.toQueryParameters(),
    };
    final response = await _post(kRecurringUrl, body);
    return _isAffirmative(response, kRecurringUrl);
  }

  /// Pre-creates an invoice via `Indexjson.aspx` and returns its identifier.
  ///
  /// This is what the iOS SDK does before opening its WebView: it turns a
  /// long signed parameter set into a short `/Merchant/Index/<id>` URL.
  Future<CreatedInvoice> createInvoice(PaymentParams params) async {
    final builder = RobokassaLinkBuilder(credentials: credentials);
    final response = await _post(
      kCreateInvoiceUrl,
      builder.buildFormFields(params),
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(response);
    } on FormatException {
      throw RobokassaApiException(
        'Expected JSON from the invoice endpoint',
        body: response,
        endpoint: kCreateInvoiceUrl,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw RobokassaApiException(
        'Expected a JSON object from the invoice endpoint',
        body: response,
        endpoint: kCreateInvoiceUrl,
      );
    }

    final errorCode = switch (decoded['errorCode']) {
      final int value => value,
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    final errorMessage = decoded['errorMessage'] as String?;
    final invoiceId = decoded['invoiceID'] ?? decoded['invoiceId'];

    if (errorCode != 0 || invoiceId == null) {
      throw RobokassaApiException(
        errorMessage ?? 'Robokassa refused to create the invoice',
        body: response,
        endpoint: kCreateInvoiceUrl,
      );
    }

    return CreatedInvoice(
      invoiceId: invoiceId.toString(),
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// Polls [getPaymentState] until the payment reaches a terminal state.
  ///
  /// Checks every [interval] until [timeout] elapses, then returns the last
  /// state observed rather than throwing — the caller decides whether a
  /// still-pending payment is an error.
  ///
  /// Transport failures are retried; a [FormatException] from unreadable XML
  /// is not, since it will not fix itself.
  Future<PaymentState> awaitPaymentState(
    int invoiceId, {
    Duration interval = const Duration(seconds: 3),
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    PaymentState? last;

    while (true) {
      try {
        last = await getPaymentState(invoiceId);
        if (!last.shouldKeepPolling) return last;
      } on RobokassaApiException {
        // Transient: keep polling until the deadline.
      }

      if (!DateTime.now().isBefore(deadline)) {
        return last ??
            const PaymentState(
              requestResult: RequestResultCode.timeout,
              stateCode: PaymentStateCode.notInitialized,
              description: 'Timed out waiting for a terminal payment state',
            );
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<String> _post(Uri url, Map<String, String> fields) async {
    final http.Response response;
    try {
      response = await _httpClient.post(
        url,
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
          'Accept': '*/*',
        },
        body: encodeFormBody(fields),
      );
    } on Exception catch (error) {
      throw RobokassaApiException(
        'Network request failed: $error',
        endpoint: url,
      );
    }

    // Robokassa answers with UTF-8 but does not always say so in the header,
    // and `http` falls back to latin-1 when the charset is absent.
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RobokassaApiException(
        'Robokassa returned HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        body: body,
        endpoint: url,
      );
    }
    return body;
  }

  /// Robokassa signals success on these endpoints with a bare `OK…` or a
  /// SOAP-ish `<string>true</string>`, depending on the endpoint.
  bool _isAffirmative(String response, Uri endpoint) {
    final normalized = response.trim().toLowerCase();
    if (normalized.contains('true') || normalized.startsWith('ok')) return true;
    // A definite negative still reads as a successful HTTP exchange, so the
    // reason has to be surfaced rather than collapsed into `false`.
    throw RobokassaApiException(
      'Robokassa did not confirm the operation',
      body: response,
      endpoint: endpoint,
    );
  }
}
