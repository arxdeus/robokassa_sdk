## 0.1.0

Initial release.

* **Zero-setup installation.** Robokassa's official Android and iOS SDKs are
  vendored into this plugin (both MIT — see `THIRD_PARTY_NOTICES.md`), so
  `flutter pub add robokassa_sdk` is the entire integration. No Gradle module,
  no AAR, no JitPack, no Podfile entry. Works on CocoaPods and on Flutter's
  Swift Package Manager. Requires Android `minSdk 24` and iOS 14.0.
* **Native checkout** on Android and iOS over a Pigeon-generated type-safe
  bridge: simple payment, two-stage hold with capture/release, recurring
  subscriptions, and saved-card payments.
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

### Native-flow behaviour worth knowing

* `PaymentParams.userParameters` (`Shp_*`) now **throws `ArgumentError`** on
  the native checkout path instead of being silently discarded — Robokassa's
  native SDKs build their own request body and cannot carry those values. Use
  `RobokassaLinkBuilder` for payments that need them.
* `CustomerParams.ip` (`UserIp`) is **never part of `SignatureValue`**, and is
  **not transmitted by either native SDK**. It still works through
  `RobokassaLinkBuilder` and `RobokassaApi`, where it is sent unsigned.
* Both platforms report the real `requestResult` and `stateCode` after a native
  checkout, so `RobokassaPaymentResult.isHeld` is trustworthy on each. Android
  gets them from its SDK directly; iOS queries the payment-state service for
  that invoice once checkout succeeds, because its SDK's success callback
  carries only an opaque `opKey`. If that lookup fails or times out, both codes
  are `null` and the payment is *still* reported as successful — a failed status
  lookup never demotes a payment that actually went through.
* `checkPaymentState` now runs **natively on both platforms**; the previous
  iOS-only fallback to `RobokassaApi.getPaymentState` is gone.
  `RobokassaApi.getPaymentState` still returns strictly more detail (amounts,
  payment method, timestamps, `opKey`).
* The native bridge now **rejects** an unrecognised `Culture`, `Currency`,
  `Tax`, `PaymentMethod`, `PaymentObject` or `TaxSystem` with an
  `invalid_arguments` `RobokassaNativeException` instead of silently dropping
  or coercing it. Every value of this package's closed enums maps cleanly on
  both platforms, so this can only fire if a value is constructed outside them.
* Per Robokassa: closing the payment frame and returning to the app work only
  in production mode, so `isTest: true` is not representative of the full flow.
* **Release builds are R8-safe.** The bundled `consumer-rules.pro` pins the
  field names of Robokassa's Gson-serialised models. Without it, a minified
  build silently shipped receipts as `{"c":…,"d":…}` instead of
  `{"name":…,"sum":…}` — that JSON is also hashed into `SignatureValue` — and
  broke the SharedPreferences resume used when returning from a bank app.
  Upstream ships this file empty; its own demo builds unminified.
* Automatic return from external bank apps (SBP, SberPay) on Android still
  needs a `robokassa://open` intent-filter and matching Success/Fail URLs in
  the Robokassa dashboard — see the README.

### Removed

* `dart run robokassa_sdk:fetch_native_sdks`. It existed only to clone the
  native SDKs into a consuming app; vendoring makes it dead.
* `PaymentStateCode.isFailure`. It had no call sites. Use `isPaid` / `isHeld` /
  `isPending` / `isTerminal`, or compare codes directly.
