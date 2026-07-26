pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// --- Robokassa Android SDK (consumer-side setup) -----------------------------
//
// robokassa_sdk does not bundle Robokassa's Android library, because Robokassa
// publishes https://github.com/robokassa/sdk-android as source rather than as a
// Maven artifact. Fetch it with:
//
//     dart run robokassa_sdk:fetch_native_sdks       (from the example folder)
//
// which clones the SDK into `example/native/sdk-android`. The block below wires
// that checkout in when it is present, and stays quiet when it is not so that
// `flutter pub get` still works on a fresh clone.
val robokassaLibrary = file("../native/sdk-android/Robokassa_Library")
if (robokassaLibrary.isDirectory) {
    include(":Robokassa_Library")
    project(":Robokassa_Library").projectDir = robokassaLibrary
} else {
    logger.warn(
        "robokassa_sdk: ${robokassaLibrary.path} not found — run " +
            "`dart run robokassa_sdk:fetch_native_sdks` before building for Android."
    )
}
