import 'package:meta/meta.dart';

import 'credentials.dart';
import 'hash_algorithm.dart';
// Imported for the `[ReceiptSignatureMode]` reference in the docs below.
import 'receipt_encoding.dart';
import 'user_parameters.dart';

/// Builds and verifies Robokassa `SignatureValue` hashes.
///
/// Every Robokassa signature is the hash of a colon-joined string. The parts,
/// their order, and which password terminates the string differ per operation,
/// and getting any of it wrong yields a generic "wrong signature" rejection —
/// so each supported operation gets its own named constructor here rather than
/// a single stringly-typed helper.
///
/// [buildBase] is exposed so you can log or unit-test the exact pre-image.
/// Note that the pre-image contains a password: never log it in production.
@immutable
class RobokassaSignature {
  const RobokassaSignature._(this.base, this.algorithm);

  /// The colon-joined pre-image that was hashed. Contains a password.
  final String base;

  /// Algorithm used to produce [value].
  final HashAlgorithm algorithm;

  /// The lower-case hex digest sent as `SignatureValue`.
  String get value => algorithm.hash(base);

  /// Joins [parts] with `:` and appends the sorted `shp_` segments.
  ///
  /// Every named constructor funnels through here, so the user-parameter rule
  /// (append **after** the password, sorted by name) is implemented once.
  static String buildBase(
    List<String> parts, {
    UserParameters userParameters = UserParameters.empty,
  }) => <String>[...parts, ...userParameters.signatureSegments].join(':');

