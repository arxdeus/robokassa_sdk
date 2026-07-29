// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift Package Manager variant of the plugin.
//
// Robokassa's iOS SDK is vendored under Sources/robokassa_sdk/RobokassaSDK and
// compiled straight into this target, so neither packaging path needs any extra
// setup by the host app. See that directory's VENDORED.md.
let package = Package(
    name: "robokassa_sdk",
    platforms: [
        // Robokassa's iOS SDK requires iOS 14.
        .iOS("14.0")
    ],
    products: [
        .library(name: "robokassa-sdk", targets: ["robokassa_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "robokassa_sdk",
            // Documentation, not a resource — otherwise SwiftPM warns about an
            // unhandled file in the target directory.
            exclude: ["RobokassaSDK/VENDORED.md"],
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
                // Loading spinner shown by the vendored SDK's WebViewController.
                .process("RobokassaSDK/AssetsResources/ic_robokassa_loader.png")
            ]
        )
    ]
)
