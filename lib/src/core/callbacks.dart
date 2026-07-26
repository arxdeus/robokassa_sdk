import 'package:meta/meta.dart';

import 'amount.dart';
import 'credentials.dart';
import 'signature.dart';
import 'user_parameters.dart';

/// Which Robokassa callback a payload came from.
enum RobokassaCallbackKind {
  /// Server-to-server payment notification. Signed with **password #2**.
  ///
  /// This is the only callback that proves a payment happened.
  result,

  /// Browser redirect after a successful payment. Signed with **password #1**.
  ///
  /// The customer's browser follows this, so it is trivially replayable —
  /// use it to show a thank-you page, never to grant goods.
  success,

  /// Browser redirect after a failed or abandoned payment. **Unsigned.**
  fail,
}

/// A parsed and (where applicable) verified Robokassa callback.
///
/// ```dart
/// final callback = RobokassaCallback.parse(
///   request.uri.queryParameters,
///   kind: RobokassaCallbackKind.result,
///   credentials: credentials,
/// );
/// if (callback.isSignatureValid) {
///   await markOrderPaid(callback.invoiceId!, callback.outSum!);
///   return callback.acknowledgement; // "OK1042"
/// }
/// ```
@immutable
class RobokassaCallback {
  const RobokassaCallback._({
    required this.kind,
    required this.raw,
    required this.userParameters,
    required this.isSignatureValid,
    this.invoiceId,
    this.outSum,
    this.outSumRaw,
    this.signature,
    this.culture,
    this.incCurrLabel,
    this.email,
    this.fee,
    this.paymentMethod,
    this.signatureError,
  });

  /// Which endpoint produced this payload.
  final RobokassaCallbackKind kind;

  /// The untouched request parameters, so nothing Robokassa sends is lost.
  final Map<String, String> raw;

  /// The `shp_*` values echoed back from the original payment request.
  final UserParameters userParameters;

  /// Whether [signature] matched a locally computed one.
  ///
  /// Always `false` for [RobokassaCallbackKind.fail], which carries no
  /// signature — check [kind] before treating this as a rejection.
  final bool isSignatureValid;

  /// `InvId` — the shop's invoice number.
  final int? invoiceId;

  /// `OutSum` parsed as a number.
  final double? outSum;

  /// `OutSum` exactly as received. This is what was hashed.
  final String? outSumRaw;

  /// `SignatureValue` as received.
  final String? signature;

  /// `Culture`, when present.
  final String? culture;

  /// `IncCurrLabel` — the payment method the customer actually used.
  final String? incCurrLabel;

  /// `EMail` of the payer, when Robokassa forwards it.
  final String? email;

  /// `Fee` withheld by Robokassa, when present.
  final double? fee;

  /// `PaymentMethod`, when present.
  final String? paymentMethod;

  /// Why verification failed, for logging. `null` when it succeeded or when
  /// the callback is unsigned.
  final String? signatureError;

  /// The body a `ResultURL` handler must return so Robokassa stops retrying.
  ///
  /// Robokassa expects `OK` followed by the invoice number, e.g. `OK1042`.
  /// Returning anything else makes it re-deliver the notification.
  String get acknowledgement => 'OK${invoiceId ?? ''}';

  /// `true` when this payload is a signed, verified payment confirmation.
  ///
  /// The one condition under which it is safe to fulfil an order.
  bool get isConfirmedPayment =>
      kind == RobokassaCallbackKind.result && isSignatureValid;

  /// Parses [request] — a query-parameter or form-field map — and verifies the
  /// signature against [credentials].
  ///
  /// Parameter names are matched case-insensitively because Robokassa is not
  /// consistent about them (`InvId` / `InvID`, `EMail` / `Email`).
  ///
  /// [RobokassaCallbackKind.result] needs `credentials.password2`; passing
  /// publishable credentials for it throws [StateError].
  factory RobokassaCallback.parse(
    Map<String, String> request, {
    required RobokassaCallbackKind kind,
    required RobokassaCredentials credentials,
  }) {
    final lookup = <String, String>{
      for (final entry in request.entries) entry.key.toLowerCase(): entry.value,
    };
    String? read(String name) {
      final value = lookup[name.toLowerCase()];
      return (value == null || value.isEmpty) ? null : value;
    }

    final outSumRaw = read('OutSum');
    final invoiceRaw = read('InvId') ?? read('InvID');
    final invoiceId = invoiceRaw == null ? null : int.tryParse(invoiceRaw);
    final signature = read('SignatureValue');
    final userParameters = UserParameters.fromRequest(request);

    var valid = false;
    String? error;

    if (kind == RobokassaCallbackKind.fail) {
      error = null;
    } else if (outSumRaw == null || invoiceId == null) {
      error =
          'Callback is missing ${outSumRaw == null ? 'OutSum' : 'InvId'}; '
          'cannot verify the signature.';
    } else if (signature == null) {
      error = 'Callback carries no SignatureValue.';
    } else {
      final expected = kind == RobokassaCallbackKind.result
          ? RobokassaSignature.forResultUrl(
              credentials: credentials,
              outSum: outSumRaw,
              invoiceId: invoiceId,
              userParameters: userParameters,
            )
          : RobokassaSignature.forSuccessUrl(
              credentials: credentials,
              outSum: outSumRaw,
              invoiceId: invoiceId,
              userParameters: userParameters,
            );
      valid = expected.matches(signature);
      if (!valid) {
        error =
            'Signature mismatch for invoice $invoiceId. Check that the shop '
            'hash algorithm is ${credentials.algorithm.name}, that '
            '${kind == RobokassaCallbackKind.result ? 'password #2' : 'password #1'} '
            'is correct, and that every shp_ parameter was forwarded.';
      }
    }

    return RobokassaCallback._(
      kind: kind,
      raw: Map.unmodifiable(request),
      userParameters: userParameters,
      isSignatureValid: valid,
      invoiceId: invoiceId,
      outSum: parseOutSum(outSumRaw),
      outSumRaw: outSumRaw,
      signature: signature,
      culture: read('Culture'),
      incCurrLabel: read('IncCurrLabel'),
      email: read('EMail') ?? read('Email'),
      fee: parseOutSum(read('Fee')),
      paymentMethod: read('PaymentMethod'),
      signatureError: error,
    );
  }

  /// Parses a callback delivered as a full [uri] with query parameters.
  factory RobokassaCallback.parseUri(
    Uri uri, {
    required RobokassaCallbackKind kind,
    required RobokassaCredentials credentials,
  }) => RobokassaCallback.parse(
    uri.queryParameters,
    kind: kind,
    credentials: credentials,
  );

  /// Parses a callback delivered as an `application/x-www-form-urlencoded`
  /// request [body].
  factory RobokassaCallback.parseFormBody(
    String body, {
    required RobokassaCallbackKind kind,
    required RobokassaCredentials credentials,
  }) => RobokassaCallback.parse(
    Uri.splitQueryString(body),
    kind: kind,
    credentials: credentials,
  );

  @override
  String toString() =>
      'RobokassaCallback(${kind.name}, invoiceId: $invoiceId, '
      'outSum: $outSumRaw, valid: $isSignatureValid'
      '${signatureError == null ? '' : ', error: $signatureError'})';
}
