package io.hiroshimeow.private_vault_pluginhost

import java.io.File
import java.util.Properties

const val TRANSFORM_SCHEMA_VERSION = 1

enum class PluginResult(val wire: String) {
    READY("ready"),
    HELPER_MISSING("helper_missing"),
    NO_FREE_SLOT("no_free_slot"),
    TRANSFORM_UNSUPPORTED("transform_unsupported"),
    TRANSFORM_FAILED("transform_failed"),
    PACKAGE_UNREADABLE("package_unreadable"),
    MISSING_SPLIT("missing_split"),
    UNSUPPORTED_SPLIT_CODE("unsupported_split_code"),
    UNSUPPORTED_PROVIDER("unsupported_provider"),
    UNSUPPORTED_SERVICE("unsupported_service"),
    UNSUPPORTED_RECEIVER("unsupported_receiver"),
    UNSUPPORTED_MULTIPROCESS("unsupported_multiprocess"),
    UNSUPPORTED_ABI("unsupported_abi"),
    UNSUPPORTED_NATIVE_PATH_BEHAVIOR("unsupported_native_path_behavior"),
    SOURCE_SIGNER_CHANGED("source_signer_changed"),
    LAUNCH_FAILED("launch_failed"),
    OPERATION_FAILED("operation_failed"),
}

data class GuestArtifactMetadata(
    val sourcePackage: String,
    val versionCode: Long,
    val versionName: String,
    val sourceSignerDigests: List<String>,
    val sourceApkSha256: LinkedHashMap<String, String>,
    val launcherClass: String,
    val applicationClass: String?,
    val transformSchemaVersion: Int,
) {
    fun writeTo(file: File) {
        val props = Properties().apply {
            setProperty("sourcePackage", sourcePackage)
            setProperty("versionCode", versionCode.toString())
            setProperty("versionName", versionName)
            setProperty("sourceSignerDigests", sourceSignerDigests.joinToString(","))
            setProperty("sourceApkSha256", sourceApkSha256.entries.joinToString("|") { "${it.key}=${it.value}" })
            setProperty("launcherClass", launcherClass)
            setProperty("applicationClass", applicationClass.orEmpty())
            setProperty("transformSchemaVersion", transformSchemaVersion.toString())
        }
        file.outputStream().buffered().use { props.store(it, null) }
    }

    companion object {
        fun readFrom(file: File): GuestArtifactMetadata {
            val props = Properties().apply { file.inputStream().buffered().use(::load) }
            val hashes = linkedMapOf<String, String>()
            props.getProperty("sourceApkSha256").orEmpty().split('|')
                .filter(String::isNotEmpty)
                .forEach { item ->
                    val index = item.indexOf('=')
                    require(index > 0) { "invalid source hash entry" }
                    hashes[item.substring(0, index)] = item.substring(index + 1)
                }
            return GuestArtifactMetadata(
                sourcePackage = props.getProperty("sourcePackage") ?: error("missing sourcePackage"),
                versionCode = props.getProperty("versionCode")?.toLongOrNull() ?: error("missing versionCode"),
                versionName = props.getProperty("versionName").orEmpty(),
                sourceSignerDigests = props.getProperty("sourceSignerDigests").orEmpty().split(',').filter(String::isNotEmpty),
                sourceApkSha256 = LinkedHashMap(hashes),
                launcherClass = props.getProperty("launcherClass") ?: error("missing launcherClass"),
                applicationClass = props.getProperty("applicationClass")?.takeIf(String::isNotEmpty),
                transformSchemaVersion = props.getProperty("transformSchemaVersion")?.toIntOrNull()
                    ?: error("missing transformSchemaVersion"),
            )
        }
    }
}

object PluginUpdatePolicy {
    fun sameSigner(current: List<String>, incoming: List<String>): Boolean =
        current.isNotEmpty() && current.sorted() == incoming.sorted()
}
