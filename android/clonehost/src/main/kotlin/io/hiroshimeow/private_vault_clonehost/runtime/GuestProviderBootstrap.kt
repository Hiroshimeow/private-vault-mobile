package io.hiroshimeow.private_vault_clonehost.runtime

import android.content.ContentProvider
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

internal object GuestProviderBootstrap {
    fun create(
        context: Context,
        classLoader: ClassLoader,
        baseApk: File,
        splitApks: List<File>,
        packageName: String,
    ): Result<List<ContentProvider>> = runCatching {
        val flags = PackageManager.GET_PROVIDERS
        @Suppress("DEPRECATION")
        val info = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageArchiveInfo(baseApk.absolutePath, PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            context.packageManager.getPackageArchiveInfo(baseApk.absolutePath, flags)
        } ?: return@runCatching emptyList()
        info.applicationInfo?.apply {
            sourceDir = baseApk.absolutePath
            publicSourceDir = baseApk.absolutePath
            splitSourceDirs = splitApks.map(File::getAbsolutePath).toTypedArray().takeIf { it.isNotEmpty() }
            splitPublicSourceDirs = splitSourceDirs
        }
        info.providers.orEmpty().map { providerInfo ->
            require(providerInfo.processName.isNullOrBlank() || providerInfo.processName == packageName) { "unsupported_provider" }
            val providerClass = classLoader.loadClass(providerInfo.name)
            val provider = providerClass.getDeclaredConstructor().newInstance() as ContentProvider
            provider.attachInfo(context, providerInfo)
            provider
        }
    }
}
