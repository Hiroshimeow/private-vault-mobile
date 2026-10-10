package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class StandaloneCloneBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val engine = StandaloneCloneEngine()
    private val signingStore = StandaloneCloneSigningStore()
    private val store = StandaloneCloneStore(activity.applicationContext)
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "standalone-clone-lab").apply { isDaemon = true }
    }
    private val disposed = AtomicBoolean(false)
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingUninstall: PendingUninstall? = null

    private data class PendingUninstall(
        val record: StandaloneCloneRecord,
        val result: MethodChannel.Result,
    )

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            result.error("bridge_disposed", "Standalone clone bridge is unavailable", null)
            return
        }
        when (call.method) {
            "getEnvironment" -> result.success(environmentMap())
            "pickAndBuildClone" -> beginPickAndBuild(result)
            "listClones" -> runAsync(result) { reconcileAndList().map(StandaloneCloneRecord::toMap) }
            "installClone" -> {
                val cloneId = call.argument<String>("cloneId")
                if (cloneId == null) {
                    result.error("invalid_clone_id", "Missing cloneId", null)
                } else {
                    installClone(cloneId, result)
                }
            }
            "launchClone" -> {
                val cloneId = call.argument<String>("cloneId")
                if (cloneId == null) {
                    result.error("invalid_clone_id", "Missing cloneId", null)
                } else {
                    launchClone(cloneId, result)
                }
            }
            "removeClone" -> {
                val cloneId = call.argument<String>("cloneId")
                if (cloneId == null) {
                    result.error("invalid_clone_id", "Missing cloneId", null)
                } else {
                    removeClone(cloneId, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_UNINSTALL_CLONE) {
            val pending = pendingUninstall ?: return true
            pendingUninstall = null
            val current = runCatching { store.getOwnedRecord(pending.record.cloneId) }.getOrElse { error ->
                pending.result.error("clone_registry_invalid", error.message, null)
                return true
            }
            if (current == null || !pending.record.matchesOwnershipIdentity(current)) {
                pending.result.error(
                    "clone_registry_changed",
                    "Clone registry identity changed while uninstall confirmation was open",
                    null,
                )
                return true
            }
            if (resultCode == Activity.RESULT_OK) {
                val removed = runCatching {
                    store.removeRecordAndArtifact(pending.record.cloneId)
                }.getOrElse { error ->
                    pending.result.error("clone_cleanup_failed", error.message, null)
                    return true
                }
                if (!removed) {
                    pending.result.error(
                        "clone_cleanup_failed",
                        "Clone registry entry disappeared before confirmed uninstall cleanup",
                        null,
                    )
                    return true
                }
                pending.result.success(mapOf("status" to "removed"))
                return true
            }

            runCatching {
                store.updateInstallStatus(pending.record.cloneId, pending.record.installStatus)
            }.getOrElse { error ->
                pending.result.error("clone_registry_invalid", error.message, null)
                return true
            }
            val status = if (resultCode == Activity.RESULT_CANCELED) {
                "uninstall_cancelled"
            } else {
                "uninstall_failed"
            }
            pending.result.success(mapOf("status" to status))
            return true
        }

        if (requestCode != REQUEST_PICK_APK) return false
        val result = pendingPickerResult ?: return true
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(mapOf("status" to "cancelled"))
            return true
        }
        val sourceUri = data.data!!
        val displayName = queryDisplayName(sourceUri)
        executor.execute {
            val response = buildCloneFromUri(sourceUri, displayName)
            completeOnMain(result) { result.success(response) }
        }
        return true
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        pendingPickerResult?.error("bridge_disposed", "Standalone clone bridge closed", null)
        pendingPickerResult = null
        pendingUninstall?.result?.error(
            "bridge_disposed",
            "Standalone clone bridge closed before uninstall result was confirmed",
            null,
        )
        pendingUninstall = null
        executor.shutdown()
    }

    private fun beginPickAndBuild(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("picker_busy", "An APK selection is already in progress", null)
            return
        }
        pendingPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = StandaloneCloneArtifactProvider.APK_MIME
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(StandaloneCloneArtifactProvider.APK_MIME, "application/zip"))
        }
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_APK)
        } catch (error: Exception) {
            pendingPickerResult = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    private fun buildCloneFromUri(uri: Uri, displayName: String): Map<String, Any?> {
        val workDir = store.newWorkDir()
        try {
            val source = File(workDir, "source.apk")
            activity.contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Unable to open selected APK" }
                source.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= MAX_SOURCE_BYTES) { "Selected APK exceeds clone-lab size limit" }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val inspection = engine.inspect(source, displayName)
            if (!inspection.supported) {
                return inspectionMap(inspection, "unsupported")
            }
            val priorRecord = inspection.cloneId?.let(store::getOwnedRecord)
            val incomingVersion = inspection.versionCode
            if (priorRecord?.versionCode != null && incomingVersion != null &&
                priorRecord.versionCode > incomingVersion
            ) {
                return inspectionMap(
                    inspection.copy(
                        compatibility = StandaloneCloneCompatibility(
                            blockers = listOf("clone_downgrade_unsupported"),
                        ),
                    ),
                    "unsupported",
                )
            }

            val unsigned = File(workDir, "unsigned.apk")
            val signed = File(workDir, "signed.apk")
            engine.transform(source, inspection, unsigned)
            val signing = signingStore.signAndVerify(
                unsignedApk = unsigned,
                signedApk = signed,
                alias = requireNotNull(inspection.signingAlias),
            )
            val record = store.retainSignedArtifact(inspection, signing, signed)
            return inspectionMap(inspection, "artifact_ready") + mapOf(
                "clone" to record.toMap(),
                "verifiedSigningSchemes" to signing.verifiedSchemes,
            )
        } catch (error: StandaloneCloneSignatureException) {
            return mapOf(
                "status" to "failed",
                "errorCode" to "clone_signature_invalid",
                "error" to (error.message ?: "Clone signature verification failed"),
            )
        } catch (error: Exception) {
            return mapOf(
                "status" to "failed",
                "error" to (error.message ?: error::class.java.simpleName),
            )
        } finally {
            store.cleanWorkDir(workDir)
        }
    }

    private fun installClone(cloneId: String, result: MethodChannel.Result) {
        val record = runCatching { store.getOwnedRecord(cloneId) }.getOrElse { error ->
            result.error("clone_registry_invalid", error.message, null)
            return
        }
        if (record == null) {
            result.error("clone_not_owned", "Clone is not owned by clone-lab registry", null)
            return
        }
        val artifact = runCatching { store.artifactFor(record) }.getOrElse { error ->
            result.error("artifact_missing", error.message, null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            val settings = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            )
            activity.startActivity(settings)
            result.success(mapOf("status" to "unknown_sources_required"))
            return
        }

        val artifactUri = Uri.Builder()
            .scheme("content")
            .authority("${activity.packageName}.clone_artifacts")
            .appendPath(record.cloneId)
            .appendPath(artifact.name)
            .build()
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(artifactUri, StandaloneCloneArtifactProvider.APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }
        try {
            activity.startActivity(intent)
            store.updateInstallStatus(cloneId, "install_requested")
            result.success(mapOf("status" to "install_requested"))
        } catch (error: Exception) {
            result.error("install_unavailable", error.message, null)
        }
    }

    private fun launchClone(cloneId: String, result: MethodChannel.Result) {
        val record = runCatching { store.getOwnedRecord(cloneId) }.getOrNull()
        if (record == null) {
            result.error("clone_not_owned", "Clone is not owned by clone-lab registry", null)
            return
        }
        if (!requireInstalledCloneOwnership(record, result)) return
        val launch = activity.packageManager.getLaunchIntentForPackage(record.clonePackage)
        if (launch == null) {
            result.error("clone_not_launchable", "Installed clone has no visible launcher activity", null)
            return
        }
        try {
            activity.startActivity(launch)
            store.updateInstallStatus(cloneId, "installed")
            result.success(mapOf("status" to "launched"))
        } catch (error: Exception) {
            result.error("launch_failed", error.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun removeClone(cloneId: String, result: MethodChannel.Result) {
        if (pendingUninstall != null) {
            result.error("uninstall_busy", "Another clone uninstall confirmation is already open", null)
            return
        }
        val record = runCatching { store.getOwnedRecord(cloneId) }.getOrNull()
        if (record == null) {
            result.error("clone_not_owned", "Clone is not owned by clone-lab registry", null)
            return
        }
        if (!requireInstalledCloneOwnership(record, result)) return
        val intent = Intent(
            Intent.ACTION_UNINSTALL_PACKAGE,
            Uri.parse("package:${record.clonePackage}"),
        ).apply {
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        pendingUninstall = PendingUninstall(record, result)
        try {
            store.updateInstallStatus(cloneId, "uninstall_requested")
            activity.startActivityForResult(intent, REQUEST_UNINSTALL_CLONE)
        } catch (error: Exception) {
            pendingUninstall = null
            runCatching { store.updateInstallStatus(cloneId, record.installStatus) }
            result.error("uninstall_unavailable", error.message, null)
        }
    }

    private fun reconcileAndList(): List<StandaloneCloneRecord> {
        val records = store.listRecords()
        for (record in records) {
            when (installedCloneOwnership(record)) {
                InstalledCloneOwnership.OWNED -> {
                    if (record.installStatus == "install_requested") {
                        store.updateInstallStatus(record.cloneId, "installed")
                    }
                }
                InstalledCloneOwnership.FOREIGN_OR_AMBIGUOUS -> {
                    if (record.installStatus == "install_requested" ||
                        record.installStatus == "uninstall_requested"
                    ) {
                        store.updateInstallStatus(record.cloneId, "ownership_mismatch")
                    }
                }
                InstalledCloneOwnership.UNKNOWN -> Unit
            }
        }
        return store.listRecords()
    }

    private fun requireInstalledCloneOwnership(
        record: StandaloneCloneRecord,
        result: MethodChannel.Result,
    ): Boolean = when (installedCloneOwnership(record)) {
        InstalledCloneOwnership.OWNED -> true
        InstalledCloneOwnership.FOREIGN_OR_AMBIGUOUS -> {
            result.error(
                "clone_signer_mismatch",
                "Installed package at clone identity is not signed by the clone-lab signer",
                null,
            )
            false
        }
        InstalledCloneOwnership.UNKNOWN -> {
            result.error(
                "clone_ownership_unverified",
                "Installed clone ownership could not be verified",
                null,
            )
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun installedCloneOwnership(record: StandaloneCloneRecord): InstalledCloneOwnership {
        val packageInfo = try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                    activity.packageManager.getPackageInfo(
                        record.clonePackage,
                        PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
                    )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                    activity.packageManager.getPackageInfo(
                        record.clonePackage,
                        PackageManager.GET_SIGNING_CERTIFICATES,
                    )
                else -> activity.packageManager.getPackageInfo(
                    record.clonePackage,
                    PackageManager.GET_SIGNATURES,
                )
            }
        } catch (_: PackageManager.NameNotFoundException) {
            return InstalledCloneOwnership.UNKNOWN
        } catch (_: SecurityException) {
            return InstalledCloneOwnership.UNKNOWN
        }

        val signerSha256 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return InstalledCloneOwnership.UNKNOWN
            if (signingInfo.hasMultipleSigners()) return InstalledCloneOwnership.FOREIGN_OR_AMBIGUOUS
            signingInfo.apkContentsSigners?.map { signature -> sha256(signature.toByteArray()) }.orEmpty()
        } else {
            packageInfo.signatures?.map { signature -> sha256(signature.toByteArray()) }.orEmpty()
        }
        return if (StandaloneClonePolicy.matchesExpectedSingleSigner(
                record.cloneSignerSha256,
                signerSha256,
            )
        ) {
            InstalledCloneOwnership.OWNED
        } else {
            InstalledCloneOwnership.FOREIGN_OR_AMBIGUOUS
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private enum class InstalledCloneOwnership {
        OWNED,
        FOREIGN_OR_AMBIGUOUS,
        UNKNOWN,
    }

    private fun queryDisplayName(uri: Uri): String {
        activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return "selected.apk"
    }

    private fun inspectionMap(
        inspection: StandaloneCloneInspection,
        status: String,
    ): Map<String, Any?> = mapOf(
        "status" to status,
        "supported" to inspection.supported,
        "blockers" to inspection.compatibility.blockers,
        "warnings" to inspection.compatibility.warnings,
        "sourcePackage" to inspection.sourcePackage,
        "sourceSignerSha256" to inspection.sourceSignerSha256,
        "clonePackage" to inspection.clonePackage,
        "cloneId" to inspection.cloneId,
        "versionCode" to inspection.versionCode,
        "versionName" to inspection.versionName,
        "sourceSignatureSchemes" to inspection.sourceSignatureSchemes,
    )

    private fun environmentMap(): Map<String, Any?> = mapOf(
        "route" to "standalone_repackage",
        "sdkInt" to Build.VERSION.SDK_INT,
        "canRequestPackageInstalls" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        },
        "maxSourceBytes" to MAX_SOURCE_BYTES,
    )

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                completeOnMain(result) { result.success(value) }
            } catch (error: Exception) {
                completeOnMain(result) {
                    result.error("standalone_clone_failed", error.message, null)
                }
            }
        }
    }

    private fun completeOnMain(result: MethodChannel.Result, action: () -> Unit) {
        if (disposed.get()) return
        activity.runOnUiThread(action)
    }

    companion object {
        private const val CHANNEL_NAME = "private_vault/standalone_clone"
        private const val REQUEST_PICK_APK = 61840
        private const val REQUEST_UNINSTALL_CLONE = 61841
        private const val MAX_SOURCE_BYTES = 1024L * 1024L * 1024L
    }
}
