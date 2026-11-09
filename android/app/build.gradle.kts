import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 固定簽章金鑰：android/key.properties（不進 git）指定金鑰時用它簽署，
// 換電腦建置也能覆蓋安裝舊版；沒有這個檔案時沿用本機 debug 金鑰。
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasFixedKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.bili.tv.bili_tv_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.gordonpow.pilibtrtv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ndk {
        //    // abiFilters.add("armeabi-v7a")
        // }
    }

    signingConfigs {
        if (hasFixedKey) {
            create("fixed") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        val signing =
            if (hasFixedKey) signingConfigs.getByName("fixed")
            else signingConfigs.getByName("debug")
        getByName("debug") {
            signingConfig = signing
        }
        getByName("release") {
            signingConfig = signing
        }
    }
}

flutter {
    source = "../.."
}
