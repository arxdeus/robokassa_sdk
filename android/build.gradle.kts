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
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        // Robokassa's Android library pulls konsume-xml from JitPack. Only the
        // pre-built-AAR path needs this; harmless otherwise.
        maven { url = uri("https://jitpack.io") }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ru.robokassa.robokassa_sdk"

    compileSdk = 36

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
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// ---------------------------------------------------------------------------
// Locating Robokassa's Android SDK
// ---------------------------------------------------------------------------
//
// Robokassa does not publish `Robokassa_Library` to Maven Central or any other
// registry — https://github.com/robokassa/sdk-android ships it as a Gradle
// module plus pre-built AARs. So the app has to supply it, and this block finds
// it, in order of preference:
//
//   1. `robokassa.android.dependency` in gradle.properties — Maven coordinates,
//      for teams that mirror the library into a private repository.
//   2. A Gradle module included in the app's settings.gradle, by default
//      `:Robokassa_Library`. Override the path with `robokassa.android.module`.
//   3. A pre-built AAR found in `android/robokassa/`, `android/app/libs/` or
//      `android/libs/`. Override the directory with `robokassa.android.aarDir`.
//
// If none is present the build stops here with instructions, rather than
// several hundred lines of "unresolved reference: com.robokassa".

fun stringProperty(name: String): String? =
    (project.findProperty(name) as String?)?.takeIf { it.isNotBlank() }

val robokassaCoordinates: String? = stringProperty("robokassa.android.dependency")
val robokassaModulePath: String = stringProperty("robokassa.android.module") ?: ":Robokassa_Library"

val robokassaAar: File? = run {
    val searchDirs = listOfNotNull(
        stringProperty("robokassa.android.aarDir")?.let { file(it) },
        rootProject.file("robokassa"),
        rootProject.file("app/libs"),
        rootProject.file("libs"),
    )
    searchDirs
        .asSequence()
        .filter { it.isDirectory }
        .flatMap { (it.listFiles() ?: emptyArray()).asSequence() }
        .filter { it.isFile && it.extension == "aar" && it.name.startsWith("Robokassa", ignoreCase = true) }
        // Prefer a release build when both variants are present.
        .sortedBy { if (it.name.contains("debug", ignoreCase = true)) 1 else 0 }
        .firstOrNull()
}

val robokassaModule: Project? =
    if (robokassaCoordinates == null) rootProject.findProject(robokassaModulePath) else null

if (robokassaCoordinates == null && robokassaModule == null && robokassaAar == null) {
    throw GradleException(
        """
        |
        |  robokassa_sdk: Robokassa's Android SDK was not found.
        |
        |  This plugin deliberately does not bundle it — Robokassa publishes
        |  https://github.com/robokassa/sdk-android as source, not as an artifact,
        |  so your app supplies it. Pick ONE of these:
        |
        |  (a) Gradle module — recommended
        |      1. Copy `Robokassa_Library/` from the SDK repo next to your
        |         `android/` folder.
        |      2. In `android/settings.gradle.kts` add:
        |             include(":Robokassa_Library")
        |             project(":Robokassa_Library").projectDir = file("../Robokassa_Library")
        |
        |  (b) Pre-built AAR
        |      Drop `Robokassa_Library-release.aar` (from the SDK repo's `app/lib/`)
        |      into `android/robokassa/`.
        |
        |  (c) Private Maven mirror
        |      In `android/gradle.properties` add:
        |             robokassa.android.dependency=com.example:robokassa-library:1.0.0
        |
        |  Searched for a module at "$robokassaModulePath" and for an AAR in
        |  android/robokassa, android/app/libs and android/libs.
        |  Full instructions: see the robokassa_sdk README, "Android setup".
        |
        """.trimMargin()
    )
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.appcompat:appcompat:1.6.1")

    when {
        robokassaCoordinates != null -> implementation(robokassaCoordinates)

        robokassaModule != null -> implementation(project(robokassaModulePath))

        // A file-backed AAR carries no POM, so its transitive dependencies have
        // to be restated. These mirror `Robokassa_Library/build.gradle.kts`.
        else -> {
            implementation(files(robokassaAar!!))
            implementation("androidx.core:core-ktx:1.12.0")
            implementation("com.google.android.material:material:1.11.0")
            implementation("androidx.activity:activity-ktx:1.9.0")
            implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.1")
            implementation("androidx.lifecycle:lifecycle-common-java8:2.8.1")
            implementation("androidx.constraintlayout:constraintlayout:2.1.4")
            implementation("com.squareup.okhttp3:okhttp:4.12.0")
            implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
            implementation("com.gitlab.mvysny.konsume-xml:konsume-xml:1.1")
            implementation("com.google.code.gson:gson:2.10.1")
        }
    }

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}

logger.lifecycle(
    "robokassa_sdk: using Robokassa Android SDK from " + when {
        robokassaCoordinates != null -> "Maven coordinates $robokassaCoordinates"
        robokassaModule != null -> "Gradle module $robokassaModulePath"
        else -> "AAR ${robokassaAar!!.absolutePath}"
    }
)
