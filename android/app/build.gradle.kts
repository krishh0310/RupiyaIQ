plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rupiyaiq.rupiya_iq"
    // compileSdk must stay ≥ 36: CameraX 1.6 (camera plugin) and
    // permission_handler_android require it; 34 fails `flutter build apk`.
    // compileSdk only affects which APIs we compile against, not which phones run the app.
    compileSdk = flutter.compileSdkVersion // = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rupiyaiq.rupiya_iq"
        minSdk = 24 // ML Kit + camera; spec: API 24+
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signed with debug keys so `flutter build apk --release` / `flutter run --release`
            // work out of the box for the hackathon. Add a real keystore before any store upload.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
