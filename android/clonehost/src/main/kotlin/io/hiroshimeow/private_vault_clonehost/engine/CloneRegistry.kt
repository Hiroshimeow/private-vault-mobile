package io.hiroshimeow.private_vault_clonehost.engine

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class CloneRecord(
    val instanceId: String,
    val packageName: String,
    val label: String,
    val launcherActivity: String,
    val applicationClass: String?,
    val providerClasses: List<String>,
    val imageFiles: List<String>,
    val state: String = "ready",
)

data class RegistryResult(
    val ok: Boolean,
    val record: CloneRecord? = null,
    val errorCode: String? = null,
)

class CloneRegistry internal constructor(
    private val prefs: SharedPreferences,
    private val imageRoot: File,
    private val sourceResolver: (String) -> SourceResult,
    private val slot: Int,
) {
    constructor(context: Context) : this(
        prefs = context.getSharedPreferences("clone_registry", Context.MODE_PRIVATE),
        imageRoot = File(context.filesDir, "guest/package"),
        sourceResolver = InstalledApkSource(context)::resolve,
        slot = io.hiroshimeow.private_vault_clonehost.BuildConfig.CLONE_SLOT,
    )

    fun current(): CloneRecord? = prefs.getString(KEY_RECORD, null)?.let(::decode)

    fun registerInstalled(packageName: String): RegistryResult {
        if (current() != null) return RegistryResult(false, errorCode = "slot_occupied")
        val source = when (val resolved = sourceResolver(packageName)) {
            is SourceResult.Failure -> return RegistryResult(false, errorCode = resolved.reason.code)
            is SourceResult.Success -> resolved.source
        }
        val destination = File(imageRoot, "current")
        val staged = GuestPackageImage.stage(source.packageName, source.baseApk, source.splitApks, destination)
        val image = when (staged) {
            is PackageImageResult.Success -> staged.image
            is PackageImageResult.Failure -> return RegistryResult(false, errorCode = staged.reason.toCode())
        }
        val record = CloneRecord(
            instanceId = "slot$slot:${source.packageName}",
            packageName = source.packageName,
            label = source.label,
            launcherActivity = source.launcherActivity,
            applicationClass = source.applicationClass,
            providerClasses = source.providerClasses,
            imageFiles = image.files.map { it.file.name },
        )
        if (!prefs.edit().putString(KEY_RECORD, encode(record)).commit()) {
            destination.deleteRecursively()
            return RegistryResult(false, errorCode = "operation_failed")
        }
        return RegistryResult(true, record)
    }

    fun imageFiles(record: CloneRecord): List<File> = record.imageFiles.map { File(File(imageRoot, "current"), it) }

    fun remove(instanceId: String): RegistryResult {
        val current = current() ?: return RegistryResult(false, errorCode = "instance_not_found")
        if (current.instanceId != instanceId) return RegistryResult(false, errorCode = "instance_not_found")
        val destination = File(imageRoot, "current")
        if (!prefs.edit().remove(KEY_RECORD).commit()) {
            return RegistryResult(false, errorCode = "operation_failed")
        }
        destination.deleteRecursively()
        return RegistryResult(true)
    }

    private fun encode(record: CloneRecord): String = JSONObject().apply {
        put("instanceId", record.instanceId)
        put("packageName", record.packageName)
        put("label", record.label)
        put("launcherActivity", record.launcherActivity)
        put("applicationClass", record.applicationClass)
        put("providerClasses", JSONArray(record.providerClasses))
        put("imageFiles", JSONArray(record.imageFiles))
        put("state", record.state)
    }.toString()

    private fun decode(raw: String): CloneRecord? = runCatching {
        val json = JSONObject(raw)
        CloneRecord(
            instanceId = json.getString("instanceId"),
            packageName = json.getString("packageName"),
            label = json.getString("label"),
            launcherActivity = json.getString("launcherActivity"),
            applicationClass = json.optString("applicationClass").takeIf { it.isNotBlank() && it != "null" },
            providerClasses = json.getJSONArray("providerClasses").strings(),
            imageFiles = json.getJSONArray("imageFiles").strings(),
            state = json.optString("state", "ready"),
        )
    }.getOrNull()

    private fun JSONArray.strings(): List<String> = (0 until length()).map { getString(it) }

    private fun PackageImageFailure.toCode(): String = when (this) {
        PackageImageFailure.INVALID_PACKAGE, PackageImageFailure.PACKAGE_UNREADABLE -> "package_unreadable"
        PackageImageFailure.MISSING_SPLIT -> "missing_split"
        PackageImageFailure.PACKAGE_CHANGED_DURING_COPY -> "package_changed_during_copy"
        PackageImageFailure.COMMIT_FAILED -> "operation_failed"
    }

    private companion object {
        const val KEY_RECORD = "record"
    }
}
