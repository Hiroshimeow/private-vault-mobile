import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    releaseSigningProperties.getProperty(propertyName)?.trim()?.takeIf { it.isNotEmpty() }
        ?: System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }

android {
    namespace = "io.hiroshimeow.private_vault_clonehost"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "0.1-experiment"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    flavorDimensions += "slot"
    productFlavors {
        create("slot0") {
            dimension = "slot"
            applicationId = "io.hiroshimeow.private_vault.clonehost.slot0"
            buildConfigField("int", "CLONE_SLOT", "0")
        }
        create("slot1") {
            dimension = "slot"
            applicationId = "io.hiroshimeow.private_vault.clonehost.slot1"
            buildConfigField("int", "CLONE_SLOT", "1")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        val storePath = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
        if (storePath != null) {
            create("release") {
                storeFile = rootProject.file(storePath)
                storePassword = releaseSigningValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
