import java.util.Base64

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// External demo-signing inputs. The credential owner supplies the keystore
// path/alias/secrets as process environment or Gradle properties; they never
// live in source control and this file carries references only. Missing inputs
// must not disturb regular prod builds, so validation is deferred to the
// task-graph gate below, which fires only for scheduled demo tasks.
val demoKeystorePath: String? =
    System.getenv("FIELDSYNC_DEMO_KEYSTORE_PATH")
        ?: (project.findProperty("FIELDSYNC_DEMO_KEYSTORE_PATH") as String?)
val demoKeystoreAlias: String? =
    System.getenv("FIELDSYNC_DEMO_KEYSTORE_ALIAS")
        ?: (project.findProperty("FIELDSYNC_DEMO_KEYSTORE_ALIAS") as String?)
val demoKeystorePassword: String? =
    System.getenv("FIELDSYNC_DEMO_KEYSTORE_PASSWORD")
        ?: (project.findProperty("FIELDSYNC_DEMO_KEYSTORE_PASSWORD") as String?)
val demoKeyPassword: String? =
    System.getenv("FIELDSYNC_DEMO_KEY_PASSWORD")
        ?: (project.findProperty("FIELDSYNC_DEMO_KEY_PASSWORD") as String?)
val hasDemoSigningInputs =
    demoKeystorePath != null && demoKeystoreAlias != null &&
        demoKeystorePassword != null && demoKeyPassword != null

