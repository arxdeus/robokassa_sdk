/// Formatting rules for the monetary values Robokassa signs.
///
/// The critical invariant across this package: **the string you sign must be
/// byte-identical to the string you send**. Robokassa recomputes the hash from
/// the literal text of `OutSum`, so `100`, `100.0` and `100.00` are three
/// different signatures. Every amount therefore goes through [formatOutSum].
library;

/// Renders [value] as an `OutSum` / `IncSum` string.
///
/// Defaults to two decimal places (`100` → `"100.00"`), which is what the
/// Robokassa documentation shows and what most merchant back ends emit.
///
/// Set [stripTrailingZeros] to drop a zero fractional part (`100` → `"100"`),
/// which Robokassa also accepts — but only if your server signs callbacks the
/// same way, otherwise `ResultURL` verification will fail.
///
/// Throws [ArgumentError] when [value] is negative or not finite.
String formatOutSum(num value, {bool stripTrailingZeros = false}) {
  final asDouble = value.toDouble();
  if (!asDouble.isFinite) {
    throw ArgumentError.value(value, 'value', 'OutSum must be a finite number');
  }
  if (asDouble < 0) {
    throw ArgumentError.value(value, 'value', 'OutSum must not be negative');
  }

  final fixed = asDouble.toStringAsFixed(2);
  if (!stripTrailingZeros) return fixed;
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}

/// Normalises an `OutSum` that arrived from Robokassa so it can be compared
/// with a locally computed amount.
///
/// Robokassa may echo `100`, `100.0` or `100.00`; all three parse to the same
/// number. Returns `null` when [raw] is not a number.
double? parseOutSum(String? raw) {
  if (raw == null) return null;
  return double.tryParse(raw.trim().replaceAll(',', '.'));
}

/// Formats a [DateTime] for the `ExpirationDate` parameter.
///
/// Robokassa expects ISO-8601 with milliseconds and a numeric offset, e.g.
/// `2026-07-25T18:30:00.000+03:00`. UTC values are rendered with `+00:00`
/// rather than `Z`, matching the `yyyy-MM-dd'T'HH:mm:ss.SSSZ` pattern used by
/// the official Android SDK.
String formatExpirationDate(DateTime value) {
  final local = value.isUtc ? value.toLocal() : value;
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');

  final date = <String>[
    local.year.toString().padLeft(4, '0'),
    local.month.toString().padLeft(2, '0'),
    local.day.toString().padLeft(2, '0'),
  ].join('-');
  final time = <String>[
    local.hour.toString().padLeft(2, '0'),
    local.minute.toString().padLeft(2, '0'),
    local.second.toString().padLeft(2, '0'),
  ].join(':');
  final millis = local.millisecond.toString().padLeft(3, '0');

  return '${date}T$time.$millis$sign$hours:$minutes';
}
