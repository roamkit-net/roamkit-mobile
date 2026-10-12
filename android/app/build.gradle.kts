import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun resolveExistingFile(rawPath: String): File {
    val direct = file(rawPath)
    if (direct.exists()) {
        return direct
    }
    val normalized = rawPath.replace('\\', '/')
    val drive = Regex("""^([A-Za-z]):/(.*)$""").find(normalized)
    if (drive != null) {
        val translated = file("/mnt/${drive.groupValues[1].lowercase()}/${drive.groupValues[2]}")
        if (translated.exists()) {
            return translated
        }
    }
    return direct
}

android {
    namespace = "net.roamkit.roamkit_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "net.roamkit.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            val secrets = Properties()
            val secretsRaw = keystoreProperties.getProperty("secretsFile")
                ?: error("android/key.properties is missing secretsFile")
            resolveExistingFile(secretsRaw).inputStream().use { secrets.load(it) }
            create("release") {
                keyAlias = secrets.getProperty("KEYSTORE_ALIAS")
                keyPassword = secrets.getProperty("KEY_PASSWORD")
                storePassword = secrets.getProperty("KEYSTORE_PASSWORD")
                val storeRaw = keystoreProperties.getProperty("storeFile")
                    ?: secrets.getProperty("KEYSTORE_PATH")
                storeFile = resolveExistingFile(storeRaw)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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
