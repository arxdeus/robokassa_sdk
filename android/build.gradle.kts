group = "ru.robokassa.robokassa_sdk"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        // Also supplies `kotlin-parcelize`, which the vendored
        // `RobokassaPayLauncher.Result` needs.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    // The vendored `RobokassaPayLauncher.Result` is @Parcelize. Upstream also
    // applies kotlin-kapt; nothing in the library uses an annotation processor,
    // so it is left out.
    id("kotlin-parcelize")
}

android {
    // Robokassa's SDK is vendored into src/main/kotlin/com/robokassa/library, and
    // `RobokassaActivity` imports `com.robokassa.library.R` plus the generated
    // `com.robokassa.library.databinding.ActivityRobokassaBinding`. AGP emits R
    // and ViewBinding under the module namespace and nowhere else, so the
    // namespace has to be the library's package. This is unrelated to Flutter's
    // plugin lookup, which resolves `ru.robokassa.robokassa_sdk.RobokassaSdkPlugin`
    // from pubspec.yaml against the classpath.
    namespace = "com.robokassa.library"

    compileSdk = 36

    buildFeatures {
        viewBinding = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // Robokassa's Android SDK requires Android 7.0.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        // Upstream's library module targets 1.8; the Flutter bridge and the
        // Flutter embedding are on 17, and one module cannot straddle both.
        // The vendored Kotlin has no 1.8-only constructs, so 17 it is.
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Versions mirror Robokassa_Library/build.gradle.kts at the vendored commit.
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.activity:activity-ktx:1.4.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.1")
    implementation("androidx.lifecycle:lifecycle-common-java8:2.8.1")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
    // konsume-xml is deliberately absent: it only exists on JitPack, and
    // CheckPayState now parses with the platform's XmlPullParser instead.

    // Used by the Flutter bridge itself.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
