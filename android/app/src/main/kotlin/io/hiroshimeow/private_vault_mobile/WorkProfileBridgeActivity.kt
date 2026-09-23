package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class WorkProfileBridgeActivity : Activity() {
    private lateinit var dpm: DevicePolicyManager
    private lateinit var admin: ComponentName
    private var pendingPackageName: String? = null
    private var resultPendingIntent: PendingIntent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dpm = getSystemService(DevicePolicyManager::class.java)
        admin = ComponentName(this, PrivateVaultDeviceAdminReceiver::class.java)
        resultPendingIntent = resultPendingIntentFrom(intent)

        if (!dpm.isProfileOwnerApp(packageName)) {
            finishFailure(
                NativeWorkProfileErrorCode.UNAUTHORIZED,
                "Private Vault is not the profile owner.",
            )
            return
        }
        if (!isAuthorizedIntent(intent)) {
            finishFailure(
                NativeWorkProfileErrorCode.UNAUTHORIZED,
                "Work-profile control authorization failed.",
            )
            return
        }

        when (intent.action) {
            WorkProfileProtocol.ACTION_INSTALL_STATUS -> {
                handleInstallerStatus(intent)
                return
            }
            WorkProfileProtocol.ACTION_UNINSTALL_STATUS -> {
                handleUninstallStatus(intent)
                return
            }
        }

        handleCommand(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        resultPendingIntent = resultPendingIntentFrom(intent) ?: resultPendingIntent
        if (!dpm.isProfileOwnerApp(packageName) || !isAuthorizedIntent(intent)) {
            finishFailure(
                NativeWorkProfileErrorCode.UNAUTHORIZED,
                "Work-profile control authorization failed.",
            )
            return
        }
        when (intent.action) {
            WorkProfileProtocol.ACTION_INSTALL_STATUS -> handleInstallerStatus(intent)
            WorkProfileProtocol.ACTION_UNINSTALL_STATUS -> handleUninstallStatus(intent)
            else -> handleCommand(intent)
        }
    }

    private fun handleCommand(intent: Intent) {
        when (intent.action) {
            WorkProfileProtocol.ACTION_LIST_WORK_APPS -> finishApps(visibleManagedApps())
            WorkProfileProtocol.ACTION_GET_APP_STATE -> {
                val packageName = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
                finishApp(packageName?.let(::packageState))
            }
            WorkProfileProtocol.ACTION_CLONE -> clone(intent)
            WorkProfileProtocol.ACTION_LAUNCH -> launch(intent)
            WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT -> pickWorkDocument()
            WorkProfileProtocol.ACTION_OPEN_STORE -> openStore(intent)
            WorkProfileProtocol.ACTION_SHARE_VAULT_FILE -> shareVaultFile(intent)
            WorkProfileProtocol.ACTION_SUSPEND -> suspend(intent)
            WorkProfileProtocol.ACTION_HIDE -> hide(intent)
            WorkProfileProtocol.ACTION_UNINSTALL -> uninstall(intent)
            WorkProfileProtocol.ACTION_DESTROY -> destroyProfile()
            else -> finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Unknown work-profile operation.",
            )
        }
    }

    private fun clone(intent: Intent) {
        val targetPackage = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
            ?: return finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Missing package name.",
            )
        if (intent.getBooleanExtra(WorkProfileProtocol.EXTRA_SYSTEM_APP, false)) {
            try {
                dpm.enableSystemApp(admin, targetPackage)
                if (isInstalled(targetPackage)) {
                    rememberManagedPackage(targetPackage)
                    finishSuccess()
                } else {
                    finishFailure(
                        NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                        "Android did not enable this system app in the work profile.",
                    )
                }
            } catch (error: Exception) {
                finishFailure(NativeWorkProfileErrorCode.POLICY_DENIED, error.message)
            }
            return
        }

        val clip = intent.clipData
        if (clip == null || clip.itemCount == 0) {
            finishFailure(
                NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                "No APK payload was supplied.",
            )
            return
        }

        val installer = packageManager.packageInstaller
        var sessionId: Int? = null
        try {
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                .apply {
                    setAppPackageName(targetPackage)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                    }
                }
            sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                for (index in 0 until clip.itemCount) {
                    val uri = clip.getItemAt(index).uri
                        ?: throw IllegalArgumentException("APK item has no URI")
                    val name = if (index == 0) "base.apk" else "split_${index}.apk"
                    val input = contentResolver.openInputStream(uri)
                        ?: throw IllegalArgumentException("Unable to open APK payload")
                    input.use {
                        session.openWrite(name, 0, -1).use { output ->
                            it.copyTo(output)
                            session.fsync(output)
                        }
                    }
                }
                pendingPackageName = targetPackage
                val statusIntent = Intent(this, WorkProfileBridgeActivity::class.java)
                    .setAction(WorkProfileProtocol.ACTION_INSTALL_STATUS)
                    .setData(Uri.parse("private-vault://install/$sessionId"))
                    .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, targetPackage)
                    .putExtra(
                        WorkProfileProtocol.EXTRA_CONTROL_TOKEN,
                        WorkProfileControlToken.read(this),
                    )
                    .putExtra(
                        WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                        resultPendingIntent,
                    )
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    sessionId,
                    statusIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                )
                session.commit(pendingIntent.intentSender)
            }
        } catch (error: Exception) {
            sessionId?.let {
                runCatching { installer.abandonSession(it) }
            }
            finishFailure(NativeWorkProfileErrorCode.INSTALLER_FAILURE, error.message)
        }
    }

    private fun handleInstallerStatus(statusIntent: Intent) {
        pendingPackageName =
            statusIntent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME) ?: pendingPackageName
        when (statusIntent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    statusIntent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    statusIntent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                }
                if (confirmation == null) {
                    finishFailure(
                        NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                        "Android requested confirmation without an intent.",
                    )
                } else {
                    startActivityForResult(confirmation, REQUEST_INSTALL_CONFIRMATION)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                val targetPackage = pendingPackageName
                if (targetPackage != null && isInstalled(targetPackage)) {
                    rememberManagedPackage(targetPackage)
                    finishSuccess()
                } else {
                    finishFailure(
                        NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                        "Android reported install success but the work-profile package is absent.",
                    )
                }
            }
            PackageInstaller.STATUS_FAILURE_BLOCKED -> finishFailure(
                WorkProfileNativePolicy.installerFailureCode(
                    PackageInstaller.STATUS_FAILURE_BLOCKED,
                ),
                "Android or OEM policy blocked direct APK installation. "
                    + "Install the app inside the work profile from Play/OEM store "
                    + "or use Browser fallback.",
            )
            PackageInstaller.STATUS_FAILURE_ABORTED -> finishFailure(
                WorkProfileNativePolicy.installerFailureCode(
                    PackageInstaller.STATUS_FAILURE_ABORTED,
                ),
                "Package installation was cancelled.",
            )
            PackageInstaller.STATUS_FAILURE_INVALID,
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE,
            -> finishFailure(
                WorkProfileNativePolicy.installerFailureCode(
                    statusIntent.getIntExtra(
                        PackageInstaller.EXTRA_STATUS,
                        PackageInstaller.STATUS_FAILURE,
                    ),
                ),
                statusIntent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "This APK set is not installable in the work profile.",
            )
            else -> finishFailure(
                NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                statusIntent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Package installation failed.",
            )
        }
    }

    private fun launch(intent: Intent) {
        val targetPackage = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
            ?: return finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Missing package name.",
            )

        Thread {
            try {
                val hidden =
                    runCatching { dpm.isApplicationHidden(admin, targetPackage) }
                        .getOrDefault(false)
                if (hidden && !dpm.setApplicationHidden(admin, targetPackage, false)) {
                    return@Thread postFailure(
                        NativeWorkProfileErrorCode.POLICY_DENIED,
                        "Android refused to unhide this work-profile app.",
                    )
                }

                val failedToUnsuspend =
                    dpm.setPackagesSuspended(admin, arrayOf(targetPackage), false)
                if (failedToUnsuspend.isNotEmpty()) {
                    return@Thread postFailure(
                        NativeWorkProfileErrorCode.POLICY_DENIED,
                        "Android refused to unfreeze this work-profile app.",
                    )
                }

                val startedAt = SystemClock.elapsedRealtime()
                var launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
                while (
                    launchIntent == null &&
                    WorkProfileNativePolicy.shouldContinuePolling(
                        SystemClock.elapsedRealtime() - startedAt,
                        WorkProfileNativePolicy.PACKAGE_STATE_TIMEOUT_MS,
                    )
                ) {
                    Thread.sleep(WorkProfileNativePolicy.PACKAGE_STATE_POLL_MS)
                    launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
                }

                if (launchIntent == null) {
                    val launcherQuery =
                        Intent(Intent.ACTION_MAIN)
                            .addCategory(Intent.CATEGORY_LAUNCHER)
                            .setPackage(targetPackage)
                    val resolved = packageManager.queryIntentActivities(launcherQuery, 0).firstOrNull()
                    if (resolved != null) {
                        launchIntent =
                            Intent(Intent.ACTION_MAIN)
                                .addCategory(Intent.CATEGORY_LAUNCHER)
                                .setComponent(
                                    ComponentName(
                                        targetPackage,
                                        resolved.activityInfo.name,
                                    ),
                                )
                    }
                }

                val finalLaunchIntent = launchIntent
                if (finalLaunchIntent == null) {
                    return@Thread postFailure(
                        NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                        "This work-profile app has no launchable activity.",
                    )
                }

                Handler(Looper.getMainLooper()).post {
                    try {
                        startActivity(finalLaunchIntent)
                        rememberManagedPackage(targetPackage)
                        finishSuccess()
                    } catch (error: Exception) {
                        finishFailure(
                            NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                            error.message,
                        )
                    }
                }
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                postFailure(
                    NativeWorkProfileErrorCode.BRIDGE_TIMEOUT,
                    "Launching the work-profile app was interrupted.",
                )
            } catch (error: Exception) {
                postFailure(NativeWorkProfileErrorCode.POLICY_DENIED, error.message)
            }
        }.start()
    }

    private fun postFailure(code: NativeWorkProfileErrorCode, message: String?) {
        Handler(Looper.getMainLooper()).post {
            finishFailure(code, message)
        }
    }

    private fun pickWorkDocument() {
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(picker, REQUEST_PICK_WORK_DOCUMENT)
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.OEM_UNSUPPORTED, error.message)
        }
    }

    private fun openStore(intent: Intent) {
        val targetPackage =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
                ?: return finishFailure(
                    NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                    "Missing package name.",
                )
        val candidates =
            listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$targetPackage")),
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$targetPackage"),
                ),
            )
        val storeIntent =
            candidates.firstOrNull { packageManager.resolveActivity(it, 0) != null }
                ?: return finishFailure(
                    NativeWorkProfileErrorCode.STORE_FALLBACK_REQUIRED,
                    "No app store is available inside the Work Profile.",
                )
        try {
            startActivity(storeIntent)
            finishSuccess()
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.OEM_UNSUPPORTED, error.message)
        }
    }

    private fun shareVaultFile(intent: Intent) {
        val targetPackage =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
                ?: return finishFailure(
                    NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                    "Missing package name.",
                )
        val uri =
            intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
                ?: return finishFailure(
                    NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                    "No vault file was supplied.",
                )
        val mimeType =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_MIME_TYPE)
                ?.takeIf { it.isNotBlank() }
                ?: "application/octet-stream"
        val displayName =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_DISPLAY_NAME)
                ?.takeIf { it.isNotBlank() }
                ?: "vault-item"

        try {
            val hidden =
                runCatching { dpm.isApplicationHidden(admin, targetPackage) }
                    .getOrDefault(false)
            if (hidden && !dpm.setApplicationHidden(admin, targetPackage, false)) {
                finishFailure(
                    NativeWorkProfileErrorCode.POLICY_DENIED,
                    "Android refused to unhide this work-profile app.",
                )
                return
            }

            val failedToUnsuspend =
                dpm.setPackagesSuspended(admin, arrayOf(targetPackage), false)
            if (failedToUnsuspend.isNotEmpty()) {
                finishFailure(
                    NativeWorkProfileErrorCode.POLICY_DENIED,
                    "Android refused to unfreeze this work-profile app.",
                )
                return
            }

            val clip = ClipData.newRawUri(displayName, uri)
            val shareIntent =
                Intent(Intent.ACTION_SEND)
                    .setPackage(targetPackage)
                    .setType(mimeType)
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .apply {
                        clipData = clip
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
            val viewIntent =
                Intent(Intent.ACTION_VIEW)
                    .setPackage(targetPackage)
                    .setDataAndType(uri, mimeType)
                    .apply {
                        clipData = clip
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

            val targetIntent =
                when {
                    packageManager.queryIntentActivities(shareIntent, 0).isNotEmpty() -> shareIntent
                    packageManager.queryIntentActivities(viewIntent, 0).isNotEmpty() -> viewIntent
                    else -> null
                }
                    ?: return finishFailure(
                        NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                        "This isolated app cannot receive the selected vault file.",
                    )

            startActivity(targetIntent)
            rememberManagedPackage(targetPackage)
            finishSuccess()
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.OEM_UNSUPPORTED, error.message)
        }
    }

    private fun suspend(intent: Intent) {
        val targetPackage = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
            ?: return finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Missing package name.",
            )
        return try {
            val failed = dpm.setPackagesSuspended(
                admin,
                arrayOf(targetPackage),
                intent.getBooleanExtra(WorkProfileProtocol.EXTRA_BOOL_VALUE, false),
            )
            if (failed.isEmpty()) finishSuccess()
            else finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Android refused to change suspension state.",
            )
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.POLICY_DENIED, error.message)
        }
    }

    private fun hide(intent: Intent) {
        val targetPackage = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
            ?: return finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Missing package name.",
            )
        return try {
            if (dpm.setApplicationHidden(
                    admin,
                    targetPackage,
                    intent.getBooleanExtra(WorkProfileProtocol.EXTRA_BOOL_VALUE, false),
                )
            ) {
                rememberManagedPackage(targetPackage)
                finishSuccess()
            } else {
                finishFailure(
                    NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                    "Android refused to change hidden state.",
                )
            }
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.POLICY_DENIED, error.message)
        }
    }

    private fun uninstall(intent: Intent) {
        val targetPackage = intent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
            ?: return finishFailure(
                NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                "Missing package name.",
            )
        pendingPackageName = targetPackage
        val requestCode = targetPackage.hashCode() and Int.MAX_VALUE
        val statusIntent =
            Intent(this, WorkProfileBridgeActivity::class.java)
                .setAction(WorkProfileProtocol.ACTION_UNINSTALL_STATUS)
                .setData(Uri.parse("private-vault://uninstall/$targetPackage"))
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, targetPackage)
                .putExtra(
                    WorkProfileProtocol.EXTRA_CONTROL_TOKEN,
                    WorkProfileControlToken.read(this),
                )
                .putExtra(
                    WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                    resultPendingIntent,
                )
        val statusPendingIntent =
            PendingIntent.getActivity(
                this,
                requestCode,
                statusIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
        try {
            packageManager.packageInstaller.uninstall(
                targetPackage,
                statusPendingIntent.intentSender,
            )
        } catch (error: Exception) {
            finishFailure(NativeWorkProfileErrorCode.POLICY_DENIED, error.message)
        }
    }

    private fun handleUninstallStatus(statusIntent: Intent) {
        pendingPackageName =
            statusIntent.getStringExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME)
                ?: pendingPackageName
        when (
            statusIntent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
        ) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        statusIntent.getParcelableExtra(
                            Intent.EXTRA_INTENT,
                            Intent::class.java,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        statusIntent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                    }
                if (confirmation == null) {
                    finishFailure(
                        NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                        "Android requested uninstall confirmation without an intent.",
                    )
                } else {
                    startActivityForResult(
                        confirmation,
                        REQUEST_UNINSTALL_CONFIRMATION,
                    )
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                val targetPackage = pendingPackageName
                if (targetPackage != null && !isInstalled(targetPackage)) {
                    forgetManagedPackage(targetPackage)
                    finishSuccess()
                } else {
                    finishFailure(
                        NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                        "Android reported uninstall success but the work-profile package remains.",
                    )
                }
            }
            PackageInstaller.STATUS_FAILURE_ABORTED -> finishFailure(
                NativeWorkProfileErrorCode.USER_ACTION_REQUIRED,
                "Work-profile uninstall was cancelled.",
            )
            PackageInstaller.STATUS_FAILURE_BLOCKED -> finishFailure(
                NativeWorkProfileErrorCode.POLICY_DENIED,
                statusIntent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Android policy blocked work-profile uninstall.",
            )
            else -> finishFailure(
                NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                statusIntent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Work-profile uninstall failed.",
            )
        }
    }

    private fun destroyProfile() {
        sendResultAndFinish(RESULT_OK, successIntent())
        Handler(Looper.getMainLooper()).postDelayed({
            runCatching { dpm.wipeData(0) }
        }, 150)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        when (requestCode) {
            REQUEST_INSTALL_CONFIRMATION -> {
                // PackageInstaller's status callback is authoritative. Some
                // installer UIs return RESULT_CANCELED even when they continue
                // processing the session.
                return
            }
            REQUEST_UNINSTALL_CONFIRMATION -> {
                // PackageInstaller's status callback is authoritative.
                return
            }
            REQUEST_PICK_WORK_DOCUMENT -> {
                handlePickedWorkDocument(resultCode, data)
                return
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handlePickedWorkDocument(resultCode: Int, data: Intent?) {
        if (resultCode != RESULT_OK || data?.data == null) {
            sendResultAndFinish(RESULT_CANCELED, Intent())
            return
        }
        val uri = data.data ?: run {
            sendResultAndFinish(RESULT_CANCELED, Intent())
            return
        }
        val grantFlags =
            data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val metadata =
            runCatching {
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use Pair<String?, Long?>(null, null)
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    val name =
                        if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                            cursor.getString(nameIndex)
                        } else {
                            null
                        }
                    val size =
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                            cursor.getLong(sizeIndex)
                        } else {
                            null
                        }
                    Pair(name, size)
                }
            }.getOrNull()
        val displayName = metadata?.first?.takeIf { it.isNotBlank() } ?: "selected-file"
        val sizeBytes = metadata?.second
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        val result =
            successIntent()
                .putExtra(WorkProfileProtocol.EXTRA_URI, uri.toString())
                .putExtra(WorkProfileProtocol.EXTRA_DISPLAY_NAME, displayName)
                .putExtra(WorkProfileProtocol.EXTRA_MIME_TYPE, mimeType)
                .putExtra(
                    WorkProfileProtocol.EXTRA_CAN_DELETE,
                    grantFlags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0,
                )
                .apply {
                    if (sizeBytes != null) {
                        putExtra(WorkProfileProtocol.EXTRA_SIZE_BYTES, sizeBytes)
                    }
                    clipData = ClipData.newRawUri(displayName, uri)
                    addFlags(grantFlags)
                }
        sendResultAndFinish(RESULT_OK, result)
    }

    private fun visibleManagedApps(): List<NativeManagedAppState> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val packages = packageManager.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .filter { it != packageName }
            .toMutableSet()
        packages += managedPackages()
        return packages.mapNotNull(::packageState).sortedBy { it.label.lowercase() }
    }

    private fun packageState(targetPackage: String): NativeManagedAppState? {
        return try {
            val app = packageManager.getApplicationInfo(
                targetPackage,
                PackageManager.MATCH_DISABLED_COMPONENTS or
                    PackageManager.MATCH_UNINSTALLED_PACKAGES,
            )
            val hidden = runCatching { dpm.isApplicationHidden(admin, targetPackage) }.getOrDefault(false)
            NativeManagedAppState(
                packageName = targetPackage,
                label = packageManager.getApplicationLabel(app).toString(),
                presentPersonal = false,
                presentWork = true,
                launchableWork = packageManager.getLaunchIntentForPackage(targetPackage) != null,
                systemApp = app.flags and ApplicationInfo.FLAG_SYSTEM != 0,
                suspended = app.flags and ApplicationInfo.FLAG_SUSPENDED != 0,
                hidden = hidden,
                cloneEligibility = NativeCloneEligibility.ALREADY_INSTALLED,
                installerActionRequired = false,
                iconBytes = boundedAppIconPng(packageManager, app),
            )
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun finishApps(apps: List<NativeManagedAppState>) {
        val metadataArray = JSONArray()
        apps.forEach { metadataArray.put(it.toJson(includeIcon = false)) }
        val metadataBytes = metadataArray.toString().toByteArray(Charsets.UTF_8).size
        val iconPayloadDeltas = apps.map { app ->
            val withoutIcon = app.toJson(includeIcon = false).toString().toByteArray(Charsets.UTF_8).size
            val withIcon = app.toJson(includeIcon = true).toString().toByteArray(Charsets.UTF_8).size
            (withIcon - withoutIcon).coerceAtLeast(0)
        }
        val includeIcons = WorkProfileNativePolicy.iconInclusionMask(
            metadataPayloadBytes = metadataBytes,
            iconPayloadDeltas = iconPayloadDeltas,
            maxPayloadBytes = MAX_APPS_JSON_BYTES,
        )
        val array = JSONArray()
        apps.zip(includeIcons).forEach { (app, includeIcon) ->
            array.put(app.toJson(includeIcon = includeIcon))
        }
        sendResultAndFinish(
            RESULT_OK,
            successIntent().putExtra(WorkProfileProtocol.EXTRA_APPS_JSON, array.toString()),
        )
    }

    private fun finishApp(app: NativeManagedAppState?) {
        val result = successIntent()
        if (app != null) {
            result.putExtra(WorkProfileProtocol.EXTRA_APP_JSON, app.toJson().toString())
        }
        sendResultAndFinish(RESULT_OK, result)
    }

    private fun finishSuccess() {
        sendResultAndFinish(RESULT_OK, successIntent())
    }

    private fun finishFailure(code: NativeWorkProfileErrorCode, message: String?) {
        sendResultAndFinish(
            RESULT_OK,
            Intent()
                .putExtra(WorkProfileProtocol.EXTRA_OK, false)
                .putExtra(WorkProfileProtocol.EXTRA_ERROR_CODE, code.name)
                .putExtra(WorkProfileProtocol.EXTRA_MESSAGE, message),
        )
    }

    private fun sendResultAndFinish(resultCode: Int, result: Intent) {
        val callback = resultPendingIntent
        if (callback != null) {
            result.putExtra(WorkProfileProtocol.EXTRA_RESULT_CODE, resultCode)
            try {
                callback.send(this, 0, result)
            } catch (_: PendingIntent.CanceledException) {
                setResult(resultCode, result)
            }
        } else {
            setResult(resultCode, result)
        }
        finish()
    }

    private fun resultPendingIntentFrom(intent: Intent): PendingIntent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(
                WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                PendingIntent::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT)
                as? PendingIntent
        }

    private fun successIntent(): Intent = Intent().putExtra(WorkProfileProtocol.EXTRA_OK, true)

    private fun isAuthorizedIntent(intent: Intent): Boolean {
        val expected = WorkProfileControlToken.read(this) ?: return false
        val supplied =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_CONTROL_TOKEN) ?: return false
        return constantTimeTokenEquals(expected, supplied)
    }

    private fun constantTimeTokenEquals(expected: String, supplied: String): Boolean =
        MessageDigest.isEqual(
            expected.toByteArray(Charsets.UTF_8),
            supplied.toByteArray(Charsets.UTF_8),
        )

    private fun isInstalled(targetPackage: String): Boolean =
        try {
            packageManager.getApplicationInfo(targetPackage, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }

    private fun managedPackages(): Set<String> =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getStringSet(PREF_MANAGED_PACKAGES, emptySet())
            ?.toSet()
            ?: emptySet()

    private fun rememberManagedPackage(targetPackage: String) {
        val packages = managedPackages().toMutableSet()
        packages += targetPackage
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putStringSet(PREF_MANAGED_PACKAGES, packages)
            .apply()
    }

    private fun forgetManagedPackage(targetPackage: String) {
        val packages = managedPackages().toMutableSet()
        packages -= targetPackage
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putStringSet(PREF_MANAGED_PACKAGES, packages)
            .apply()
    }

    private fun NativeManagedAppState.toJson(includeIcon: Boolean = true): JSONObject = JSONObject()
        .put("packageName", packageName)
        .put("label", label)
        .put("presentPersonal", presentPersonal)
        .put("presentWork", presentWork)
        .put("launchableWork", launchableWork)
        .put("systemApp", systemApp)
        .put("suspended", suspended)
        .put("hidden", hidden)
        .put("cloneEligibility", cloneEligibility.name)
        .put("installerActionRequired", installerActionRequired)
        .apply {
            if (includeIcon && iconBytes != null) {
                put("iconBase64", Base64.encodeToString(iconBytes, Base64.NO_WRAP))
            }
        }

    companion object {
        private const val REQUEST_INSTALL_CONFIRMATION = 9411
        private const val REQUEST_UNINSTALL_CONFIRMATION = 9412
        private const val REQUEST_PICK_WORK_DOCUMENT = 9413
        private const val PREFS_NAME = "work_profile_apps"
        private const val PREF_MANAGED_PACKAGES = "managed_packages"
    }
}
