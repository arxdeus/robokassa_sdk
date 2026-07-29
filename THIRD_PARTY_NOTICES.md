# Third-party notices

`robokassa_sdk` redistributes source code from Robokassa's official native
payment SDKs. Both are MIT licensed, and MIT requires that the copyright
notice and permission notice be preserved in redistributions. The full texts
are reproduced verbatim below.

| Upstream project | Vendored into | Package namespace |
| --- | --- | --- |
| [robokassa/sdk-android](https://github.com/robokassa/sdk-android) | `android/src/main/kotlin/com/robokassa/library/`, `android/src/main/res/` | `com.robokassa.library.**` |
| [robokassa/sdk-ios](https://github.com/robokassa/sdk-ios) | `ios/robokassa_sdk/Sources/robokassa_sdk/RobokassaSDK/` | `RobokassaSDK` |

The vendored sources are modified only where the plugin build requires it. The
Android copy replaces the upstream `konsume-xml` dependency with the
platform's own `XmlPullParser`; no signature, request-building or
payment-state logic is altered. Where a vendored file was changed, the change
is noted in a `VENDORED.md` next to it.

Nothing else in this package is third-party. The Dart layer
(`RobokassaSignature`, `RobokassaLinkBuilder`, `RobokassaCallback`,
`RobokassaApi`, `Receipt`) is an independent implementation written from
Robokassa's public protocol documentation.

---

## robokassa/sdk-android

```
MIT License

Copyright (c) 2024 Robokassa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## robokassa/sdk-ios

```
MIT License

Copyright (c) 2024 madjios

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
