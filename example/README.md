# robokassa_sdk example

Exercises every Robokassa payment mode against a shop you configure at runtime.

## Run it

```bash
flutter run
```

No native setup step. `robokassa_sdk` vendors Robokassa's official Android and
iOS SDKs, so there is nothing to clone, no `settings.gradle.kts` include and no
`Podfile` line to add.

The first screen asks for `MerchantLogin` and both passwords. Use your **test**
password pair while the "Test mode" switch is on — Robokassa validates against a
different pair in test mode.

> **Test mode is not representative.** Robokassa's own Android and iOS READMEs
> both warn that parts of the SDK — closing the payment frame and returning to
> the app after payment — only work in production. Treat a test-mode run as a
> check that your credentials and signature are right, not that the full flow is.

## Screens

**Native checkout** — simple payment, hold + capture/release, recurring first
payment and subsequent charges, saved-card payment, and state queries. Results
carry the `opKey` needed for the saved-card and recurring flows, so run a simple
payment first to unlock them.

**Links & signatures** — pure Dart: the exact signature pre-image, the digest,
the finished payment link, and live `ResultURL` verification. Runs anywhere,
including on platforms with no native SDK.
