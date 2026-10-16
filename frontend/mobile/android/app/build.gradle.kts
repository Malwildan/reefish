import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.reefish.reefish_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.reefish.reefish_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigningFile = rootProject.file("key.properties")
    val releaseRequested = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
    if (releaseRequested && !releaseSigningFile.isFile) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties and the referenced " +
                "upload keystore before building a release APK. See RELEASE.md."
        )
    }
    val releaseSigning = Properties()
    if (releaseSigningFile.isFile) {
        releaseSigningFile.inputStream().use { input -> releaseSigning.load(input) }
    }
    val releaseKeystorePath = releaseSigning.getProperty("storeFile")
    val releaseKeystore = releaseKeystorePath?.let(rootProject::file)
    if (releaseRequested && (releaseKeystore == null || !releaseKeystore.isFile)) {
        throw GradleException("Release keystore is missing at ${releaseKeystorePath ?: "<storeFile unset>"}; see RELEASE.md.")
    }
    val releaseSigningConfigured = releaseKeystore?.isFile == true &&
        listOf("keyAlias", "keyPassword", "storePassword").all { !releaseSigning.getProperty(it).isNullOrBlank() }
    if (releaseRequested && !releaseSigningConfigured) {
        throw GradleException("Release signing values are incomplete in android/key.properties.")
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
                storeFile = releaseKeystore
                storePassword = releaseSigning.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                null
            }
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
