/// How the `Receipt` operand is rendered before it is hashed and sent.
///
/// Robokassa's own sources disagree, and the two conventions produce different
/// signatures, so this is an explicit choice rather than a hidden default.
///
/// * The **documentation** (`/ru/fiscalization`) says: *«Перед добавлением в
///   строку для подписи значение `Receipt` нужно URL-кодировать»*, and every
///   worked base string on the site shows `%7B%22items%22…`.
/// * The **official `robokassa/sdk-php`**, `igor-netFantom/robokassa-api`, and
///   both official mobile SDKs hash the **raw JSON** and URL-encode only for
///   transport.
///
/// Both work, because Robokassa recomputes the hash from the value it decodes
/// out of the request — what matters is that *the string you sign is the string
/// that arrives*. This package guarantees that in either mode.
///
/// [ReceiptSignatureMode.urlEncoded] is the default because it follows the
/// normative documentation.
enum ReceiptSignatureMode {
  /// Percent-encode the JSON once, then sign and send that exact string.
  ///
  /// The value travels through one more encoding pass in a query string or
  /// form body, so it appears double-encoded on the wire (`%257B`) and
  /// Robokassa decodes it back to the single-encoded operand that was signed.
  /// This reproduces the `/ru/saving` worked example exactly.
  urlEncoded,

  /// Sign the raw JSON and let the transport encode it once.
  ///
  /// Matches `robokassa/sdk-php` and the official Android and iOS SDKs. Use
  /// this if your back end already verifies signatures that way.
  rawJson;

  /// Renders [receiptJson] as the operand this mode signs and transmits.
  String render(String receiptJson) => switch (this) {
    ReceiptSignatureMode.urlEncoded => Uri.encodeComponent(receiptJson),
    ReceiptSignatureMode.rawJson => receiptJson,
  };
}
