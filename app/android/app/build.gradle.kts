import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // With android.builtInKotlin=false it also applies the Kotlin plugin to this module.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}
val wantsRelease = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (wantsRelease) {
    require(signingFile.exists()) { "Configure android/key.properties before building release." }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach {
        require(!signingProperties.getProperty(it).isNullOrBlank()) { "Missing signing property: $it" }
    }
}

// Flutter hands --dart-define and --dart-define-from-file values to Gradle base64-encoded, so the
// AdMob app ID can live in the same untracked config file as the ad unit ID read by the app.
val dartDefines: Map<String, String> =
    (findProperty("dart-defines") as String?).orEmpty()
        .split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8).split("=", limit = 2) }
        .filter { it.size == 2 }
        .associate { it[0] to it[1] }
val adMobAppId = dartDefines["ADMOB_APP_ID"].orEmpty()
val adMobUnitId = dartDefines["ADMOB_APP_OPEN_ID"].orEmpty()
require(adMobAppId.isEmpty() == adMobUnitId.isEmpty()) {
    "Pass ADMOB_APP_ID and ADMOB_APP_OPEN_ID together: the ad unit must belong to the app."
}
if (wantsRelease && adMobAppId.isEmpty()) {
    logger.warn("Release build without ADMOB_APP_ID and ADMOB_APP_OPEN_ID: it will not show ads.")
}
// Google Play wants the privacy policy reachable inside the app, and on Android its link is built
// from SITE_URL: without it the link would silently disappear.
require(!wantsRelease || dartDefines["SITE_URL"].orEmpty().startsWith("https://")) {
    "Release builds need SITE_URL (https://...) so the app links to the privacy policy."
}

android {
    namespace = "br.com.ninho.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The application ID identifies the app on Google Play and cannot change after the first upload.
        applicationId = "br.com.ninho.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Google Play requires API 36 for new apps and updates since 31 August 2026.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The Mobile Ads SDK stops the app at launch without an app ID. Google's sample ID only
        // serves test ads, which is what builds without the AdMob values get.
        manifestPlaceholders["adMobAppId"] = adMobAppId.ifEmpty { "ca-app-pub-3940256099942544~3347511713" }
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (signingFile.exists()) signingConfig = signingConfigs.getByName("release")
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
