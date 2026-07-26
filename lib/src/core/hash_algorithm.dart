import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Hash algorithms Robokassa accepts for `SignatureValue`.
///
/// The algorithm is configured per-shop in the Robokassa dashboard
/// ("Алгоритм расчёта хеша"); the value you sign with must match that setting.
/// MD5 is the default for new shops.
///
/// Robokassa also lists RIPEMD160, which has no implementation in
/// `package:crypto` and is therefore not offered here. If your shop uses it,
/// take `RobokassaSignature.base` and hash that string yourself.
enum HashAlgorithm {
  /// MD5 — the Robokassa default.
  md5,

  /// SHA-1.
  sha1,

  /// SHA-256.
  sha256,

  /// SHA-384.
  sha384,

  /// SHA-512.
  sha512;

  /// Hashes [input] as UTF-8 and returns the digest as lower-case hex.
  ///
  /// Robokassa compares signatures case-insensitively, but lower-case hex is
  /// what both official mobile SDKs produce.
  String hash(String input) {
    final bytes = utf8.encode(input);
    final digest = switch (this) {
      HashAlgorithm.md5 => crypto.md5.convert(bytes),
      HashAlgorithm.sha1 => crypto.sha1.convert(bytes),
      HashAlgorithm.sha256 => crypto.sha256.convert(bytes),
      HashAlgorithm.sha384 => crypto.sha384.convert(bytes),
      HashAlgorithm.sha512 => crypto.sha512.convert(bytes),
    };
    return digest.toString();
  }

  /// Number of hex characters a digest of this algorithm occupies.
  int get digestLength => switch (this) {
    HashAlgorithm.md5 => 32,
    HashAlgorithm.sha1 => 40,
    HashAlgorithm.sha256 => 64,
    HashAlgorithm.sha384 => 96,
    HashAlgorithm.sha512 => 128,
  };

  /// Guesses the algorithm from the length of a hex [signature].
  ///
  /// Useful when verifying an incoming callback whose algorithm you did not
  /// configure yourself. Returns `null` when the length matches nothing.
  static HashAlgorithm? fromDigestLength(String signature) {
    for (final algorithm in HashAlgorithm.values) {
      if (signature.length == algorithm.digestLength) return algorithm;
    }
    return null;
  }
}

/// Compares two hex signatures without leaking timing information.
///
/// Callback signatures arrive from the network, so verification should not
/// short-circuit on the first differing character.
bool constantTimeEquals(String a, String b) {
  final left = a.toLowerCase().codeUnits;
  final right = b.toLowerCase().codeUnits;
  if (left.length != right.length) return false;
  var mismatch = 0;
  for (var i = 0; i < left.length; i++) {
    mismatch |= left[i] ^ right[i];
  }
  return mismatch == 0;
}
