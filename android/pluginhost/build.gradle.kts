plugins {
    id("com.android.application")
}

apply(from = rootProject.file("release-signing.gradle.kts"))

android {
    namespace = "io.hiroshimeow.private_vault_pluginhost"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }

    flavorDimensions += "slot"
    productFlavors {
        create("slot0") {
            dimension = "slot"
            applicationId = "io.hiroshimeow.private_vault.pluginhost.slot0"
            manifestPlaceholders["slotId"] = "0"
        }
        create("slot1") {
            dimension = "slot"
            applicationId = "io.hiroshimeow.private_vault.pluginhost.slot1"
            manifestPlaceholders["slotId"] = "1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("org.smali:dexlib2:2.5.2")
    testImplementation("junit:junit:4.13.2")
}
