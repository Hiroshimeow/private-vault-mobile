package io.hiroshimeow.private_vault_clonehost.engine

import java.io.File
import java.security.MessageDigest
import java.util.UUID

data class PackageImageFile(val file: File, val sha256: String)
data class PackageImage(val packageName: String, val files: List<PackageImageFile>)

enum class PackageImageFailure {
    INVALID_PACKAGE,
    PACKAGE_UNREADABLE,
    MISSING_SPLIT,
    PACKAGE_CHANGED_DURING_COPY,
    COMMIT_FAILED,
}

sealed interface PackageImageResult {
    data class Success(val image: PackageImage) : PackageImageResult
    data class Failure(val reason: PackageImageFailure) : PackageImageResult
}

object GuestPackageImage {
    private val packagePattern = Regex("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+$")

    fun isValidPackageName(packageName: String): Boolean = packagePattern.matches(packageName)

    fun stage(
        packageName: String,
        baseApk: File,
        splitApks: List<File>,
        destination: File,
    ): PackageImageResult {
        if (!isValidPackageName(packageName)) return PackageImageResult.Failure(PackageImageFailure.INVALID_PACKAGE)
        if (!baseApk.isFile || !baseApk.canRead()) return PackageImageResult.Failure(PackageImageFailure.PACKAGE_UNREADABLE)
        if (splitApks.any { !it.isFile || !it.canRead() }) return PackageImageResult.Failure(PackageImageFailure.MISSING_SPLIT)

        val ordered = splitApks.sortedBy { it.name }
        val sources = listOf(baseApk) + ordered
        val snapshots = sources.associateWith { it.length() to it.lastModified() }
        val parent = destination.parentFile ?: return PackageImageResult.Failure(PackageImageFailure.COMMIT_FAILED)
        parent.mkdirs()
        val staging = File(parent, ".${destination.name}.staging-${UUID.randomUUID()}")
        val backup = File(parent, ".${destination.name}.backup-${UUID.randomUUID()}")
        staging.mkdirs()

        return try {
            val copied = mutableListOf<PackageImageFile>()
            sources.forEachIndexed { index, source ->
                val name = if (index == 0) "base.apk" else "split-${(index - 1).toString().padStart(3, '0')}-${source.name}"
                val target = File(staging, name)
                source.inputStream().use { input -> target.outputStream().use(input::copyTo) }
                if (snapshots[source] != (source.length() to source.lastModified())) {
                    staging.deleteRecursively()
                    return PackageImageResult.Failure(PackageImageFailure.PACKAGE_CHANGED_DURING_COPY)
                }
                copied += PackageImageFile(target, sha256(target))
            }

            var backedUp = false
            if (destination.exists()) {
                backedUp = destination.renameTo(backup)
                if (!backedUp) {
                    staging.deleteRecursively()
                    return PackageImageResult.Failure(PackageImageFailure.COMMIT_FAILED)
                }
            }
            if (!staging.renameTo(destination)) {
                if (backedUp) backup.renameTo(destination)
                staging.deleteRecursively()
                return PackageImageResult.Failure(PackageImageFailure.COMMIT_FAILED)
            }
            backup.deleteRecursively()
            val finalFiles = copied.map { PackageImageFile(File(destination, it.file.name), it.sha256) }
            PackageImageResult.Success(PackageImage(packageName, finalFiles))
        } catch (_: Exception) {
            staging.deleteRecursively()
            PackageImageResult.Failure(PackageImageFailure.PACKAGE_UNREADABLE)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
