import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: processes google-services.json into resources at build time.
    id("com.google.gms.google-services")
}

// Release signing — secrets live in android/key.properties (gitignored), never
// in the repo. When the file is absent (fresh clone / CI without the keystore)
// the release build falls back to debug keys so `flutter run --release` works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.dewdrop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // App ID — must match the Firebase Android app (google-services.json) and
        // the Apple bundle id (app.dewdrop). SDK/version values flow from Flutter.
        applicationId = "app.dewdrop"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Le repli sur la clé de débogage sert `flutter run --release`, qui
            // exige une signature quelconque. Mais il se dit : un AAB signé en
            // débogage est accepté sans un mot par Gradle et refusé par Play,
            // une demi-heure plus tard, sans indice sur la cause.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "ATTENTION : android/key.properties absent — la version " +
                        "release est signée avec la clé de DÉBOGAGE. Play " +
                        "refusera cet AAB. Voir ../android-signing-guide.md.",
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
