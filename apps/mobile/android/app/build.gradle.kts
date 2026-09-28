plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val getuiAppId = providers.gradleProperty("BINGO_GETUI_APP_ID")
    .orElse(providers.environmentVariable("BINGO_GETUI_APP_ID"))
    .getOrElse("")
fun pushProperty(name: String): String = providers.gradleProperty(name)
    .orElse(providers.environmentVariable(name))
    .getOrElse("")

android {
    namespace = "com.example.bingo"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.bingo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GETUI_APPID"] = getuiAppId.ifBlank { "not-configured" }
        manifestPlaceholders["XIAOMI_APP_ID"] = pushProperty("BINGO_XIAOMI_APP_ID")
        manifestPlaceholders["XIAOMI_APP_KEY"] = pushProperty("BINGO_XIAOMI_APP_KEY")
        manifestPlaceholders["OPPO_APP_KEY"] = pushProperty("BINGO_OPPO_APP_KEY")
        manifestPlaceholders["OPPO_APP_SECRET"] = pushProperty("BINGO_OPPO_APP_SECRET")
        manifestPlaceholders["VIVO_APP_ID"] = pushProperty("BINGO_VIVO_APP_ID")
        manifestPlaceholders["VIVO_APP_KEY"] = pushProperty("BINGO_VIVO_APP_KEY")
        buildConfigField("boolean", "GETUI_CONFIGURED", getuiAppId.isNotBlank().toString())
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.getui:gtsdk:3.3.12.0")
    implementation("com.getui:gtc:3.2.18.0")
    implementation("com.getui.opt:xmp:3.3.7")
    implementation("com.assist-v3:oppo:3.6.0")
    implementation("com.assist-v3:vivo:3.2.0")
}
