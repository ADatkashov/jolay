import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// A release build must never silently fall back to the debug key: such an APK/AAB cannot be published, and an app installed from it cannot be
// updated by a properly signed build. Local experiments can opt out with JOLAY_ALLOW_DEBUG_SIGNED_RELEASE=true.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && (it.name == "assembleRelease" || it.name == "bundleRelease") }
    if (buildsRelease && !keystoreProperties.containsKey("storeFile") && System.getenv("JOLAY_ALLOW_DEBUG_SIGNED_RELEASE") != "true") {
        throw GradleException("Release build without android/key.properties would be signed with the DEBUG key. Provide the release keystore " +
            "(see .github/workflows/android-release.yml) or set JOLAY_ALLOW_DEBUG_SIGNED_RELEASE=true for a local, unpublishable build.")
    }
}

android {
    namespace = "kz.jolay.driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "kz.jolay.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Release signing comes from android/key.properties (git-ignored). Without it, release tasks fail (see the guard above); the debug key is only a local opt-in.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
