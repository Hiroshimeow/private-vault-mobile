import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    val propertyValue = releaseSigningProperties.getProperty(propertyName)?.trim()
    if (!propertyValue.isNullOrEmpty()) {
        return propertyValue
    }
    return System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }
}

val releaseStoreFilePath = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningValues = mapOf(
    "storeFile/ANDROID_KEYSTORE_PATH" to releaseStoreFilePath,
    "storePassword/ANDROID_KEYSTORE_PASSWORD" to releaseStorePassword,
    "keyAlias/ANDROID_KEY_ALIAS" to releaseKeyAlias,
    "keyPassword/ANDROID_KEY_PASSWORD" to releaseKeyPassword,
)
val missingReleaseSigningValues = releaseSigningValues
    .filterValues { it.isNullOrEmpty() }
    .keys
val releaseStoreFile = releaseStoreFilePath?.let { rootProject.file(it) }

fun validateReleaseSigning() {
    if (missingReleaseSigningValues.isNotEmpty()) {
        throw GradleException(
            "Release signing is not configured. Missing: " +
                missingReleaseSigningValues.joinToString() +
                ". Provide android/key.properties or ANDROID_KEYSTORE_* environment variables.",
        )
    }
    if (releaseStoreFile != null && !releaseStoreFile.isFile) {
        throw GradleException(
            "Release signing keystore does not exist: ${releaseStoreFile.absolutePath}",
        )
    }
}

val releaseCapableAggregateTasks = setOf("assemble", "build", "bundle")
val releaseArtifactTasks = setOf("assembleRelease", "bundleRelease", "installRelease")

fun releaseSigningTaskRequested(taskName: String): Boolean {
    val selector = taskName.substringAfterLast(':')
    val releaseCapableSelector =
        releaseCapableAggregateTasks.any { selector.equals(it, ignoreCase = true) } ||
            releaseArtifactTasks.any { selector.equals(it, ignoreCase = true) }
    if (!releaseCapableSelector) {
        return false
    }

    val separatorIndex = taskName.lastIndexOf(':')
    if (separatorIndex < 0) {
        return true
    }

    val requestedProjectPath = taskName
        .substring(0, separatorIndex)
        .ifEmpty { ":" }
        .let { if (it.startsWith(':')) it else ":$it" }
    return requestedProjectPath == project.path
}

if (gradle.startParameter.taskNames.any(::releaseSigningTaskRequested)) {
    validateReleaseSigning()
}

gradle.taskGraph.whenReady {
    val releaseBuildRequested = allTasks.any { task ->
        task.project == project && releaseSigningTaskRequested(task.name)
    }
    if (releaseBuildRequested) {
        validateReleaseSigning()
    }
}

android {
    namespace = "io.hiroshimeow.private_vault_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.hiroshimeow.private_vault_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.1.0")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
