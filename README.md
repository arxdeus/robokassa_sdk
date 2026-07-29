# robokassa_sdk

Robokassa payments for Flutter: signature generation, payment links, fiscal
receipts, server-callback verification, and the full native 3‑D Secure checkout
flow driven by Robokassa's own [Android](https://github.com/robokassa/sdk-android)
and [iOS](https://github.com/robokassa/sdk-ios) SDKs.

Both native SDKs are **vendored into this package**, so there is no native
setup: adding the dependency is the whole installation.

The package is three layers, usable together or separately:

| Layer | Class | Runs on |
| --- | --- | --- |
| Native checkout | `Robokassa` | Android, iOS |
| Signing & links | `RobokassaLinkBuilder`, `RobokassaSignature`, `RobokassaCallback` | everywhere, including tests and server-side Dart |
| Merchant HTTP API | `RobokassaApi` | everywhere |

---

## Installation

```bash
flutter pub add robokassa_sdk
```

That is all. No Gradle module, no AAR, no Podfile entry — Robokassa's Kotlin
and Swift sources compile as part of this plugin, on CocoaPods and on Flutter's
Swift Package Manager alike.

**Minimum platform versions**, inherited from the native SDKs:

| Platform | Requirement |
| --- | --- |
| Android | `minSdk 24` (Android 7.0) |
| iOS | 14.0 |

Raise `minSdkVersion` in `android/app/build.gradle.kts` and the iOS deployment
target in `ios/Podfile` if your app is currently below those.

### Test mode is not representative

> Robokassa states this prominently in both native SDK READMEs, and it is worth
> repeating: **parts of the SDK — closing the payment frame after payment, and
> returning to your app — work only in production mode.** A payment created
> with `isTest: true` can therefore leave the checkout screen open even though
> the payment itself succeeded. Use test mode to check your signatures and
> parameters; validate the end-to-end flow with a real, small production
> payment.

### Android: returning from external bank apps

SBP and SberPay hand the customer off to a bank application. Getting them back
into *your* app afterwards is the host app's job — the SDK cannot register your
intent filters for you. Two steps, both outside this package:

1. Add to `android/app/src/main/AndroidManifest.xml`, inside your
   `<activity>` (usually `MainActivity`):

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="robokassa" />
       <data android:host="open" />
   </intent-filter>
   ```

2. Host two pages on your own web server that bounce back into the app, and set
   them as **Success URL** and **Fail URL** in the Robokassa dashboard:

   ```html
   <html><body><script>
     document.location.href =
       "intent://scan/#Intent;scheme=robokassa://open;package=YOUR.APPLICATION.ID;end";
   </script></body></html>
   ```

   Replace `YOUR.APPLICATION.ID` with your Android `applicationId`. Robokassa
   hosts working examples at `https://ipol.ru/webService/robokassa/success.html`
   and `.../fail.html` for trying the flow before you deploy your own.

Skipping this does not break payment — the money still moves and `ResultURL`
still fires — the customer just has to switch back to your app by hand.

iOS needs no equivalent setup.

### Checking the wiring

```dart
if (!await robokassa.isNativeSdkAvailable()) {
  // Android/iOS only, and only if a shrinker stripped the vendored classes.
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
| --- | --- |
| `pay` | Ordinary one-stage payment |
| `payWithHold` | Authorise and hold; capture later |
| `confirmHold` / `cancelHold` | Capture or release a hold (no UI) |
| `payRecurrentFirst` | First payment of a subscription |
| `chargeRecurring` | Subsequent subscription charges (no UI) |
| `payWithSavedCard` | Charge a card saved by an earlier payment |
| `checkPaymentState` | Query an invoice's state |

Capture a hold with `confirmHold` or release it with `cancelHold`; an
uncaptured hold expires on its own after a few days. Test the outcome with
`result.isSuccess`; `result.isHeld` confirms the funds are actually held.

To charge a saved card later, keep `result.opKey` and pass it as
`OrderParams.token`.

---

## What the native flow cannot do

The native checkout screen is Robokassa's code, and it builds its own request
body. Three of this package's Dart features therefore do not reach it. Each one
throws rather than silently changing what you asked for.

**`Shp_` parameters are rejected, not dropped.** Neither native SDK models
merchant pass-through values, so `pay` and friends throw `ArgumentError` when
`PaymentParams.userParameters` is non-empty. If your reconciliation keys off
`Shp_orderId`, build the payment with `RobokassaLinkBuilder` (which signs and
sends them correctly) instead of the native screen.

**`customer.ip` is ignored.** Neither vendored SDK puts `UserIp` on the wire —
Android's `payPostParams` never reads the field, and the vendored iOS tree does
not emit it either. Set it and it simply does not travel. `UserIp` *does* work
through `RobokassaLinkBuilder` and `RobokassaApi`, where it is sent as an
unsigned parameter. It is **not** part of `SignatureValue` on any path.

**Fractional receipt quantities are rejected.** Both native SDKs type receipt
quantity as a 32-bit integer. The bridge throws rather than truncate a fiscal
document; `RobokassaLinkBuilder` handles them.

**State codes can be `null` even on success.** Both platforms normally report
the real `requestResult` and `stateCode` after checkout. Android reads them
from its SDK; iOS queries the payment-state service for that invoice once
checkout succeeds, because its SDK's success callback carries only an opaque
`opKey`. If that lookup fails or times out, both codes come back `null` while
`isSuccess` stays `true` — a failed *status lookup* must never demote a payment
that actually went through. So branch on `result.isSuccess`, treat the codes as
extra detail, and call `checkPaymentState` if you need them and they are absent.

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
| --- | --- | --- |
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

```text
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

* **`Shp_` parameters, `customer.ip` and fractional receipt quantities** do not
  work through the native checkout screen — see "What the native flow cannot
  do" above.
* **`checkPaymentState`** runs natively on both platforms and returns the real
  result/state codes, but less detail than `RobokassaApi.getPaymentState`,
  which also gives amounts, payment method, timestamps and `opKey`.
* **RIPEMD‑160** is not implemented (see above).
* **Test mode and `OpStateExt`**: operations created with `IsTest=1` are not
  visible to the state web service.
* **Test mode and the checkout screen**: frame-close and return-to-app are
  production-only, per Robokassa — see "Test mode is not representative".

---

## Example

`example/` exercises every mode against a shop you configure at runtime, plus a
playground showing the signature pre-image, the finished link, and live
callback verification.

```bash
cd example
flutter run
```

---

## License

MIT — see [`LICENSE`](LICENSE).

This package redistributes Robokassa's native Android and iOS SDKs, both MIT
licensed. Their copyright and permission notices, and the directories holding
the vendored code, are reproduced in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
