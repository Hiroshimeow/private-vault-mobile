plugins {
    id("com.android.application")
}

android {
    namespace = "io.hiroshimeow.private_vault_pluginfixture"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.hiroshimeow.private_vault.pluginfixture"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
