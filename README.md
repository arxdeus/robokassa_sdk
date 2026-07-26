# robokassa_sdk

Robokassa payments for Flutter: signature generation, payment links, fiscal
receipts, server-callback verification, and the full native 3‑D Secure checkout
flow driven by Robokassa's own [Android](https://github.com/robokassa/sdk-android)
and [iOS](https://github.com/robokassa/sdk-ios) SDKs.

The package is three layers, usable together or separately:

| Layer | Class | Runs on |
|---|---|---|
| Native checkout | `Robokassa` | Android, iOS |
| Signing & links | `RobokassaLinkBuilder`, `RobokassaSignature`, `RobokassaCallback` | everywhere, including tests and server-side Dart |
| Merchant HTTP API | `RobokassaApi` | everywhere |

---

## Installation

> **Read this section fully.** Robokassa publishes its mobile SDKs as GitHub
> source, not as Maven or CocoaPods artifacts, so a Flutter plugin cannot pull
> them in on your behalf. Your app supplies them. It is three lines of config
> and one command.

```yaml
dependencies:
  robokassa_sdk: ^0.1.0
```

Fetch the native SDKs from your app folder (the one holding `android/` and
`ios/`):

```bash
dart run robokassa_sdk:fetch_native_sdks
```

That clones both repositories into `native/`.

### Android setup

Add to `android/settings.gradle.kts`:

```kotlin
val robokassaLibrary = file("../native/sdk-android/Robokassa_Library")
if (robokassaLibrary.isDirectory) {
    include(":Robokassa_Library")
    project(":Robokassa_Library").projectDir = robokassaLibrary
}
```

Requires `minSdk 24` (Robokassa's library targets Android 7.0+).

Two alternatives, if a git checkout in your tree does not suit you:

* **Pre-built AAR** — drop `Robokassa_Library-release.aar` (from the SDK repo's
  `app/lib/`) into `android/robokassa/`. The plugin finds it there, and also in
  `android/app/libs/` and `android/libs/`.
* **Private Maven mirror** — put the coordinates in `android/gradle.properties`:
  `robokassa.android.dependency=com.example:robokassa-library:1.0.0`

If none of the three is present, the Gradle build stops with a message saying
exactly this, rather than a wall of unresolved references.

### iOS setup

Add to `ios/Podfile`, inside the `Runner` target:

```ruby
platform :ios, '14.0'   # Robokassa's iOS SDK requires iOS 14

target 'Runner' do
  pod 'RobokassaSDK', :git => 'https://github.com/robokassa/sdk-ios.git', :tag => '1.0.0'
  # …
end
```

This package's podspec declares `s.dependency 'RobokassaSDK'` but cannot name
its source — only a Podfile may declare an external source. Omit the line and
CocoaPods reports `Unable to find a specification for RobokassaSDK`.

Apps using **Swift Package Manager** need no iOS setup: `Package.swift` names
the git dependency directly.

Verify the wiring at start-up:

```dart
if (!await robokassa.isNativeSdkAvailable()) {
  // The native setup above was skipped, or R8 stripped the library.
}
```

---

## Quick start

```dart
import 'package:robokassa_sdk/robokassa_sdk.dart';

final robokassa = Robokassa(
  credentials: const RobokassaCredentials(
    merchantLogin: 'my_shop',
    password1: '...',
    password2: '...',
    isTest: true,
  ),
);

final result = await robokassa.pay(const PaymentParams(
  order: OrderParams(
    invoiceId: 1042,
    orderSum: 149.90,
    description: 'Pro plan, 1 month',
    receipt: Receipt(items: <ReceiptItem>[
      ReceiptItem(name: 'Pro plan', sum: 149.90, quantity: 1, tax: Tax.vat20),
    ]),
  ),
  customer: CustomerParams(email: 'buyer@example.com', culture: Culture.ru),
));

if (result.isSuccess) {
  // Show a receipt — but grant access from your ResultURL handler (below).
}
```

### Payment modes

| Call | Flow |
|---|---|
| `pay` | Ordinary one-stage payment |
| `payWithHold` | Authorise and hold; capture later |
| `confirmHold` / `cancelHold` | Capture or release a hold (no UI) |
| `payRecurrentFirst` | First payment of a subscription |
| `chargeRecurring` | Subsequent subscription charges (no UI) |
| `payWithSavedCard` | Charge a card saved by an earlier payment |
| `checkPaymentState` | Query an invoice's state |

A held payment returns `result.isHeld == true`; capture it with `confirmHold`
or release it with `cancelHold`. An uncaptured hold expires on its own after a
few days.

To charge a saved card later, keep `result.opKey` and pass it as
`OrderParams.token`.

---

## Verifying payments on your server

**A client-side success is not proof of payment.** Only the `ResultURL`
notification is — it is server-to-server and signed with password #2.

```dart
// In your Dart back end, handling POST /robokassa/result
final callback = RobokassaCallback.parse(
  formFields,
  kind: RobokassaCallbackKind.result,
  credentials: credentials,
);

if (!callback.isConfirmedPayment) {
  return Response(400);           // never fulfil on a bad signature
}
await markOrderPaid(callback.invoiceId!, callback.outSum!);
return Response.ok(callback.acknowledgement);   // "OK1042"
```

| Callback | Signed with | Meaning |
|---|---|---|
| `ResultURL` | password #2 | **Authoritative.** Fulfil here. |
| `SuccessURL` | password #1 | Browser redirect. Show a thank-you page only. |
| `FailURL` | *unsigned* | UI only. Never mutate order state. |

Robokassa sends notifications from `185.59.216.65` and `185.59.217.65`.

---

## Payment links without the native flow

`RobokassaLinkBuilder` is pure Dart and works anywhere:

```dart
final uri = RobokassaLinkBuilder(credentials: credentials).buildUri(params);
// https://auth.robokassa.ru/Merchant/Index.aspx?MerchantLogin=…&SignatureValue=…
```

`buildFormFields` and `buildFormBody` give the same signed parameter set for a
`POST`, which you want once a receipt makes the URL long.

---

## Security

The native flow needs **both passwords on the device**. Anyone who unpacks your
APK or IPA can read them, and password #2 is what proves a `ResultURL`
notification is genuine — leaking it lets an attacker forge "this order is
paid".

For a production integration:

1. Create the payment **on your server** with `RobokassaLinkBuilder`.
2. Send only the finished link (or invoice id) to the app.
3. Verify every `ResultURL` callback server-side.

`RobokassaCredentials.publishable` builds a credential set carrying only
password #1; anything needing password #2 then throws `StateError` instead of
silently working. The native checkout flow does require password #2, so treat
it as a test-mode or accepted-risk convenience. `toString()` never renders
either password.

---

## Signature details

Every formula is implemented from Robokassa's documentation and cross-checked
against both official mobile SDKs. `RobokassaSignature.base` exposes the exact
pre-image when you need to debug a mismatch (it contains a password — do not
log it in production).

**Modifier order.** After `MerchantLogin:OutSum:InvId` the signature carries
only the modifiers Robokassa documents, in this fixed order, with absent ones
omitted entirely rather than left as empty slots:

```
Receipt → StepByStep → ResultUrl2 → SuccessUrl2 → SuccessUrl2Method
        → FailUrl2 → FailUrl2Method → Token → Password#1 → Shp_*
```

`Description`, `Email`, `Culture`, `Encoding`, `IsTest`, `IncCurrLabel`,
`ExpirationDate`, `Recurring`, `OutSumCurrency` and `UserIp` are **sent but not
signed**.

**`Shp_` parameters are case-sensitive.** `Shp_item` and `shp_item` produce
different signatures, so this package never rewrites the case you supply and
preserves whatever Robokassa sends back. Pick one spelling and keep it.

**Receipt encoding.** Robokassa's docs say to URL-encode `Receipt` before
signing; its own PHP and mobile SDKs sign the raw JSON. Both work, because what
actually matters is that *the string you sign is the string that arrives*.
`ReceiptSignatureMode.urlEncoded` (the default) follows the docs;
`ReceiptSignatureMode.rawJson` matches the SDKs. Use `RobokassaApi` in the same
mode as the link that created the payment.

**Amounts are signed literally.** `100`, `100.0` and `100.00` are three
different signatures, so the string you sign must be the string you send —
which is why `OutSum` goes through `formatOutSum` everywhere, and why incoming
callbacks are verified against the raw text received rather than a reparsed
number. Robokassa sends six decimals (`100.000000`) in production.

**Hash algorithms.** MD5 (default), SHA‑1, SHA‑256, SHA‑384 and SHA‑512, chosen
per shop in Технические настройки. RIPEMD‑160 is offered by Robokassa but has
no `package:crypto` implementation; if your shop uses it, take
`signatureFor(params).base` and hash it yourself.

---

## Known limitations

* **Fractional receipt quantities** cannot go through the native flow — both
  native SDKs type quantity as a 32-bit integer. `RobokassaLinkBuilder`
  supports them; the bridge throws `ArgumentError` rather than silently
  truncating a fiscal document.
* **`checkPaymentState` on iOS** falls back to the Dart HTTP implementation.
  Robokassa's iOS SDK exposes no headless state query present in both its
  CocoaPods and SwiftPM layouts. The result is identical.
* **RIPEMD‑160** is not implemented (see above).
* **Test mode and `OpStateExt`**: operations created with `IsTest=1` are not
  visible to the state web service.

---

## Example

`example/` exercises every mode against a shop you configure at runtime, plus a
playground showing the signature pre-image, the finished link, and live
callback verification.

```bash
cd example
dart run robokassa_sdk:fetch_native_sdks
flutter run
```

---

## License

MIT. Robokassa's native SDKs are MIT and are fetched from their own
repositories rather than redistributed here.
