import 'package:http/http.dart' as http;

import 'api/robokassa_api.dart';
import 'core/callbacks.dart';
import 'core/credentials.dart';
import 'core/payment_link.dart';
import 'models/payment_params.dart';
import 'models/payment_result.dart';
import 'models/payment_state.dart';
import 'platform/robokassa_platform.dart';

/// The entry point of the Robokassa SDK.
///
/// One instance binds a set of shop [credentials] to three capabilities:
///
/// * **[pay] and friends** — the native 3-D Secure checkout screen, backed by
///   Robokassa's own Android and iOS SDKs.
/// * **[links]** — pure-Dart signed payment links, usable on any platform.
/// * **[api]** — direct HTTP access to the merchant interfaces.
///
/// ```dart
/// final robokassa = Robokassa(
///   credentials: const RobokassaCredentials(
///     merchantLogin: 'my_shop',
///     password1: '...',
///     password2: '...',
///     isTest: true,
///   ),
/// );
///
/// final result = await robokassa.pay(PaymentParams(
///   order: OrderParams(
///     invoiceId: 1042,
///     orderSum: 149.90,
///     description: 'Pro plan, 1 month',
///     receipt: Receipt(items: [
///       ReceiptItem(name: 'Pro plan', sum: 149.90, quantity: 1, tax: Tax.vat20),
///     ]),
///   ),
///   customer: CustomerParams(email: 'buyer@example.com', culture: Culture.ru),
/// ));
///
/// if (result.isSuccess) {
///   // Show a receipt — but grant access from your ResultURL handler.
/// }
/// ```
///
/// ## Security
///
/// The native flow needs both passwords on the device. Anyone who unpacks your
/// app can read them, and password #2 is what proves a `ResultURL` callback is
/// genuine. Treat a client-side [RobokassaPaymentResult] as a UI cue, never as
/// authorisation — confirm every payment server-side. See
/// [RobokassaCredentials] for the details.
class Robokassa {
  /// Creates an SDK instance for one shop.
  ///
  /// [httpClient] is forwarded to [api]; supply one to add retries, timeouts,
  /// or a mock in tests.
  Robokassa({required this.credentials, http.Client? httpClient})
    : links = RobokassaLinkBuilder(credentials: credentials),
      api = RobokassaApi(credentials: credentials, httpClient: httpClient);

  /// Shop identity and passwords.
  final RobokassaCredentials credentials;

  /// Builds signed payment links and form bodies. Works on every platform.
  final RobokassaLinkBuilder links;

  /// Direct HTTP access to Robokassa's merchant interfaces.
  final RobokassaApi api;

  RobokassaPlatform get _platform => RobokassaPlatform.instance;

  /// Releases the HTTP client owned by [api].
  void dispose() => api.close();

  /// Runs an ordinary one-stage payment in the native checkout screen.
  ///
  /// Completes when the screen closes — successfully, cancelled, or failed.
  Future<RobokassaPaymentResult> pay(PaymentParams params) =>
      _platform.startPayment(
        credentials: credentials,
        params: params,
        mode: RobokassaPaymentMode.simple,
      );

  /// Runs a two-stage payment: authorises and **holds** the funds.
  ///
  /// A successful result has `stateCode == PaymentStateCode.holdSuccess`.
  /// Capture it with [confirmHold] or release it with [cancelHold] — an
  /// uncaptured hold expires on its own, typically within a few days.
  Future<RobokassaPaymentResult> payWithHold(PaymentParams params) =>
      _platform.startPayment(
        credentials: credentials,
        params: params,
        mode: RobokassaPaymentMode.hold,
      );

  /// Runs the **first** payment of a recurring series.
  ///
  /// Robokassa remembers the card; later charges go through [chargeRecurring]
  /// with this payment's `invoiceId` as `previousInvoiceId`, and need no UI.
  Future<RobokassaPaymentResult> payRecurrentFirst(PaymentParams params) =>
      _platform.startPayment(
        credentials: credentials,
        params: params,
        mode: RobokassaPaymentMode.recurrent,
      );

