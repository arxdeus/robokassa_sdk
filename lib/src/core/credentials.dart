import 'package:meta/meta.dart';

import 'hash_algorithm.dart';

/// Shop identity and the two Robokassa passwords.
///
/// The two passwords have strictly separate roles and mixing them up is the
/// single most common Robokassa integration bug:
///
/// * **Password #1** signs *outgoing* payment requests and verifies
///   `SuccessURL` redirects.
/// * **Password #2** verifies *incoming* `ResultURL` notifications and signs
///   payment-status queries.
///
/// ## Keeping secrets out of the app bundle
///
/// [password2] must never ship inside a mobile binary in a production
/// integration: anyone who extracts it can forge the `ResultURL` callback that
/// marks an order as paid. Prefer creating payment links on your own server
/// and passing only the finished link (or invoice id) to the app.
///
/// The native Robokassa SDKs do require both passwords on the device, so
/// [RobokassaCredentials] carries both — but treat that as a test-mode /
/// low-risk convenience, and see [RobokassaCredentials.publishable] for the
/// client-side-safe subset.
@immutable
class RobokassaCredentials {
  /// Creates a credential set.
  const RobokassaCredentials({
    required this.merchantLogin,
    required this.password1,
    this.password2,
    this.algorithm = HashAlgorithm.md5,
    this.isTest = false,
  }) : assert(merchantLogin.length > 0, 'merchantLogin must not be empty');

  /// Credentials that carry only [password1].
  ///
  /// Enough to build payment links and verify `SuccessURL`, and safe(r) to
  /// embed in a client. Calls that need password #2 throw [StateError].
  const RobokassaCredentials.publishable({
    required String merchantLogin,
    required String password1,
    HashAlgorithm algorithm = HashAlgorithm.md5,
    bool isTest = false,
  }) : this(
         merchantLogin: merchantLogin,
         password1: password1,
         algorithm: algorithm,
         isTest: isTest,
       );

  /// Shop identifier (`MerchantLogin`).
  final String merchantLogin;

  /// Password #1 — signs outgoing requests, verifies `SuccessURL`.
  final String password1;

  /// Password #2 — verifies `ResultURL`, signs status queries.
  ///
  /// `null` when these credentials were created with
  /// [RobokassaCredentials.publishable].
  final String? password2;

  /// Hash algorithm configured for this shop in the Robokassa dashboard.
  final HashAlgorithm algorithm;

  /// Whether requests should be flagged with `IsTest=1`.
  ///
  /// In test mode Robokassa validates against the *test* password pair, so
  /// [password1] and [password2] must be the test passwords when this is set.
  final bool isTest;

  /// [password2], or a descriptive [StateError] when it was not provided.
  String get requirePassword2 {
    final value = password2;
    if (value == null || value.isEmpty) {
      throw StateError(
        'This operation needs Robokassa password #2, but the credentials for '
        'shop "$merchantLogin" were created without one. Either supply '
        '`password2:` or perform this step on your server.',
      );
    }
    return value;
  }

  /// Returns a copy with the given fields replaced.
  RobokassaCredentials copyWith({
    String? merchantLogin,
    String? password1,
    String? password2,
    HashAlgorithm? algorithm,
    bool? isTest,
  }) => RobokassaCredentials(
    merchantLogin: merchantLogin ?? this.merchantLogin,
    password1: password1 ?? this.password1,
    password2: password2 ?? this.password2,
    algorithm: algorithm ?? this.algorithm,
    isTest: isTest ?? this.isTest,
  );

  /// Redacts both passwords — [toString] never leaks a secret.
  @override
  String toString() =>
      'RobokassaCredentials(merchantLogin: $merchantLogin, '
      'algorithm: ${algorithm.name}, isTest: $isTest, '
      'password1: <redacted>, '
      'password2: ${password2 == null ? '<absent>' : '<redacted>'})';

  @override
  bool operator ==(Object other) =>
      other is RobokassaCredentials &&
      other.merchantLogin == merchantLogin &&
      other.password1 == password1 &&
      other.password2 == password2 &&
      other.algorithm == algorithm &&
      other.isTest == isTest;

  @override
  int get hashCode =>
      Object.hash(merchantLogin, password1, password2, algorithm, isTest);
}