android {
    namespace = "com.example.imaps_fieldsync"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.imaps_fieldsync"
        manifestPlaceholders["appLabel"] = "imaps_fieldsync"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        // The demo signer is owned by the credential owner: never a debug-
        // keystore fallback and never a keystore created here. Without
        // external inputs the config stays empty; the task-graph gate rejects
        // any scheduled demo build, so nothing is signed silently.
        create("demo") {
            if (hasDemoSigningInputs) {
                storeFile = file(demoKeystorePath!!)
                storePassword = demoKeystorePassword
                keyAlias = demoKeystoreAlias
                keyPassword = demoKeyPassword
            }
        }
    }

    // One dimension, two flavors: strict prod/demo identity matrix. The old
    // FIELDSYNC_QA_BUILD environment switch is retired; requesting it now
    // produces the plain prod identity, and the Dart entry point rejects the
    // stale QA define anyway.
    flavorDimensions += "environment"
    productFlavors {
        create("prod") {
            dimension = "environment"
            // No .prod suffix: the regular installed identity is unchanged.
            applicationId = "com.example.imaps_fieldsync"
        }
        create("demo") {
            dimension = "environment"
            applicationId = "com.example.imaps_fieldsync.demo"
            manifestPlaceholders["appLabel"] = "FieldSync DEMO"
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    buildTypes {
        release {
            // Unchanged: prodRelease signing is the separate F-02 gate. The
            // execution gate below blocks scheduled prodRelease builds until
            // that approval lands.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// AGP selected-variant signing API (manifest P0.6): the demo signer must beat
// the implicit debug build-type signer, so it is assigned on the selected
// demoDebug variant rather than assumed from the flavor DSL. It is assigned
// only when the credential owner supplied inputs; prod variants keep their
// existing configuration.
val demoSigningConfig = android.signingConfigs.getByName("demo")
androidComponents {
    // Demo profile/release have no enabled variant; the runtime !kDebugMode
    // check rejects independently. Regular profile/release keep their own
    // gates (prodRelease is blocked in the execution gate below until F-02).
    beforeVariants(
        selector()
            .withFlavor("environment" to "demo")
            .withBuildType("profile"),
    ) { variantBuilder ->
        variantBuilder.enabled = false
    }
    beforeVariants(
        selector()
            .withFlavor("environment" to "demo")
            .withBuildType("release"),
    ) { variantBuilder ->
        variantBuilder.enabled = false
    }
    onVariants { variant ->
        if (variant.flavorName == "demo" &&
            variant.buildType == "debug" &&
            hasDemoSigningInputs
        ) {
            variant.signingConfig.setConfig(demoSigningConfig)
        }
    }
}

// Fail-closed variant/target/define gate. Runs when the execution graph is
// known, so a plain prod build never demands demo credentials, while every
// scheduled Flutter compile task is validated against the strict matrix,
// including direct Gradle invocations the flutter tool did not start:
//
//   prod  debug/profile -> lib/main.dart, no QA_PREVIEW
//   demo  debug         -> lib/main_qa.dart + QA_PREVIEW=true + approved
//                          signer pin + credential-owner signing inputs
//   everything else     -> rejected (demo profile/release are disabled above;
//                          prodRelease waits for the F-02 approval)
//
// The effective canonical target mirrors the installed Flutter tool's own
// precedence (-Ptarget, then the unused flutter{target} extension, then
// lib/main.dart). Dart defines arrive comma-separated and standard-base64
// encoded, exactly as the tool builds them (flutter_tools build_info.dart
// encodeDartDefines). Unknown/aggregate mixed-target execution fails here.
gradle.taskGraph.whenReady {
    val flutterTasks = allTasks.filter { it.name.startsWith("compileFlutterBuild") }
    if (flutterTasks.isEmpty()) return@whenReady

    fun variantParts(taskName: String): Pair<String, String> {
        val variantName = taskName.removePrefix("compileFlutterBuild")
        val flavor = when {
            variantName.startsWith("Prod", ignoreCase = true) -> "prod"
            variantName.startsWith("Demo", ignoreCase = true) -> "demo"
            else -> variantName.takeWhile { it.isLowerCase() }
        }
        return flavor to variantName.drop(flavor.length).lowercase()
    }

    // `flutter build` passes a relative entry point, while `flutter run`
    // passes an absolute one (ResidentRunner.mainPath). Canonicalise both
    // spellings against the Flutter project root; anything outside it stays
    // unmatched and is rejected below.
    val flutterRoot = rootProject.projectDir.parentFile.canonicalFile
    val rawTarget = (project.findProperty("target") as String?) ?: "lib/main.dart"
    val targetFile =
        File(rawTarget)
            .let { if (it.isAbsolute) it else File(flutterRoot, rawTarget) }
            .canonicalFile
    val target =
        runCatching {
            flutterRoot.toPath().relativize(targetFile.toPath()).toString().replace('\\', '/')
        }.getOrElse { "" }
    val defines: Set<String> = (project.findProperty("dart-defines") as String?)
        ?.split(',')
        ?.filter { it.isNotBlank() }
        ?.mapNotNull { entry ->
            runCatching {
                String(Base64.getDecoder().decode(entry), Charsets.UTF_8)
            }.getOrNull()
        }
        ?.toSet()
        ?: emptySet()
    val hasQaPreview = defines.contains("QA_PREVIEW=true")
    val signerPin =
        defines.firstOrNull { it.startsWith("FIELDSYNC_DEMO_SIGNER_SHA256=") }
            ?.substringAfter('=') ?: ""
    val pinIsApprovedSha256 =
        signerPin.length == 64 &&
            signerPin.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

    for (task in flutterTasks) {
        val (flavor, buildType) = variantParts(task.name)
        val reject = when (flavor) {
            "demo" -> when {
                buildType != "debug" ->
                    "demo profile/release variants are disabled; demo is debug-only"
                target != "lib/main_qa.dart" ->
                    "demoDebug must target lib/main_qa.dart"
                !hasQaPreview ->
                    "demoDebug requires --dart-define=QA_PREVIEW=true"
                !pinIsApprovedSha256 ->
                    "demoDebug requires the approved signer pin via " +
                        "--dart-define=FIELDSYNC_DEMO_SIGNER_SHA256=<64-hex SHA-256>"
                !hasDemoSigningInputs ->
                    "demo signing inputs (FIELDSYNC_DEMO_KEYSTORE_PATH/ALIAS/" +
                        "PASSWORD/KEY_PASSWORD) are missing; the debug keystore " +
                        "must not silently sign the demo app"
                else -> null
            }
            "prod" -> when {
                buildType == "release" ->
                    "prodRelease is blocked until the F-02 production " +
                        "signing approval; do not build or distribute it"
                buildType != "debug" && buildType != "profile" ->
                    "unknown prod build type '$buildType'"
                target != "lib/main.dart" ->
                    "prod variants must target lib/main.dart"
                hasQaPreview ->
                    "QA_PREVIEW=true must not be set for prod builds"
                else -> null
            }
            else -> "unknown flavor '$flavor' in scheduled task '${task.name}'"
        }
        if (reject != null) {
            throw GradleException("Rejected ${task.name}: $reject (Task 4 B1 build matrix).")
        }
    }

    // An in-repository keystore is not an external credential-owner input.
    val demoScheduled = flutterTasks.any { variantParts(it.name).first == "demo" }
    if (demoScheduled && hasDemoSigningInputs) {
        val repositoryRoot = rootProject.projectDir.parentFile.canonicalFile.toPath()
        val keystorePath = file(demoKeystorePath!!).canonicalFile.toPath()
        if (keystorePath.startsWith(repositoryRoot)) {
            throw GradleException(
                "Rejected demo signing: the keystore path must be supplied " +
                    "outside the repository.",
            )
        }
    }
}

flutter {
    source = "../.."
}
