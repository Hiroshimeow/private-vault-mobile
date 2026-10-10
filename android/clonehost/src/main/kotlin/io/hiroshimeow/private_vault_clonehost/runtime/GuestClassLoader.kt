package io.hiroshimeow.private_vault_clonehost.runtime

import android.content.Context
import android.os.Build
import dalvik.system.DexClassLoader
import java.io.File
import java.util.zip.ZipFile

internal data class LoadedGuest(
    val classLoader: ClassLoader,
    val nativeDir: File,
)

internal object GuestClassLoader {
    fun create(context: Context, instanceId: String, apkFiles: List<File>): Result<LoadedGuest> = runCatching {
        require(apkFiles.isNotEmpty() && apkFiles.all(File::isFile))
        val safeId = instanceId.replace(Regex("[^A-Za-z0-9_.-]"), "_")
        val root = File(context.codeCacheDir, "guest/$safeId").apply { mkdirs() }
        val nativeDir = File(context.filesDir, "guest/native").apply { mkdirs() }
        extractNativeLibraries(apkFiles, nativeDir)
        val dexPath = apkFiles.joinToString(File.pathSeparator) { it.absolutePath }
        LoadedGuest(
            DexClassLoader(dexPath, root.absolutePath, nativeDir.absolutePath, context.classLoader),
            nativeDir,
        )
    }

    private fun extractNativeLibraries(apks: List<File>, output: File) {
        output.listFiles()?.forEach(File::delete)
        val abi = Build.SUPPORTED_ABIS.firstOrNull { candidate ->
            apks.any { apk ->
                runCatching { ZipFile(apk).use { zip -> zip.entries().asSequence().any { it.name.startsWith("lib/$candidate/") && it.name.endsWith(".so") } } }
                    .getOrDefault(false)
            }
        } ?: return
        apks.forEach { apk ->
            ZipFile(apk).use { zip ->
                zip.entries().asSequence()
                    .filter { !it.isDirectory && it.name.startsWith("lib/$abi/") && it.name.endsWith(".so") }
                    .forEach { entry ->
                        val out = File(output, entry.name.substringAfterLast('/'))
                        zip.getInputStream(entry).use { input -> out.outputStream().use(input::copyTo) }
                    }
            }
        }
    }
}
