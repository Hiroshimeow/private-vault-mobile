import com.android.build.gradle.internal.dsl.BaseAppModuleExtension
import java.util.Properties

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    val propertyValue = releaseSigningProperties.getProperty(propertyName)?.trim()
    if (!propertyValue.isNullOrEmpty()) return propertyValue
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
val missingReleaseSigningValues = releaseSigningValues.filterValues { it.isNullOrEmpty() }.keys
val releaseStoreFile = releaseStoreFilePath?.let(rootProject::file)

fun validateReleaseSigning() {
    if (missingReleaseSigningValues.isNotEmpty()) {
        throw GradleException(
            "Release signing is not configured. Missing: " +
                missingReleaseSigningValues.joinToString() +
                ". Provide android/key.properties or ANDROID_KEYSTORE_* environment variables.",
        )
    }
    if (releaseStoreFile != null && !releaseStoreFile.isFile) {
        throw GradleException("Release signing keystore does not exist: ${releaseStoreFile.absolutePath}")
    }
}

fun releaseSigningTaskRequested(taskName: String): Boolean {
    val selector = taskName.substringAfterLast(':')
    val releaseArtifact =
        (selector.startsWith("assemble", ignoreCase = true) ||
            selector.startsWith("bundle", ignoreCase = true) ||
            selector.startsWith("install", ignoreCase = true)) &&
            selector.endsWith("Release", ignoreCase = true)
    val aggregate = selector.equals("assemble", true) || selector.equals("build", true) || selector.equals("bundle", true)
    if (!releaseArtifact && !aggregate) return false

    val separatorIndex = taskName.lastIndexOf(':')
    if (separatorIndex < 0) return true
    val requestedProjectPath = taskName.substring(0, separatorIndex).ifEmpty { ":" }.let {
        if (it.startsWith(':')) it else ":$it"
    }
    return requestedProjectPath == project.path
}

if (gradle.startParameter.taskNames.any(::releaseSigningTaskRequested)) validateReleaseSigning()

gradle.taskGraph.whenReady {
    if (allTasks.any { task -> task.project == project && releaseSigningTaskRequested(task.path) }) {
        validateReleaseSigning()
    }
}

extensions.configure<BaseAppModuleExtension>("android") {
    signingConfigs {
        maybeCreate("release").apply {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        getByName("release").signingConfig = signingConfigs.getByName("release")
    }
}
