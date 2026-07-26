import 'package:meta/meta.dart';

import 'payment_state.dart';

/// How a native checkout screen finished.
enum PaymentOutcome {
  /// The payment reached a successful terminal state.
  success,

  /// The user dismissed the checkout screen without paying.
  canceled,

  /// The flow failed. See [RobokassaPaymentResult.errorMessage].
  error,
}

/// Result of running the native Robokassa checkout.
///
/// A [PaymentOutcome.success] here means the native SDK polled Robokassa's
/// state service and saw a terminal success — a much stronger signal than a
/// `SuccessURL` redirect. It is still a *client-side* claim: fulfil orders
/// from your server's `ResultURL` handler, and treat this as the cue to show
/// the customer a result and refresh from your back end.
@immutable
class RobokassaPaymentResult {
  /// Creates a result.
  const RobokassaPaymentResult({
    required this.outcome,
    this.invoiceId,
    this.opKey,
    this.requestResult,
    this.stateCode,
    this.description,
    this.errorMessage,
  });

  /// Whether the flow succeeded, was cancelled, or failed.
  final PaymentOutcome outcome;

  /// The shop invoice number the payment was made against.
  final int? invoiceId;

  /// Operation key of the completed payment.
  ///
  /// Persist this to charge the same card later without re-entering it: pass
  /// it as `OrderParams.token` for a saved-card payment.
  final String? opKey;

  /// Robokassa's answer to the state *query*, when the SDK reported one.
  final RequestResultCode? requestResult;

  /// State of the *payment*, when the SDK reported one.
  final PaymentStateCode? stateCode;

  /// Robokassa's own message, usually Russian.
  final String? description;

  /// Failure detail when [outcome] is [PaymentOutcome.error].
  final String? errorMessage;

  /// `true` when the payment completed successfully.
  bool get isSuccess => outcome == PaymentOutcome.success;

  /// `true` when the user backed out of checkout.
  bool get isCanceled => outcome == PaymentOutcome.canceled;

  /// `true` when the flow failed.
  bool get isError => outcome == PaymentOutcome.error;

  /// `true` when funds were authorised and held rather than captured.
  ///
  /// Follow up with `Robokassa.confirmHold` or `Robokassa.cancelHold`.
  bool get isHeld => stateCode == PaymentStateCode.holdSuccess;

  /// A message suitable for showing to a developer in logs.
  String get diagnostics {
    final parts = <String>[
      'outcome: ${outcome.name}',
      if (invoiceId != null) 'invoiceId: $invoiceId',
      if (requestResult != null)
        'result: ${requestResult!.code} (${requestResult!.description})',
      if (stateCode != null)
        'state: ${stateCode!.code} (${stateCode!.description})',
      if (description != null && description!.isNotEmpty)
        'description: $description',
      if (errorMessage != null && errorMessage!.isNotEmpty)
        'error: $errorMessage',
    ];
    return parts.join(', ');
  }

  @override
  String toString() => 'RobokassaPaymentResult($diagnostics)';

  @override
  bool operator ==(Object other) =>
      other is RobokassaPaymentResult &&
      other.outcome == outcome &&
      other.invoiceId == invoiceId &&
      other.opKey == opKey &&
      other.requestResult == requestResult &&
      other.stateCode == stateCode &&
      other.description == description &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
    outcome,
    invoiceId,
    opKey,
    requestResult,
    stateCode,
    description,
    errorMessage,
  );
}

/// Raised when the native Robokassa SDK is missing or misconfigured.
///
/// Almost always means the consumer-side native setup was skipped — see the
/// package README's installation section.
class RobokassaNativeException implements Exception {
  /// Creates a native-bridge exception.
  const RobokassaNativeException(this.message, {this.code, this.details});

  /// What went wrong.
  final String message;

  /// Platform error code, when the failure came from a channel error.
  final String? code;

  /// Extra platform detail.
  final Object? details;

  @override
  String toString() =>
      'RobokassaNativeException${code == null ? '' : ' [$code]'}: $message'
      '${details == null ? '' : ' ($details)'}';
}
