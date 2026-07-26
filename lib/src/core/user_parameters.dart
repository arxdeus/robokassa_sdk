import 'package:meta/meta.dart';

/// The prefix added to a bare user-parameter name.
///
/// Robokassa's documentation writes `Shp_`, its mobile SDKs write `shp_`, and
/// its SBP JavaScript widget writes `shp_`. Any of them works — but **only if
/// the same spelling is used in the request and in the signature**, because
/// Robokassa recomputes the hash from the parameter names it literally
/// received. This package therefore never rewrites the case of a name you
/// supply; it only adds this prefix when one is missing entirely.
const String kUserParameterPrefix = 'shp_';

/// Merchant-defined pass-through parameters (`Shp_*`).
///
/// Robokassa echoes these back verbatim on `ResultURL`, `SuccessURL` and
/// `FailURL`, and folds them into `SignatureValue`. They are appended **after
/// the password**, sorted by name, as `Name=value`.
///
/// ```dart
/// final params = UserParameters({'userId': '42', 'cartId': 'A-7'});
/// params.signatureSegments; // ['shp_cartId=A-7', 'shp_userId=42']
/// ```
///
/// ## Case sensitivity
///
/// From the Robokassa docs: *«Параметры `Shp_*` чувствительны к регистру. Если
/// в теле запроса передан параметр `Shp_item`, а в расчёте подписи указан
/// `shp_item`, Robokassa вернёт ошибку из-за несовпадения подписи.»*
///
/// So names are kept exactly as written — `Shp_item` stays `Shp_item`, and
/// [UserParameters.fromRequest] preserves whatever Robokassa sent. Sorting
/// happens on that literal name, which also means `Shp_b` sorts before
/// `shp_a` under ordinal comparison. Pick one spelling and keep it.
@immutable
class UserParameters {
  /// Creates a set of user parameters.
  ///
  /// Names lacking a `shp_`/`Shp_`/`SHP_` prefix get [kUserParameterPrefix];
  /// names that already have one keep their exact spelling.
  factory UserParameters(Map<String, Object?> values) {
    final normalized = <String, String>{};
    for (final entry in values.entries) {
      final key = normalizeUserParameterName(entry.key);
      if (normalized.containsKey(key)) {
        throw ArgumentError.value(
          entry.key,
          'values',
          'Duplicate user parameter "$key" — two keys collide once the '
              '"$kUserParameterPrefix" prefix is applied.',
        );
      }
      normalized[key] = entry.value?.toString() ?? '';
    }
    return UserParameters._(Map.unmodifiable(normalized));
  }

  const UserParameters._(this._values);

  /// An empty parameter set.
  static const UserParameters empty = UserParameters._(<String, String>{});

  final Map<String, String> _values;

  /// The parameters, keyed by their full name with its original case.
  Map<String, String> get values => _values;

  /// `true` when there are no parameters to sign or send.
  bool get isEmpty => _values.isEmpty;

  /// `true` when at least one parameter is present.
  bool get isNotEmpty => _values.isNotEmpty;

  /// Looks a parameter up, ignoring case and an optional prefix.
  ///
  /// Reading is deliberately forgiving even though signing is not: you want
  /// `callback.userParameters['orderId']` to work regardless of how the name
  /// was spelled on the wire.
  String? operator [](String name) {
    final wanted = normalizeUserParameterName(name).toLowerCase();
    for (final entry in _values.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  /// Parameter names sorted the way Robokassa sorts them for signing.
  ///
  /// Ordinal (code-unit) ordering on the literal name. The documentation says
  /// only «строго по алфавиту» and reference SDKs disagree about the exact
  /// collation, so this picks the most common one; the orderings differ only
  /// when one name is a prefix of another.
  List<String> get sortedNames {
    final names = _values.keys.toList(growable: false)..sort();
    return names;
  }

  /// The `Name=value` fragments appended to a signature base, in order.
  List<String> get signatureSegments => <String>[
    for (final name in sortedNames) '$name=${_values[name]}',
  ];

  /// The parameters as query-string entries, ready for a payment link.
  Map<String, String> toQueryParameters() => <String, String>{
    for (final name in sortedNames) name: _values[name]!,
  };

  /// Extracts the `Shp_*` entries from an incoming request payload.
  ///
  /// Names are preserved exactly as Robokassa sent them, which is what makes
  /// callback signature verification work.
  factory UserParameters.fromRequest(Map<String, Object?> request) {
    final extracted = <String, String>{};
    for (final entry in request.entries) {
      if (isUserParameterName(entry.key)) {
        extracted[entry.key] = entry.value?.toString() ?? '';
      }
    }
    return UserParameters._(Map.unmodifiable(extracted));
  }

  /// Returns a copy with [name] set to [value].
  UserParameters copyWith(String name, Object? value) =>
      UserParameters(<String, Object?>{..._values, name: value});

  @override
  String toString() => 'UserParameters(${signatureSegments.join(', ')})';

  @override
  bool operator ==(Object other) {
    if (other is! UserParameters) return false;
    if (other._values.length != _values.length) return false;
    for (final entry in _values.entries) {
      if (other._values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// `true` when [name] is a Robokassa user parameter.
///
/// Detection is case-insensitive because Robokassa's own material uses `Shp_`,
/// `shp_` and `SHP_` in different places.
bool isUserParameterName(String name) =>
    name.length > kUserParameterPrefix.length &&
    name.substring(0, kUserParameterPrefix.length).toLowerCase() ==
        kUserParameterPrefix;

/// Returns [name] with a `shp_` prefix, preserving the case of an existing one.
///
/// Throws [ArgumentError] when nothing remains after the prefix, or when the
/// name uses characters Robokassa rejects — the docs allow only Latin letters,
/// digits and underscores after the prefix.
String normalizeUserParameterName(String name) {
  if (name.toLowerCase() == kUserParameterPrefix) {
    throw ArgumentError.value(
      name,
      'name',
      'A user parameter needs a name after the "$kUserParameterPrefix" prefix.',
    );
  }
  final hasPrefix = isUserParameterName(name);
  final bare = hasPrefix ? name.substring(kUserParameterPrefix.length) : name;
  if (bare.isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'A user parameter needs a name after the "$kUserParameterPrefix" prefix.',
    );
  }
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(bare)) {
    throw ArgumentError.value(
      name,
      'name',
      'Robokassa allows only Latin letters, digits and underscores after the '
          'Shp_ prefix.',
    );
  }
  // Keep the caller's prefix spelling; only supply one when it is missing.
  return hasPrefix ? name : '$kUserParameterPrefix$bare';
}
