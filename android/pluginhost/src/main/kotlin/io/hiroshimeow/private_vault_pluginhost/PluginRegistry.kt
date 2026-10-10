package io.hiroshimeow.private_vault_pluginhost

import android.content.Context
import android.os.Build
import java.io.File
import java.io.FileOutputStream

class PluginRegistry(private val context: Context) {
    private val root = File(context.filesDir, "plugin")
    private val current = File(root, "current")

    fun status(): Map<String, Any?> {
        val metadataFile = File(current, "metadata.properties")
        if (!metadataFile.isFile) return mapOf("state" to PluginResult.READY.wire, "occupied" to false)
        return runCatching { GuestArtifactMetadata.readFrom(metadataFile) }
            .fold(
                onSuccess = { metadata -> mapOf("state" to PluginResult.READY.wire, "occupied" to true, "packageName" to metadata.sourcePackage) },
                onFailure = { mapOf("state" to PluginResult.OPERATION_FAILED.wire, "message" to (it.message ?: "invalid artifact")) },
            )
    }

    fun register(packageName: String): Map<String, Any?> {
        val staging = File(root, "staging-${System.nanoTime()}")
        try {
            root.mkdirs()
            val image = try {
                ApkSource(context).resolve(packageName)
            } catch (error: PluginTypedException) {
                return errorMap(error)
            } catch (error: Exception) {
                return result(PluginResult.PACKAGE_UNREADABLE, error.message)
            }

            val currentMetadata = File(current, "metadata.properties").takeIf(File::isFile)
                ?.let { runCatching { GuestArtifactMetadata.readFrom(it) }.getOrNull() }
            if (currentMetadata != null && currentMetadata.sourcePackage == image.packageInfo.packageName &&
                !PluginUpdatePolicy.sameSigner(currentMetadata.sourceSignerDigests, image.signerDigests)
            ) {
                return result(PluginResult.SOURCE_SIGNER_CHANGED, "source signer changed")
            }

            val sourceDir = File(staging, "source")
            val copied = ApkSource(context).copyInto(image, sourceDir)
            val transformed = File(staging, "plugin.dex.zip")
            try {
                GuestTransformer().transform(copied, transformed)
            } catch (error: PluginTypedException) {
                return errorMap(error)
            } catch (error: Exception) {
                return result(PluginResult.TRANSFORM_FAILED, error.message)
            }

            val metadata = GuestArtifactMetadata(
                sourcePackage = image.packageInfo.packageName,
                versionCode = if (Build.VERSION.SDK_INT >= 28) image.packageInfo.longVersionCode else @Suppress("DEPRECATION") image.packageInfo.versionCode.toLong(),
                versionName = image.packageInfo.versionName.orEmpty(),
                sourceSignerDigests = image.signerDigests,
                sourceApkSha256 = image.apkSha256,
                launcherClass = image.launcherClass,
                applicationClass = image.applicationClass,
                transformSchemaVersion = TRANSFORM_SCHEMA_VERSION,
            )
            metadata.writeTo(File(staging, "metadata.properties"))
            fsyncTree(staging)
            markReadOnly(transformed)
            copied.forEach(::markReadOnly)
            val backup = File(root, "previous")
            backup.deleteRecursively()
            if (current.exists() && !current.renameTo(backup)) return result(PluginResult.OPERATION_FAILED, "cannot stage previous artifact")
            if (!staging.renameTo(current)) {
                current.deleteRecursively()
                backup.renameTo(current)
                return result(PluginResult.OPERATION_FAILED, "cannot publish transformed artifact")
            }
            backup.deleteRecursively()
            return mapOf("state" to PluginResult.READY.wire, "ok" to true, "packageName" to metadata.sourcePackage)
        } finally {
            if (staging.exists()) staging.deleteRecursively()
        }
    }

    fun remove(): Map<String, Any?> = if (!current.exists() || current.deleteRecursively()) {
        mapOf("state" to PluginResult.READY.wire, "ok" to true)
    } else {
        result(PluginResult.OPERATION_FAILED, "could not remove plugin artifact")
    }

    fun currentArtifact(): Pair<File, GuestArtifactMetadata>? {
        val metadataFile = File(current, "metadata.properties")
        val dex = File(current, "plugin.dex.zip")
        if (!metadataFile.isFile || !dex.isFile) return null
        val metadata = GuestArtifactMetadata.readFrom(metadataFile)
        for ((name, expectedHash) in metadata.sourceApkSha256) {
            val source = File(File(current, "source"), name)
            if (!source.isFile || ApkSource.sha256(source) != expectedHash) {
                throw PluginTypedException(PluginResult.TRANSFORM_FAILED, "stored source integrity mismatch")
            }
        }
        return dex to metadata
    }

    private fun errorMap(error: PluginTypedException): Map<String, Any?> = result(error.result, error.message)
    private fun result(state: PluginResult, message: String?): Map<String, Any?> =
        mapOf("state" to state.wire, "ok" to false, "message" to (message ?: state.wire))

    private fun markReadOnly(file: File) {
        if (!file.setReadOnly()) throw PluginTypedException(PluginResult.TRANSFORM_FAILED, "artifact could not be made read-only")
    }

    private fun fsyncTree(dir: File) {
        dir.walkTopDown().filter(File::isFile).forEach { file ->
            FileOutputStream(file, true).use { it.fd.sync() }
        }
    }
}
