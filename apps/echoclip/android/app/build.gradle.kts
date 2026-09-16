import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Private, local configuration. See key.properties.example and docs/ANDROID_SIGNING.md.
val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningFile.isFile) {
        releaseSigningFile.reader(Charsets.UTF_8).use { load(it) }
    }
}
val releaseStoreFile = releaseSigningProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { rootProject.file(it) }

// Keep Debug builds usable without release credentials. Every Release build must
// pass this task; missing credentials must never produce a Debug-signed release.
val validateReleaseSigningConfig = tasks.register("validateReleaseSigningConfig") {
    group = "verification"
    description = "Checks that local release signing settings and keystore exist."
    doLast {
        if (!releaseSigningFile.isFile) {
            throw GradleException(
                "Release signing is not configured. Copy android/key.properties.example " +
                    "to android/key.properties and fill in your keystore settings. " +
                    "See docs/ANDROID_SIGNING.md. Debug builds do not need this file."
            )
        }
        val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .filter { releaseSigningProperties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Release signing: fill in these android/key.properties entries: " +
                    missing.joinToString(", ") + ". See docs/ANDROID_SIGNING.md."
            )
        }
        if (releaseStoreFile?.isFile != true) {
            throw GradleException(
                "Release signing: storeFile must point to an existing keystore. " +
                    "Use forward slashes in Windows paths. See docs/ANDROID_SIGNING.md."
            )
        }
    }
}

tasks.matching {
    it.name == "preReleaseBuild" || it.name == "validateSigningRelease"
}.configureEach {
    dependsOn(validateReleaseSigningConfig)
}

android {
    namespace = "com.echoclip.echoclip"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.echoclip.echoclip"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // EchoClip's Rust audio core and packaged FFmpeg binary are built for
        // Android arm64 only. Keep Flutter's engine/app libraries on the same
        // ABI so the APK cannot advertise unsupported 32-bit or x86 devices.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    testOptions {
        // JVM lifecycle tests exercise service state with Android effects stubbed.
        unitTests.isReturnDefaultValues = true
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseSigningProperties.getProperty("storePassword")
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        jniLibs {
            // FFmpeg is packaged as jniLibs/<abi>/libffmpeg.so but executed as a
            // process, so it must be extracted into applicationInfo.nativeLibraryDir.
            useLegacyPackaging = true
            // Dependency AARs (e.g. the Dart JNI runtime) ship libdartjni.so for
            // every ABI, which would otherwise leak armeabi-v7a/x86/x86_64 into
            // the package. EchoClip targets arm64-v8a only, so drop the rest.
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**"
            )
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
