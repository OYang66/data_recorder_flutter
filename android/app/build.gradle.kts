import java.util.Properties

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

val parentLocalProperties = Properties().apply {
    val file = rootProject.file("../../local.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

fun localOrEnv(vararg names: String): String {
    return names.firstNotNullOfOrNull { name ->
        localProperties.getProperty(name)?.takeIf { it.isNotBlank() }
            ?: parentLocalProperties.getProperty(name)?.takeIf { it.isNotBlank() }
            ?: System.getenv(name)?.takeIf { it.isNotBlank() }
    }?.trim().orEmpty()
}

fun buildConfigString(value: String): String {
    return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}

val sparkAppId = localOrEnv("SPARK_APP_ID", "XUNFEI_SPARK_APP_ID")
val sparkApiKey = localOrEnv("SPARK_API_KEY", "XUNFEI_SPARK_API_KEY")
val sparkApiSecret = localOrEnv("SPARK_API_SECRET", "XUNFEI_SPARK_API_SECRET")

val dataRecorderStoreFile = localOrEnv("DATARECORDER_STORE_FILE")
val dataRecorderStorePassword = localOrEnv("DATARECORDER_STORE_PASSWORD")
val dataRecorderKeyAlias = localOrEnv("DATARECORDER_KEY_ALIAS")
val dataRecorderKeyPassword = localOrEnv("DATARECORDER_KEY_PASSWORD")
val hasDataRecorderSigning = listOf(
    dataRecorderStoreFile,
    dataRecorderStorePassword,
    dataRecorderKeyAlias,
    dataRecorderKeyPassword
).all { it.isNotBlank() }

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.datarecorder"
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
        applicationId = "com.example.datarecorder"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "SPARK_APP_ID", buildConfigString(sparkAppId))
        buildConfigField("String", "SPARK_API_KEY", buildConfigString(sparkApiKey))
        buildConfigField("String", "SPARK_API_SECRET", buildConfigString(sparkApiSecret))
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            if (hasDataRecorderSigning) {
                storeFile = file(dataRecorderStoreFile)
                storePassword = dataRecorderStorePassword
                keyAlias = dataRecorderKeyAlias
                keyPassword = dataRecorderKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasDataRecorderSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/SparkChain.aar"))
    implementation(files("libs/Codec.aar"))
}
