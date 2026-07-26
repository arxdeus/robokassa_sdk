## 0.1.0

Initial release.

* **Native checkout** on Android and iOS via Robokassa's official SDKs, over a
  Pigeon-generated type-safe bridge: simple payment, two-stage hold with
  capture/release, recurring subscriptions, and saved-card payments.
* **Pure-Dart core** that runs anywhere, including tests and server-side Dart:
  * `RobokassaSignature` — every documented formula (payment initiation with
    the full modifier chain, `ResultURL`, `SuccessURL`, `OpStateExt`, hold
    capture and release, recurring charges), with `Shp_*` handling that
    preserves parameter-name case.
  * `RobokassaLinkBuilder` — signed payment links, form fields and POST bodies.
  * `RobokassaCallback` — `ResultURL` / `SuccessURL` / `FailURL` parsing and
    constant-time signature verification.
  * `Receipt` — fiscal receipts with byte-stable serialisation and the complete
    `tax` / `payment_method` / `payment_object` / `sno` catalogues.
* **`RobokassaApi`** — direct HTTP access to `OpStateExt` (with XML parsing),
  hold capture and release, recurring charges, and invoice creation.
* Selectable hash algorithm (MD5, SHA-1, SHA-256, SHA-384, SHA-512) and
  selectable `Receipt` signing convention (`ReceiptSignatureMode`).
* `dart run robokassa_sdk:fetch_native_sdks` fetches the native SDKs an app has
  to supply, since Robokassa publishes them as source rather than as artifacts.
