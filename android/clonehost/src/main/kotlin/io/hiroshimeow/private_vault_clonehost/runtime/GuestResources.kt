package io.hiroshimeow.private_vault_clonehost.runtime

import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ApplicationInfo
import android.content.res.AssetManager
import android.content.res.Resources
import java.io.File

internal data class GuestEnvironment(
    val context: Context,
    val applicationInfo: ApplicationInfo,
    val resources: Resources,
)

internal object GuestResources {
    fun create(
        host: Context,
        packageName: String,
        apkFiles: List<File>,
        classLoader: ClassLoader,
        nativeDir: File,
    ): Result<GuestEnvironment> = runCatching {
        require(apkFiles.isNotEmpty())
        val base = apkFiles.first()
        val splitPaths = apkFiles.drop(1).map(File::getAbsolutePath).toTypedArray()
        val appInfo = ApplicationInfo().apply {
            this.packageName = packageName
            sourceDir = base.absolutePath
            publicSourceDir = base.absolutePath
            splitSourceDirs = splitPaths.takeIf { it.isNotEmpty() }
            splitPublicSourceDirs = splitPaths.takeIf { it.isNotEmpty() }
            dataDir = host.applicationInfo.dataDir
            nativeLibraryDir = nativeDir.absolutePath
        }
        val resources = host.packageManager.getResourcesForApplication(appInfo)
        val guestContext = object : ContextWrapper(host) {
            override fun getClassLoader(): ClassLoader = classLoader
            override fun getResources(): Resources = resources
            override fun getAssets(): AssetManager = resources.assets
            override fun getApplicationInfo(): ApplicationInfo = appInfo
            override fun getPackageName(): String = packageName
            override fun getPackageCodePath(): String = base.absolutePath
            override fun getPackageResourcePath(): String = base.absolutePath
        }
        GuestEnvironment(guestContext, appInfo, resources)
    }
}
