# Vendored: Robokassa Android SDK

This subtree is a verbatim copy of Robokassa's official Android SDK library
module, vendored so that `flutter pub add robokassa_sdk` gives a working
Android build with no manual Gradle wiring in the consuming app.

- Upstream: <https://github.com/robokassa/sdk-android>
- Path:     `Robokassa_Library/src/main/java/com/robokassa/library/`
- Commit:   `ba251928cb4ebab30718d355d33b407d3d88a161`
- License:  MIT, Copyright (c) 2024 Robokassa (see upstream `LICENSE.txt`)

To diff against upstream, check out that commit and compare this directory
against `Robokassa_Library/src/main/java/com/robokassa/library/`.

## Local deltas

Everything here is byte-identical to upstream except:

1. `models/CheckPayState.kt` — `parse()` was rewritten on top of the platform's
   `XmlPullParser`. Upstream uses `com.gitlab.mvysny.konsume-xml`, which is only
   published on JitPack; a payments SDK should not force its consumers to add a
   low-trust binary repository. Parsed output is unchanged.

Resources live in `android/src/main/res/` (a Gradle module has one res root).
Upstream's `res/value-night/` was **not** copied: the directory name is a typo
(`value-night`, not `values-night`) which makes the night theme dead upstream,
and its `Theme.DedalOTA` references `@drawable/app_background_image`, which does
not exist in the SDK — copying it under the correct name would fail the build.
Nothing in the library references that theme, so it is simply omitted.
