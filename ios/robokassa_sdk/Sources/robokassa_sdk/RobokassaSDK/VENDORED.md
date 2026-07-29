# Vendored: Robokassa iOS SDK

This directory is a verbatim copy of Robokassa's official iOS SDK, vendored into
this plugin rather than consumed as a dependency.

| | |
| --- | --- |
| Upstream | <https://github.com/robokassa/sdk-ios> |
| Commit | `6e65b6fa852f5a361ecddf988976a04c12d836f0` (2025-12-03, "Добавлен НДС 22%") |
| Copied from | `Robokassa/**/*.{swift,png}` (the CocoaPods source tree) |
| Licence | MIT — Copyright (c) 2024 madjios. See upstream `LICENSE`. |

## Why vendored

`RobokassaSDK` is not published to the CocoaPods trunk, and a podspec cannot
point a `spec.dependency` at a git source — `:git`/`:path` exist only on
`spec.source` and on a Podfile's `pod` directive. Every CocoaPods app therefore
hit `[!] Unable to find a specification for RobokassaSDK` unless it hand-edited
its own Podfile. Compiling the source directly into this plugin's target removes
the external dependency entirely, and keeps the CocoaPods and SwiftPM paths
identical.

## Which upstream tree

Upstream ships **two diverged copies** of the SDK: `Robokassa/` (CocoaPods) and
`Sources/RobokassaSDK/` (SwiftPM). Both were last touched in the same commit;
neither is simply newer. `diff -rq` between them:

* **CocoaPods-only files:** `Network/ScriptMessageHandler.swift`,
  `Network/ServiceCheckPaymentStatus.swift`, `Robokassa.h`.
* **`Network/NetworkManager.swift`** — CocoaPods has a nesting-aware XML parser
  plus `requestForCheckStatus`/`getStateCode`; SwiftPM has a flat parser that
  cannot read `<Result><Code>` out of an `OpStateExt` response.
* **`Robokassa.swift`** — materially different: SwiftPM builds one long-lived
  `WebViewController` in `init`; CocoaPods constructs it per payment and seeds
  `ServiceCheckPaymentStatus`.
* **`Models/PaymentResult.swift`** — CocoaPods fixes several garbled Russian
  strings ("деньеи" → "деньги", …).
* **`Models/PaymentParams.swift`** — the one place SwiftPM has something
  CocoaPods lacks. See below.

The CocoaPods tree was taken as canonical: it is a superset everywhere except
`PaymentParams`, and it is the only tree that can answer a payment-state query.

### Deliberate divergence: `UserIp`

The SwiftPM tree's `payPostParams` emits the customer IP and folds it into the
signature:

```swift
if let ip = customer.ip, !ip.isEmpty {
    result += "&UserIp=\(ip)"
    signature += ":\(ip)"
}
```

That was **not** carried over. Robokassa's payment signature is
`MerchantLogin:OutSum:InvId[:Receipt]:Password1[:shp_*]`; `UserIp` is not a
member of it, so appending `:ip` between `Email` and `Password1` yields an MD5
that the server rejects ("Неверная цифровая подпись запроса"). The CocoaPods
tree's removal of those lines reads as the fix, not as a regression.

Consequence for callers: on iOS, `customer.ip` is accepted by the API and
carried into `CustomerParams`, but is not transmitted with the payment request.

## Local modifications

Kept to the minimum needed to work outside a standalone pod. Every edit is
marked with a `robokassa_sdk:` comment.

1. **`WebViewController.swift`** — the loader image was looked up in
   `Bundle(identifier: "org.cocoapods.RobokassaSDK")`, which resolves to `nil`
   once the SDK is no longer its own pod (the icon then failed silently behind
   an `else { print(...) }`). Replaced with the standard dual-packaging lookup:
   `Bundle.module` under SwiftPM, `Bundle(for: WebViewController.self)`
   otherwise.
2. **`Robokassa.h` not copied** — an Xcode-project umbrella header declaring
   only `RobokassaVersionNumber`/`RobokassaVersionString`. Upstream's own
   podspec globs `Robokassa/**/*.{swift}` and already excludes it; in a mixed
   Swift target it would only confuse module generation.

Nothing else was touched. To review upstream drift:

```sh
git clone https://github.com/robokassa/sdk-ios
diff -r sdk-ios/Robokassa ios/robokassa_sdk/Sources/robokassa_sdk/RobokassaSDK
```
