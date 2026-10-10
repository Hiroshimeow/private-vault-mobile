package io.hiroshimeow.private_vault_clonehost.engine

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.util.zip.ZipFile

data class GuestPackageImageSource(
    val packageName: String,
    val label: String,
    val versionName: String?,
    val launcherActivity: String,
    val applicationClass: String?,
    val providerClasses: List<String>,
    val baseApk: File,
    val splitApks: List<File>,
)

enum class SourceFailure(val code: String) {
    PACKAGE_UNREADABLE("package_unreadable"),
    NO_LAUNCHER_ACTIVITY("no_launcher_activity"),
    UNSUPPORTED_MULTIPROCESS("unsupported_multiprocess"),
    UNSUPPORTED_SERVICE_COMPONENT("unsupported_service_component"),
    UNSUPPORTED_ABI("unsupported_abi"),
    MISSING_SPLIT("missing_split"),
}

sealed interface SourceResult {
    data class Success(val source: GuestPackageImageSource) : SourceResult
    data class Failure(val reason: SourceFailure) : SourceResult
}

internal fun preflightPackageShape(
    packageName: String,
    processNames: List<String?>,
    hasServices: Boolean,
    baseApk: File,
    splitApks: List<File>,
    supportedAbis: Array<String>,
): SourceFailure? {
    if (!baseApk.isFile || !baseApk.canRead()) return SourceFailure.PACKAGE_UNREADABLE
    if (splitApks.any { !it.isFile || !it.canRead() }) return SourceFailure.MISSING_SPLIT
    if (processNames.any { !it.isNullOrBlank() && it != packageName }) return SourceFailure.UNSUPPORTED_MULTIPROCESS
    if (hasServices) return SourceFailure.UNSUPPORTED_SERVICE_COMPONENT

    val packagedAbis = buildSet {
        (listOf(baseApk) + splitApks).forEach { apk ->
            runCatching {
                ZipFile(apk).use { zip ->
                    zip.entries().asSequence()
                        .map { it.name }
                        .filter { it.startsWith("lib/") && it.endsWith(".so") }
                        .mapNotNull { it.split('/').getOrNull(1) }
                        .forEach(::add)
                }
            }
        }
    }
    if (packagedAbis.isNotEmpty() && supportedAbis.none(packagedAbis::contains)) return SourceFailure.UNSUPPORTED_ABI
    return null
}

class InstalledApkSource(private val context: Context) {
    fun resolve(packageName: String): SourceResult {
        if (!GuestPackageImage.isValidPackageName(packageName)) return SourceResult.Failure(SourceFailure.PACKAGE_UNREADABLE)
        val pm = context.packageManager
        val flags = PackageManager.GET_ACTIVITIES or PackageManager.GET_SERVICES or PackageManager.GET_PROVIDERS or PackageManager.GET_META_DATA
        val info = try {
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT >= 33) pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(flags.toLong()))
            else pm.getPackageInfo(packageName, flags)
        } catch (_: Exception) {
            return SourceResult.Failure(SourceFailure.PACKAGE_UNREADABLE)
        }
        val appInfo = info.applicationInfo ?: return SourceResult.Failure(SourceFailure.PACKAGE_UNREADABLE)
        val base = File(appInfo.sourceDir ?: return SourceResult.Failure(SourceFailure.PACKAGE_UNREADABLE))
        val splits = appInfo.splitSourceDirs.orEmpty().map(::File).sortedBy { it.name }
        val processes = buildList {
            info.activities.orEmpty().mapTo(this) { it.processName }
            info.services.orEmpty().mapTo(this) { it.processName }
            info.providers.orEmpty().mapTo(this) { it.processName }
        }
        preflightPackageShape(packageName, processes, !info.services.isNullOrEmpty(), base, splits, Build.SUPPORTED_ABIS)?.let {
            return SourceResult.Failure(it)
        }

        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(packageName)
        val launcher = pm.queryIntentActivities(launcherIntent, 0).firstOrNull()?.activityInfo?.name
            ?: return SourceResult.Failure(SourceFailure.NO_LAUNCHER_ACTIVITY)
        return SourceResult.Success(
            GuestPackageImageSource(
                packageName = packageName,
                label = appInfo.loadLabel(pm).toString(),
                versionName = info.versionName,
                launcherActivity = launcher,
                applicationClass = appInfo.className,
                providerClasses = info.providers.orEmpty().mapNotNull { it.name },
                baseApk = base,
                splitApks = splits,
            ),
        )
    }
}
