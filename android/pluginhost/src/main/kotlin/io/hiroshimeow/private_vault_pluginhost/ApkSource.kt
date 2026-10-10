package io.hiroshimeow.private_vault_pluginhost

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile

data class SourceApkImage(
    val packageInfo: PackageInfo,
    val launcherClass: String,
    val applicationClass: String?,
    val apkFiles: List<File>,
    val signerDigests: List<String>,
    val apkSha256: LinkedHashMap<String, String>,
)

class ApkSource(private val context: Context) {
    fun resolve(packageName: String): SourceApkImage {
        require(packageName.matches(Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+"))) { "invalid package" }
        val pm = context.packageManager
        val flags = PackageManager.GET_ACTIVITIES or PackageManager.GET_PROVIDERS or
            PackageManager.GET_SERVICES or PackageManager.GET_RECEIVERS or PackageManager.GET_SIGNING_CERTIFICATES
        val info = pm.getPackageInfo(packageName, flags)
        val appInfo = info.applicationInfo ?: error("package has no application info")
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(packageName)
        val launcher = pm.queryIntentActivities(launcherIntent, 0).firstOrNull()?.activityInfo?.name
            ?: error("package has no launcher activity")

        val processes = buildList {
            add(appInfo.processName ?: packageName)
            info.activities.orEmpty().mapNotNullTo(this) { it.processName }
            info.providers.orEmpty().mapNotNullTo(this) { it.processName }
            info.services.orEmpty().mapNotNullTo(this) { it.processName }
            info.receivers.orEmpty().mapNotNullTo(this) { it.processName }
        }.distinct()
        if (processes.size > 1) throw PluginTypedException(PluginResult.UNSUPPORTED_MULTIPROCESS)
        if (!info.providers.isNullOrEmpty()) throw PluginTypedException(PluginResult.UNSUPPORTED_PROVIDER)
        if (!info.services.isNullOrEmpty()) throw PluginTypedException(PluginResult.UNSUPPORTED_SERVICE)
        if (!info.receivers.isNullOrEmpty()) throw PluginTypedException(PluginResult.UNSUPPORTED_RECEIVER)

        val paths = buildList {
            add(appInfo.sourceDir)
            appInfo.splitSourceDirs?.sorted()?.let(::addAll)
        }
        val apks = paths.map { File(it) }
        if (apks.any { !it.isFile }) throw PluginTypedException(PluginResult.MISSING_SPLIT)
        val nativeAbis = apks.flatMap(::nativeAbis).toSet()
        if (nativeAbis.isNotEmpty()) {
            if (Build.SUPPORTED_ABIS.none(nativeAbis::contains)) {
                throw PluginTypedException(PluginResult.UNSUPPORTED_ABI)
            }
            throw PluginTypedException(
                PluginResult.UNSUPPORTED_NATIVE_PATH_BEHAVIOR,
                "native libraries are fail-closed in the v1 plugin runtime",
            )
        }
        val named = linkedMapOf<String, String>()
        apks.forEachIndexed { index, file ->
            named[if (index == 0) "base.apk" else "split-${index}.apk"] = sha256(file)
        }
        return SourceApkImage(
            packageInfo = info,
            launcherClass = normalizeClassName(packageName, launcher),
            applicationClass = appInfo.className?.let { normalizeClassName(packageName, it) },
            apkFiles = apks,
            signerDigests = signerDigests(info),
            apkSha256 = named,
        )
    }

    fun copyInto(image: SourceApkImage, target: File): List<File> {
        target.mkdirs()
        return image.apkFiles.mapIndexed { index, source ->
            val dest = File(target, if (index == 0) "base.apk" else "split-${index}.apk")
            source.inputStream().use { input -> dest.outputStream().use(input::copyTo) }
            dest
        }
    }

    companion object {
        fun hasDex(apk: File): Boolean = ZipFile(apk).use { zip ->
            zip.entries().asSequence().any { it.name.matches(Regex("classes(\\d*)\\.dex")) }
        }

        private fun nativeAbis(apk: File): List<String> = ZipFile(apk).use { zip ->
            zip.entries().asSequence()
                .map { it.name }
                .filter { it.startsWith("lib/") && it.endsWith(".so") }
                .mapNotNull { it.split('/').getOrNull(1) }
                .distinct()
                .toList()
        }

        private fun normalizeClassName(pkg: String, value: String): String = when {
            value.startsWith('.') -> pkg + value
            '.' !in value -> "$pkg.$value"
            else -> value
        }

        private fun signerDigests(info: PackageInfo): List<String> {
            val signatures = if (Build.VERSION.SDK_INT >= 28) {
                info.signingInfo?.apkContentsSigners?.toList().orEmpty()
            } else {
                @Suppress("DEPRECATION") info.signatures?.toList().orEmpty()
            }
            return signatures.map { signature ->
                MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
            }.sorted()
        }

        internal fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().buffered().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}

class PluginTypedException(val result: PluginResult, message: String = result.wire) : Exception(message)
