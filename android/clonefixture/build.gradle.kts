plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.hiroshimeow.clonefixture"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.hiroshimeow.clonefixture"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    flavorDimensions += "shape"
    productFlavors {
        create("supported") {
            dimension = "shape"
            applicationIdSuffix = ".supported"
        }
        create("unsupported") {
            dimension = "shape"
            applicationIdSuffix = ".unsupported"
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
