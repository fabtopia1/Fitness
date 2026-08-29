import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase's Gradle plugins are applied ONLY when this build has credentials
// for at least one flavour.
//
// google-services generates the resources that google_sign_in reads to obtain
// an ID token, and it is the prerequisite for the Crashlytics plugin that
// uploads the R8 mapping file — without which every release crash report
// arrives obfuscated. Applying them unconditionally would break a fresh clone,
// which must still build and run in local mode.
val hasFirebaseCredentials =
    listOf("google-services.json", "src/dev", "src/staging", "src/prod")
        .map { if (it.endsWith(".json")) file(it) else file("$it/google-services.json") }
        .any { it.exists() }

if (hasFirebaseCredentials) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.lifecycle(
        "LifeDNA: no google-services.json found — building WITHOUT Firebase " +
            "Gradle plugins. Google Sign-In will not return an ID token and " +
            "Crashlytics will not upload a mapping file. See " +
            "docs/mvp/18-google-auth-verification.md.",
    )
}

// Release signing comes from android/key.properties, which is never committed.
// Without it the release build falls back to the debug key so that
// `flutter build apk --release` still works on a fresh clone; CI supplies the
// real file from a secret.
//
// A PARTIALLY configured keystore fails the build instead of falling back.
// Silently debug-signing an artefact that was asked for as a release build is
// the worst outcome available: Play rejects the upload late, and a sideloaded
// beta APK gets ApiException: 10 from Google Sign-In because the debug
// certificate's SHA-1 was never registered. Both failures point away from the
// cause.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }

    val missing = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties is missing: ${missing.joinToString(", ")}. " +
                "Remove the file to build with the debug key, or complete it. " +
                "See docs/mvp/19-build-validation-report.md.",
        )
    }

    val storeFile = file(keystoreProperties.getProperty("storeFile"))
    if (!storeFile.exists()) {
        throw GradleException(
            "android/key.properties points storeFile at ${storeFile.absolutePath}, " +
                "which does not exist. See docs/mvp/19-build-validation-report.md.",
        )
    }
} else {
    // Not an error: a fresh clone must still be able to produce an installable
    // artefact. It is worth saying out loud, because the consequence is not
    // visible in the resulting file.
    logger.lifecycle(
        "LifeDNA: no android/key.properties — release builds will be signed " +
            "with the DEBUG key. They are installable, but Play will reject " +
            "them and Google Sign-In fails unless the debug SHA-1 is " +
            "registered. See docs/mvp/18-google-auth-verification.md.",
    )
}

android {
    namespace = "os.lifedna.lifedna"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications: it uses java.time on API
        // levels that predate it.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "os.lifedna.lifedna"
        // 24 is the floor: firebase_auth requires 23, and Android 7 is where
        // the notification-channel behaviour this app relies on begins.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // No multiDexEnabled: native multidex has existed since API 21 and
        // minSdk here is 24, so the flag and the support library are both
        // no-ops that only mislead the next reader.
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // One artefact per environment, installable side by side. There is no
    // runtime switch between them: a staging build can never reach production
    // data because it is a different binary with a different Firebase config.
    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("prod") {
            dimension = "environment"
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // Keeps crash line numbers readable while testing.
            isMinifyEnabled = false
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // Required by flutter_local_notifications, which uses java.time.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
