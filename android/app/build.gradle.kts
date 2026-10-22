plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.imaps_fieldsync"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The QA preview is a separate application: same code base, its own
        // package id, its own private data sandbox and its own launcher label.
        // Only a build started with FIELDSYNC_QA_BUILD=1 is affected; every
        // other build keeps the production identity below.
        val qaBuild = System.getenv("FIELDSYNC_QA_BUILD") == "1"
        applicationId = if (qaBuild) {
            "com.example.imaps_fieldsync.qa"
        } else {
            "com.example.imaps_fieldsync"
        }
        manifestPlaceholders["appLabel"] = if (qaBuild) "FieldSync QA" else "imaps_fieldsync"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