  /// Signature for initiating a payment — `MerchantLogin:OutSum:InvId:…:Password#1`.
  ///
  /// After `InvId` come the *modifiers*, in the strict order Robokassa
  /// documents on `/ru/pay-interface`:
  ///
  /// > `Receipt → StepByStep → ResultUrl2 → SuccessUrl2 → SuccessUrl2Method →
  /// > FailUrl2 → FailUrl2Method → Token`
  ///
  /// A modifier that is absent is **omitted entirely** — it does not leave an
  /// empty slot. `InvId` is the one operand that does leave an empty slot when
  /// unset, so that `Login::…` is signed.
  ///
  /// [receipt] must be the exact string that goes into the `Receipt` field —
  /// see [ReceiptSignatureMode] for the two conventions and why it matters.
  ///
  /// Parameters Robokassa does **not** sign, and which therefore have no
  /// argument here: `Description`, `Email`, `Culture`, `Encoding`, `IsTest`,
  /// `IncCurrLabel`, `ExpirationDate`, `Recurring`, `OutSumCurrency`, `UserIp`.
  factory RobokassaSignature.forPaymentInit({
    required RobokassaCredentials credentials,
    required String outSum,
    int? invoiceId,
    String? receipt,
    bool stepByStep = false,
    String? resultUrl2,
    String? successUrl2,
    String? successUrl2Method,
    String? failUrl2,
    String? failUrl2Method,
    String? token,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        credentials.merchantLogin,
        outSum,
        _invoiceOperand(invoiceId),
        ..._modifiers(
          receipt: receipt,
          stepByStep: stepByStep,
          resultUrl2: resultUrl2,
          successUrl2: successUrl2,
          successUrl2Method: successUrl2Method,
          failUrl2: failUrl2,
          failUrl2Method: failUrl2Method,
          token: token,
        ),
        credentials.password1,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// The modifier chain, in the documented order, with absent entries dropped.
  static List<String> _modifiers({
    String? receipt,
    bool stepByStep = false,
    String? resultUrl2,
    String? successUrl2,
    String? successUrl2Method,
    String? failUrl2,
    String? failUrl2Method,
    String? token,
  }) {
    bool present(String? value) => value != null && value.isNotEmpty;
    return <String>[
      if (present(receipt)) receipt!,
      // Signed as the literal word `true`, matching `StepByStep=true`.
      if (stepByStep) 'true',
      if (present(resultUrl2)) resultUrl2!,
      if (present(successUrl2)) successUrl2!,
      if (present(successUrl2Method)) successUrl2Method!,
      if (present(failUrl2)) failUrl2!,
      if (present(failUrl2Method)) failUrl2Method!,
      if (present(token)) token!,
    ];
  }

  /// Signature Robokassa sends on `ResultURL` — `OutSum:InvId:Password#2`.
  ///
  /// Note there is no `MerchantLogin` operand here.
  factory RobokassaSignature.forResultUrl({
    required RobokassaCredentials credentials,
    required String outSum,
    required int invoiceId,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        outSum,
        invoiceId.toString(),
        credentials.requirePassword2,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Signature Robokassa sends on `SuccessURL` — `OutSum:InvId:Password#1`.
  ///
  /// Identical in shape to [RobokassaSignature.forResultUrl] but signed with
  /// password #1, which is exactly why a `SuccessURL` hit must never be
  /// treated as proof of payment: the client knows password #1's signature
  /// scheme only for its own requests, and the redirect is user-controlled.
  /// Only `ResultURL` (password #2, server-to-server) confirms a payment.
  factory RobokassaSignature.forSuccessUrl({
    required RobokassaCredentials credentials,
    required String outSum,
    required int invoiceId,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        outSum,
        invoiceId.toString(),
        credentials.password1,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Signature for the payment-state web service (`OpState` / `OpStateExt`) —
  /// `MerchantLogin:InvoiceID:Password#2`.
  factory RobokassaSignature.forOperationState({
    required RobokassaCredentials credentials,
    required int invoiceId,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        credentials.merchantLogin,
        _invoiceOperand(invoiceId),
        credentials.requirePassword2,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Signature for confirming a held (two-stage) payment —
  /// `MerchantLogin:OutSum:InvId[:Receipt]:Password#1`.
  ///
  /// `OutSum` may be **lower** than the originally held amount to capture only
  /// part of it; when it is, the receipt must be restated to match.
  factory RobokassaSignature.forHoldConfirm({
    required RobokassaCredentials credentials,
    required String outSum,
    required int invoiceId,
    String? receipt,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        credentials.merchantLogin,
        outSum,
        _invoiceOperand(invoiceId),
        if (receipt != null && receipt.isNotEmpty) receipt,
        credentials.password1,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Signature for cancelling a held payment — `MerchantLogin::InvId:Password#1`.
  ///
  /// The doubled colon is not a typo: cancellation releases the whole hold, so
  /// the `OutSum` operand is present but **empty**. Both official SDKs build
  /// the string this way (`signature += "::$id"`).
  factory RobokassaSignature.forHoldCancel({
    required RobokassaCredentials credentials,
    required int invoiceId,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        credentials.merchantLogin,
        '',
        _invoiceOperand(invoiceId),
        credentials.password1,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Signature for charging a recurring payment —
  /// `MerchantLogin:OutSum:InvId[:Receipt]:Password#1`.
  ///
  /// `PreviousInvoiceID` identifies the parent subscription but is **not**
  /// part of the signed string.
  factory RobokassaSignature.forRecurring({
    required RobokassaCredentials credentials,
    required String outSum,
    required int invoiceId,
    String? receipt,
    UserParameters userParameters = UserParameters.empty,
  }) {
    return RobokassaSignature._(
      buildBase(<String>[
        credentials.merchantLogin,
        outSum,
        _invoiceOperand(invoiceId),
        if (receipt != null && receipt.isNotEmpty) receipt,
        credentials.password1,
      ], userParameters: userParameters),
      credentials.algorithm,
    );
  }

  /// Escape hatch for an operation this package does not model yet.
  ///
  /// [parts] are joined with `:` verbatim; append the password yourself.
  factory RobokassaSignature.custom({
    required List<String> parts,
    HashAlgorithm algorithm = HashAlgorithm.md5,
    UserParameters userParameters = UserParameters.empty,
  }) => RobokassaSignature._(
    buildBase(parts, userParameters: userParameters),
    algorithm,
  );

  /// Constant-time comparison against a signature received from Robokassa.
  bool matches(String? received) =>
      received != null && constantTimeEquals(value, received);

  /// An absent or zero invoice id signs as an empty operand.
  static String _invoiceOperand(int? invoiceId) =>
      (invoiceId == null || invoiceId <= 0) ? '' : invoiceId.toString();

  /// Never renders [base] — it embeds a password.
  @override
  String toString() =>
      'RobokassaSignature(${algorithm.name}: $value, base: <redacted>)';
}