  /// Charges a card saved by an earlier payment.
  ///
  /// `params.order.token` must be the `opKey` from that payment. The customer
  /// still confirms with CVC2/CVV2, so this shows the checkout screen.
  Future<RobokassaPaymentResult> payWithSavedCard(PaymentParams params) =>
      _platform.startPayment(
        credentials: credentials,
        params: params,
        mode: RobokassaPaymentMode.savedCard,
      );

  /// Captures funds held by [payWithHold]. No UI.
  ///
  /// `params.order.orderSum` may be lower than the held amount to capture only
  /// part of it; restate `params.order.receipt` to match when it is.
  Future<bool> confirmHold(PaymentParams params) =>
      _platform.confirmHold(credentials: credentials, params: params);

  /// Releases funds held by [payWithHold]. No UI.
  Future<bool> cancelHold(PaymentParams params) =>
      _platform.cancelHold(credentials: credentials, params: params);

  /// Charges a subsequent payment in a recurring series. No UI.
  ///
  /// `params.order.previousInvoiceId` must reference the first, already-paid
  /// invoice, and `params.order.invoiceId` must be a fresh unique number.
  Future<bool> chargeRecurring(PaymentParams params) =>
      _platform.chargeRecurring(credentials: credentials, params: params);

  /// Queries the state of `params.order.invoiceId`.
  ///
  /// Uses the native SDK where it offers a headless query (Android) and falls
  /// back to [RobokassaApi.getPaymentState] where it does not (iOS), so the
  /// call behaves the same on both platforms.
  ///
  /// [RobokassaApi.getPaymentState] returns strictly more detail — amounts,
  /// payment method, timestamps — so prefer it when you need those.
  Future<RobokassaPaymentResult> checkPaymentState(PaymentParams params) async {
    final invoiceId = params.order.invoiceId;
    if (invoiceId == null || invoiceId <= 0) {
      throw ArgumentError(
        'checkPaymentState needs `order.invoiceId`. Robokassa can only report '
        'on invoices whose number your shop assigned.',
      );
    }

    try {
      return await _platform.checkPaymentState(
        credentials: credentials,
        params: params,
      );
    } on RobokassaNativeException catch (error) {
      if (error.code != 'unsupported_on_ios') rethrow;
      return _fromPaymentState(await api.getPaymentState(invoiceId), invoiceId);
    }
  }

  static RobokassaPaymentResult _fromPaymentState(
    PaymentState state,
    int invoiceId,
  ) {
    final PaymentOutcome outcome;
    if (!state.requestResult.isSuccess) {
      outcome = PaymentOutcome.error;
    } else if (state.stateCode.isPaid || state.stateCode.isHeld) {
      outcome = PaymentOutcome.success;
    } else if (state.stateCode == PaymentStateCode.cancelledNotPaid) {
      outcome = PaymentOutcome.canceled;
    } else {
      outcome = PaymentOutcome.error;
    }

    return RobokassaPaymentResult(
      outcome: outcome,
      invoiceId: invoiceId,
      opKey: state.opKey,
      requestResult: state.requestResult,
      stateCode: state.stateCode,
      description: state.description,
      errorMessage: outcome == PaymentOutcome.error
          ? (state.description ?? state.stateCode.description)
          : null,
    );
  }

  /// Whether the native Robokassa SDK is linked into this build.
  ///
  /// `false` means the consumer-side native setup is missing — see the
  /// README's installation section. Check this once at start-up to fail with a
  /// useful message rather than at the customer's first tap on "Pay".
  Future<bool> isNativeSdkAvailable() => _platform.isNativeSdkAvailable();

  /// Parses and verifies a callback Robokassa delivered to your server.
  ///
  /// Only [RobokassaCallbackKind.result] proves a payment; see
  /// [RobokassaCallback].
  RobokassaCallback parseCallback(
    Map<String, String> request, {
    required RobokassaCallbackKind kind,
  }) => RobokassaCallback.parse(request, kind: kind, credentials: credentials);
}
