# robokassa_sdk example

Exercises every Robokassa payment mode against a shop you configure at runtime.

## Run it

```bash
dart run robokassa_sdk:fetch_native_sdks   # clones both native SDKs into native/
flutter run
```

The first screen asks for `MerchantLogin` and both passwords. Use your **test**
password pair while the "Test mode" switch is on — Robokassa validates against a
different pair in test mode.

## What is wired up

* `android/settings.gradle.kts` includes `:Robokassa_Library` from
  `native/sdk-android` when that checkout exists.
* `ios/Podfile` declares
  `pod 'RobokassaSDK', :git => 'https://github.com/robokassa/sdk-ios.git'`.

Both are the consumer-side setup every app using this package needs; see the
package README for why the plugin cannot do it for you.

## Screens

**Native checkout** — simple payment, hold + capture/release, recurring first
payment and subsequent charges, saved-card payment, and state queries. Results
carry the `opKey` needed for the saved-card and recurring flows, so run a simple
payment first to unlock them.

**Links & signatures** — pure Dart: the exact signature pre-image, the digest,
the finished payment link, and live `ResultURL` verification. Works without the
native SDKs.
