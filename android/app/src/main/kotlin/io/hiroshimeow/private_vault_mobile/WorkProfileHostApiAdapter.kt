package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.app.PendingIntent
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.UserManager
import android.provider.Settings
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.SecureRandom
import java.util.UUID

internal const val MAX_APP_ICON_BYTES = 64 * 1024
internal const val MAX_APPS_JSON_BYTES = 256 * 1024
internal const val APP_ICON_EDGE_PX = 96
private const val MANAGED_PROFILE_SETTINGS_ACTION = "android.settings.MANAGED_PROFILE_SETTINGS"
private const val MANAGE_USERS_PERMISSION = "android.permission.MANAGE_USERS"
private const val MODIFY_QUIET_MODE_PERMISSION = "android.permission.MODIFY_QUIET_MODE"

internal fun boundedAppIconPng(
    packageManager: PackageManager,
    app: ApplicationInfo,
): ByteArray? = runCatching {
    val drawable = app.loadIcon(packageManager)
    val bitmap = Bitmap.createBitmap(
        APP_ICON_EDGE_PX,
        APP_ICON_EDGE_PX,
        Bitmap.Config.ARGB_8888,
    )
    try {
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, APP_ICON_EDGE_PX, APP_ICON_EDGE_PX)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                return@runCatching null
            }
            output.toByteArray().takeIf { it.size <= MAX_APP_ICON_BYTES }
        }
    } finally {
        bitmap.recycle()
    }
}.getOrNull()

internal object WorkProfileProtocol {
    const val ACTION_LIST_WORK_APPS =
        "io.hiroshimeow.private_vault_mobile.action.LIST_WORK_APPS"
    const val ACTION_GET_APP_STATE =
        "io.hiroshimeow.private_vault_mobile.action.GET_APP_STATE"
    const val ACTION_CLONE =
        "io.hiroshimeow.private_vault_mobile.action.CLONE"
    const val ACTION_LAUNCH =
        "io.hiroshimeow.private_vault_mobile.action.LAUNCH"
    const val ACTION_PICK_WORK_DOCUMENT =
        "io.hiroshimeow.private_vault_mobile.action.PICK_WORK_DOCUMENT"
    const val ACTION_OPEN_STORE =
        "io.hiroshimeow.private_vault_mobile.action.OPEN_STORE"
    const val ACTION_SHARE_VAULT_FILE =
        "io.hiroshimeow.private_vault_mobile.action.SHARE_VAULT_FILE"
    const val ACTION_SUSPEND =
        "io.hiroshimeow.private_vault_mobile.action.SUSPEND"
    const val ACTION_HIDE =
        "io.hiroshimeow.private_vault_mobile.action.HIDE"
    const val ACTION_UNINSTALL =
        "io.hiroshimeow.private_vault_mobile.action.UNINSTALL"
    const val ACTION_DESTROY =
        "io.hiroshimeow.private_vault_mobile.action.DESTROY"
    const val ACTION_INSTALL_STATUS =
        "io.hiroshimeow.private_vault_mobile.action.INSTALL_STATUS"
    const val ACTION_UNINSTALL_STATUS =
        "io.hiroshimeow.private_vault_mobile.action.UNINSTALL_STATUS"

    const val EXTRA_PACKAGE_NAME = "package_name"
    const val EXTRA_SYSTEM_APP = "system_app"
    const val EXTRA_BOOL_VALUE = "bool_value"
    const val EXTRA_MIME_TYPE = "mime_type"
    const val EXTRA_DISPLAY_NAME = "display_name"
    const val EXTRA_URI = "uri"
    const val EXTRA_SIZE_BYTES = "size_bytes"
    const val EXTRA_CAN_DELETE = "can_delete"
    const val EXTRA_OK = "ok"
    const val EXTRA_ERROR_CODE = "error_code"
    const val EXTRA_MESSAGE = "message"
    const val EXTRA_APP_JSON = "app_json"
    const val EXTRA_APPS_JSON = "apps_json"
    const val EXTRA_CONTROL_TOKEN = "control_token"
    const val EXTRA_RESULT_PENDING_INTENT = "result_pending_intent"
    const val EXTRA_REQUEST_ID = "request_id"
    const val EXTRA_RESULT_CODE = "result_code"
    const val PROVISIONING_TOKEN_KEY = "private_vault_control_token"

    val forwardedActions = listOf(
        ACTION_LIST_WORK_APPS,
        ACTION_GET_APP_STATE,
        ACTION_CLONE,
        ACTION_LAUNCH,
        ACTION_PICK_WORK_DOCUMENT,
        ACTION_OPEN_STORE,
        ACTION_SHARE_VAULT_FILE,
        ACTION_SUSPEND,
        ACTION_HIDE,
        ACTION_UNINSTALL,
        ACTION_DESTROY,
    )
}

internal object WorkProfileControlToken {
    private const val PREFS = "work_profile_control"
    private const val KEY_TOKEN = "control_token"

    fun getOrCreate(context: Context): String {
        read(context)?.let { return it }
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        val token = Base64.encodeToString(
            bytes,
            Base64.NO_WRAP or Base64.NO_PADDING or Base64.URL_SAFE,
        )
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TOKEN, token)
            .apply()
        return token
    }

    fun store(context: Context, token: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TOKEN, token)
            .apply()
    }

    fun read(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, null)
}

internal object WorkProfileResultRegistry {
    private data class Entry(
        val callback: (Int, Intent?) -> Unit,
        val timeout: Runnable,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val entries = mutableMapOf<Int, Entry>()

    @Synchronized
    fun register(
        requestId: Int,
        timeoutMs: Long,
        timeoutCode: NativeWorkProfileErrorCode,
        callback: (Int, Intent?) -> Unit,
    ) {
        cancel(requestId)
        val timeout = Runnable {
            val pending = synchronized(this) { entries.remove(requestId) }
                ?: return@Runnable
            val message = when (timeoutCode) {
                NativeWorkProfileErrorCode.BRIDGE_TIMEOUT ->
                    "Work Profile did not respond. Turn it on and retry."
                else ->
                    "Work-profile operation did not complete. Retry after Android finishes any pending confirmation."
            }
            pending.callback(
                Activity.RESULT_CANCELED,
                Intent()
                    .putExtra(WorkProfileProtocol.EXTRA_OK, false)
                    .putExtra(
                        WorkProfileProtocol.EXTRA_ERROR_CODE,
                        timeoutCode.name,
                    )
                    .putExtra(
                        WorkProfileProtocol.EXTRA_MESSAGE,
                        message,
                    ),
            )
        }
        entries[requestId] = Entry(callback, timeout)
        mainHandler.postDelayed(timeout, timeoutMs)
    }

    @Synchronized
    fun contains(requestId: Int): Boolean = entries.containsKey(requestId)

    fun deliver(requestId: Int, resultCode: Int, data: Intent?) {
        val entry = synchronized(this) { entries.remove(requestId) } ?: return
        mainHandler.removeCallbacks(entry.timeout)
        entry.callback(resultCode, data)
    }

    @Synchronized
    fun cancel(requestId: Int) {
        val entry = entries.remove(requestId) ?: return
        mainHandler.removeCallbacks(entry.timeout)
    }

}

class WorkProfileResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getIntExtra(WorkProfileProtocol.EXTRA_REQUEST_ID, -1)
        if (requestId < 0) return
        val resultCode =
            intent.getIntExtra(
                WorkProfileProtocol.EXTRA_RESULT_CODE,
                Activity.RESULT_CANCELED,
            )
        WorkProfileResultRegistry.deliver(requestId, resultCode, intent)
    }
}

internal object WorkProfileProvisioningConfigurator {
    fun enableProfile(context: Context) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        val admin = ComponentName(context, PrivateVaultDeviceAdminReceiver::class.java)
        if (!dpm.isProfileOwnerApp(context.packageName)) return
        dpm.setProfileEnabled(admin)
    }

    fun configure(context: Context, controlToken: String) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        val admin = ComponentName(context, PrivateVaultDeviceAdminReceiver::class.java)
        if (!dpm.isProfileOwnerApp(context.packageName)) return

        WorkProfileControlToken.store(context, controlToken)

        val bridge = ComponentName(context, WorkProfileBridgeActivity::class.java)
        context.packageManager.setComponentEnabledSetting(
            bridge,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )

        dpm.clearCrossProfileIntentFilters(admin)
        WorkProfileProtocol.forwardedActions.forEach { action ->
            val filter = IntentFilter(action).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            dpm.addCrossProfileIntentFilter(
                admin,
                filter,
                DevicePolicyManager.FLAG_MANAGED_CAN_ACCESS_PARENT,
            )
        }
        dpm.addUserRestriction(admin, UserManager.DISALLOW_CROSS_PROFILE_COPY_PASTE)
        dpm.setProfileEnabled(admin)
    }
}

class PrivateVaultDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        if (!dpm.isProfileOwnerApp(context.packageName)) return

        @Suppress("DEPRECATION")
        val provisioningExtras =
            intent.getParcelableExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
            ) as? PersistableBundle
        val controlToken =
            provisioningExtras?.getString(WorkProfileProtocol.PROVISIONING_TOKEN_KEY)
        if (controlToken.isNullOrBlank()) {
            WorkProfileProvisioningConfigurator.enableProfile(context)
            return
        }
        WorkProfileProvisioningConfigurator.configure(context, controlToken)
    }
}

class WorkProfileHostApiAdapter(
    private val activity: MainActivity,
) : WorkProfileHostApi {
    private val context: Context
        get() = activity.applicationContext
    private val dpm: DevicePolicyManager =
        context.getSystemService(DevicePolicyManager::class.java)
    private val userManager: UserManager =
        context.getSystemService(UserManager::class.java)
    private val pendingResults = mutableMapOf<Int, (Int, Intent?) -> Unit>()
    private var nextRequestCode = 17000

    private fun isProfileOwner(): Boolean = dpm.isProfileOwnerApp(context.packageName)

    override fun getCapability(): NativeWorkProfileCapability {
        val supported =
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_MANAGED_USERS)
        val profileOwner = isProfileOwner()
        val bridgeResolvable = isBridgeResolvable()
        val hasControlToken = WorkProfileControlToken.read(context) != null
        val profiles = userManager.userProfiles
        val otherProfile = profiles.firstOrNull { it != android.os.Process.myUserHandle() }
        val profileQuiet =
            hasControlToken &&
                otherProfile != null &&
                runCatching { userManager.isQuietModeEnabled(otherProfile) }.getOrDefault(false)
        val provisioningAllowed =
            supported &&
                dpm.isProvisioningAllowed(
                    DevicePolicyManager.ACTION_PROVISION_MANAGED_PROFILE,
                )
        val state = WorkProfileNativePolicy.capabilityState(
            supported = supported,
            profileOwner = profileOwner,
            bridgeResolvable = bridgeResolvable,
            hasControlToken = hasControlToken,
            provisioningAllowed = provisioningAllowed,
            profileCount = profiles.size,
            profileQuiet = profileQuiet,
        )
        return NativeWorkProfileCapability(
            supported = supported,
            provisioningAllowed =
                provisioningAllowed && state == NativeWorkProfileState.ABSENT,
            profileState = state,
        )
    }

    override fun getProfileState(): NativeWorkProfileState = getCapability().profileState

    override fun startProvisioning(callback: (Result<NativeOperationResult>) -> Unit) {
        val capability = getCapability()
        if (!capability.supported) {
            callback(Result.success(failure(NativeWorkProfileErrorCode.UNSUPPORTED)))
            return
        }
        if (!capability.provisioningAllowed) {
            callback(
                Result.success(
                    failure(
                        if (capability.profileState == NativeWorkProfileState.CONFLICTING_PROFILE) {
                            NativeWorkProfileErrorCode.CONFLICTING_PROFILE
                        } else {
                            NativeWorkProfileErrorCode.POLICY_DENIED
                        },
                    ),
                ),
            )
            return
        }

        val requestCode = allocateRequestCode()
        pendingResults[requestCode] = { resultCode, _ ->
            if (resultCode != Activity.RESULT_OK) {
                callback(
                    Result.success(
                        NativeOperationResult(
                            false,
                            NativeWorkProfileErrorCode.POLICY_DENIED,
                            "Android work-profile provisioning was cancelled.",
                        ),
                    ),
                )
            } else {
                waitForProvisionedProfile(callback, 0)
            }
        }

        val controlToken = WorkProfileControlToken.getOrCreate(context)
        val provisioningExtras = PersistableBundle().apply {
            putString(WorkProfileProtocol.PROVISIONING_TOKEN_KEY, controlToken)
        }
        val intent = Intent(DevicePolicyManager.ACTION_PROVISION_MANAGED_PROFILE).apply {
            putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME,
                ComponentName(context, PrivateVaultDeviceAdminReceiver::class.java),
            )
            putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
                provisioningExtras,
            )
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pendingResults.remove(requestCode)
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                        error.message,
                    ),
                ),
            )
        }
    }

    override fun requestQuietModeDisabled(
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        val otherProfile =
            userManager.userProfiles.firstOrNull { it != android.os.Process.myUserHandle() }
        if (otherProfile == null) {
            callback(Result.success(failure(NativeWorkProfileErrorCode.PROFILE_ABSENT)))
            return
        }

        val authorizedCaller =
            context.checkSelfPermission(MANAGE_USERS_PERMISSION) == PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(MODIFY_QUIET_MODE_PERMISSION) == PackageManager.PERMISSION_GRANTED ||
                isDefaultLauncher()
        if (WorkProfileNativePolicy.shouldRequestQuietModeDirectly(Build.VERSION.SDK_INT, authorizedCaller)) {
            try {
                if (userManager.requestQuietModeEnabled(false, otherProfile)) {
                    callback(Result.success(NativeOperationResult(true, null, null)))
                    return
                }
            } catch (_: SecurityException) {
                // Fall through to system-managed settings; do not claim direct recovery succeeded.
            }
        }

        launchQuietModeSettings(callback)
    }

    private fun isDefaultLauncher(): Boolean {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == context.packageName
    }

    private fun launchQuietModeSettings(callback: (Result<NativeOperationResult>) -> Unit) {
        val managedProfileSettings = Intent(MANAGED_PROFILE_SETTINGS_ACTION)
        val intent = if (context.packageManager.resolveActivity(managedProfileSettings, 0) != null) {
            managedProfileSettings
        } else {
            Intent(Settings.ACTION_SETTINGS)
        }
        val requestCode = allocateRequestCode()
        pendingResults[requestCode] = { _, _ ->
            callback(Result.success(NativeOperationResult(true, null, null)))
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (_: SecurityException) {
            pendingResults.remove(requestCode)
            val fallback = Intent(Settings.ACTION_SETTINGS)
            if (intent.action != Settings.ACTION_SETTINGS && context.packageManager.resolveActivity(fallback, 0) != null) {
                pendingResults[requestCode] = { _, _ ->
                    callback(Result.success(NativeOperationResult(true, null, null)))
                }
                try {
                    activity.startActivityForResult(fallback, requestCode)
                    return
                } catch (_: Exception) {
                    pendingResults.remove(requestCode)
                }
            }
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.USER_ACTION_REQUIRED,
                        "Turn Work Profile on from Android Quick Settings or system settings, then retry.",
                    ),
                ),
            )
        } catch (error: Exception) {
            pendingResults.remove(requestCode)
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                        error.message,
                    ),
                ),
            )
        }
    }

    override fun listPersonalApps(): List<NativeManagedAppState> {
        if (isProfileOwner()) return emptyList()
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return context.packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { info -> personalPackageState(info.activityInfo.packageName) }
            .filter { it.packageName != context.packageName }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }

    override fun listWorkApps(callback: (Result<List<NativeManagedAppState>>) -> Unit) {
        launchAppsResult(bridgeIntent(WorkProfileProtocol.ACTION_LIST_WORK_APPS), callback)
    }

    override fun getAppState(
        packageName: String,
        callback: (Result<NativeManagedAppState?>) -> Unit,
    ) {
        val intent = bridgeIntent(WorkProfileProtocol.ACTION_GET_APP_STATE)
            .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName)
        launchAppResult(intent, callback)
    }

    override fun cloneToWorkProfile(
        packageName: String,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        if (isProfileOwner()) {
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
                        "Start cloning from the personal profile.",
                    ),
                ),
            )
            return
        }

        val app = try {
            context.packageManager.getApplicationInfo(packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            callback(Result.success(failure(NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE)))
            return
        }

        val intent = bridgeIntent(WorkProfileProtocol.ACTION_CLONE)
            .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName)
        val isSystemApp = app.flags and ApplicationInfo.FLAG_SYSTEM != 0
        intent.putExtra(WorkProfileProtocol.EXTRA_SYSTEM_APP, isSystemApp)

        if (isSystemApp) {
            launchOperation(intent, callback)
            return
        }

        val staged = try {
            stagePackageApks(app)
        } catch (error: Exception) {
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.INSTALLER_FAILURE,
                        error.message,
                    ),
                ),
            )
            return
        }
        val uris = staged.map { CloneTransferProvider.uriFor(context, it) }
        val clip = ClipData.newUri(
            context.contentResolver,
            "Private Vault app clone",
            uris.first(),
        )
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        intent.clipData = clip
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

        launchOperation(intent, callback) {
            uris.forEach { uri ->
                runCatching {
                    context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
            staged.forEach { file -> runCatching { file.delete() } }
        }
    }

    override fun launchWorkApp(
        packageName: String,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        launchOperation(
            bridgeIntent(WorkProfileProtocol.ACTION_LAUNCH)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName),
            callback,
        )
    }

    override fun pickWorkDocument(
        callback: (Result<NativePickedWorkDocument?>) -> Unit,
    ) {
        launchDocumentResult(
            bridgeIntent(WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT),
            callback,
        )
    }

    override fun openWorkStore(
        packageName: String,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        launchOperation(
            bridgeIntent(WorkProfileProtocol.ACTION_OPEN_STORE)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName),
            callback,
        )
    }

    override fun shareVaultFileToWorkApp(
        packageName: String,
        stagedFileName: String,
        mimeType: String,
        displayName: String,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        val root = File(context.cacheDir, VaultShuttleProvider.TRANSFER_DIR).canonicalFile
        val staged = File(root, stagedFileName).canonicalFile
        if (staged.parentFile != root || !staged.isFile) {
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.UNAUTHORIZED,
                        "Vault shuttle file is unavailable.",
                    ),
                ),
            )
            return
        }

        val uri = VaultShuttleProvider.uriFor(
            context = context,
            file = staged,
            mimeType = mimeType,
            displayName = displayName,
        )
        val intent =
            bridgeIntent(WorkProfileProtocol.ACTION_SHARE_VAULT_FILE)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName)
                .putExtra(WorkProfileProtocol.EXTRA_MIME_TYPE, mimeType)
                .putExtra(WorkProfileProtocol.EXTRA_DISPLAY_NAME, displayName)
                .apply {
                    clipData =
                        ClipData.newUri(
                            context.contentResolver,
                            displayName,
                            uri,
                        )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
        launchOperation(intent, callback)
    }

    override fun setSuspended(
        packageName: String,
        suspended: Boolean,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        launchOperation(
            bridgeIntent(WorkProfileProtocol.ACTION_SUSPEND)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName)
                .putExtra(WorkProfileProtocol.EXTRA_BOOL_VALUE, suspended),
            callback,
        )
    }

    override fun setHidden(
        packageName: String,
        hidden: Boolean,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        launchOperation(
            bridgeIntent(WorkProfileProtocol.ACTION_HIDE)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName)
                .putExtra(WorkProfileProtocol.EXTRA_BOOL_VALUE, hidden),
            callback,
        )
    }

    override fun uninstallWorkApp(
        packageName: String,
        callback: (Result<NativeOperationResult>) -> Unit,
    ) {
        launchOperation(
            bridgeIntent(WorkProfileProtocol.ACTION_UNINSTALL)
                .putExtra(WorkProfileProtocol.EXTRA_PACKAGE_NAME, packageName),
            callback,
        )
    }

    override fun destroyWorkProfile(callback: (Result<NativeOperationResult>) -> Unit) {
        launchOperation(bridgeIntent(WorkProfileProtocol.ACTION_DESTROY), callback)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val handler = pendingResults.remove(requestCode) ?: return false
        handler(resultCode, data)
        return true
    }

    private fun launchOperation(
        intent: Intent,
        callback: (Result<NativeOperationResult>) -> Unit,
        cleanup: () -> Unit = {},
    ) {
        val requestCode = allocateRequestCode()
        WorkProfileResultRegistry.register(
            requestId = requestCode,
            timeoutMs = WorkProfileNativePolicy.bridgeTimeoutMs(intent.action),
            timeoutCode = WorkProfileNativePolicy.bridgeTimeoutError(intent.action),
        ) { resultCode, data ->
            try {
                callback(Result.success(operationResult(resultCode, data)))
            } finally {
                cleanup()
            }
        }
        try {
            activity.startActivity(
                intent.putExtra(
                    WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                    bridgeResultPendingIntent(requestCode),
                ),
            )
        } catch (error: Exception) {
            WorkProfileResultRegistry.cancel(requestCode)
            cleanup()
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                        error.message,
                    ),
                ),
            )
        }
    }

    private fun launchAppsResult(
        intent: Intent,
        callback: (Result<List<NativeManagedAppState>>) -> Unit,
    ) {
        val requestCode = allocateRequestCode()
        WorkProfileResultRegistry.register(
            requestId = requestCode,
            timeoutMs = WorkProfileNativePolicy.FAST_BRIDGE_TIMEOUT_MS,
            timeoutCode = NativeWorkProfileErrorCode.BRIDGE_TIMEOUT,
        ) { resultCode, data ->
            try {
                if (resultCode != Activity.RESULT_OK || data == null) {
                    throw IllegalStateException(
                        data?.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE)
                            ?: "Work profile did not return an app inventory.",
                    )
                }
                val raw = data.getStringExtra(WorkProfileProtocol.EXTRA_APPS_JSON) ?: "[]"
                val array = JSONArray(raw)
                callback(
                    Result.success(
                        (0 until array.length()).map {
                            nativeAppState(array.getJSONObject(it))
                        },
                    ),
                )
            } catch (error: Exception) {
                callback(Result.failure(error))
            }
        }
        try {
            activity.startActivity(
                intent.putExtra(
                    WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                    bridgeResultPendingIntent(requestCode),
                ),
            )
        } catch (error: Exception) {
            WorkProfileResultRegistry.cancel(requestCode)
            callback(Result.failure(error))
        }
    }

    private fun launchAppResult(
        intent: Intent,
        callback: (Result<NativeManagedAppState?>) -> Unit,
    ) {
        val requestCode = allocateRequestCode()
        WorkProfileResultRegistry.register(
            requestId = requestCode,
            timeoutMs = WorkProfileNativePolicy.FAST_BRIDGE_TIMEOUT_MS,
            timeoutCode = NativeWorkProfileErrorCode.BRIDGE_TIMEOUT,
        ) { resultCode, data ->
            try {
                if (resultCode != Activity.RESULT_OK || data == null) {
                    throw IllegalStateException(
                        data?.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE)
                            ?: "Work profile did not return app state.",
                    )
                }
                val raw = data.getStringExtra(WorkProfileProtocol.EXTRA_APP_JSON)
                callback(Result.success(raw?.let { nativeAppState(JSONObject(it)) }))
            } catch (error: Exception) {
                callback(Result.failure(error))
            }
        }
        try {
            activity.startActivity(
                intent.putExtra(
                    WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                    bridgeResultPendingIntent(requestCode),
                ),
            )
        } catch (error: Exception) {
            WorkProfileResultRegistry.cancel(requestCode)
            callback(Result.failure(error))
        }
    }

    private fun launchDocumentResult(
        intent: Intent,
        callback: (Result<NativePickedWorkDocument?>) -> Unit,
    ) {
        val requestCode = allocateRequestCode()
        WorkProfileResultRegistry.register(
            requestId = requestCode,
            timeoutMs = WorkProfileNativePolicy.bridgeTimeoutMs(intent.action),
            timeoutCode = WorkProfileNativePolicy.bridgeTimeoutError(intent.action),
        ) { resultCode, data ->
            try {
                val typedError = data?.getStringExtra(WorkProfileProtocol.EXTRA_ERROR_CODE)
                if (typedError != null) {
                    callback(
                        Result.failure(
                            FlutterError(
                                typedError,
                                data.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE),
                            ),
                        ),
                    )
                    return@register
                }
                if (resultCode == Activity.RESULT_CANCELED) {
                    callback(Result.success(null))
                    return@register
                }
                if (resultCode != Activity.RESULT_OK || data == null) {
                    throw FlutterError(
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED.name,
                        data?.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE)
                            ?: "Work Profile did not return a selected document.",
                    )
                }
                val rawUri = data.getStringExtra(WorkProfileProtocol.EXTRA_URI)
                    ?: throw FlutterError(
                        NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE.name,
                        "Selected document URI is missing.",
                    )
                callback(
                    Result.success(
                        NativePickedWorkDocument(
                            uri = rawUri,
                            displayName =
                                data.getStringExtra(WorkProfileProtocol.EXTRA_DISPLAY_NAME)
                                    ?: "selected-file",
                            mimeType =
                                data.getStringExtra(WorkProfileProtocol.EXTRA_MIME_TYPE)
                                    ?: "application/octet-stream",
                            sizeBytes =
                                if (data.hasExtra(WorkProfileProtocol.EXTRA_SIZE_BYTES)) {
                                    data.getLongExtra(
                                        WorkProfileProtocol.EXTRA_SIZE_BYTES,
                                        0L,
                                    )
                                } else {
                                    null
                                },
                            canDelete =
                                data.getBooleanExtra(
                                    WorkProfileProtocol.EXTRA_CAN_DELETE,
                                    false,
                                ),
                        ),
                    ),
                )
            } catch (error: Exception) {
                callback(Result.failure(error))
            }
        }
        try {
            activity.startActivity(
                intent.putExtra(
                    WorkProfileProtocol.EXTRA_RESULT_PENDING_INTENT,
                    bridgeResultPendingIntent(requestCode),
                ),
            )
        } catch (error: Exception) {
            WorkProfileResultRegistry.cancel(requestCode)
            callback(
                Result.failure(
                    FlutterError(
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED.name,
                        error.message,
                    ),
                ),
            )
        }
    }

    private fun operationResult(resultCode: Int, data: Intent?): NativeOperationResult {
        val typedError =
            data?.getStringExtra(WorkProfileProtocol.EXTRA_ERROR_CODE)
                ?.let { name ->
                    runCatching { NativeWorkProfileErrorCode.valueOf(name) }.getOrNull()
                }
        if (typedError != null) {
            return NativeOperationResult(
                false,
                typedError,
                data.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE),
            )
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            return NativeOperationResult(
                false,
                NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                "Work-profile operation did not return a result.",
            )
        }
        if (data.getBooleanExtra(WorkProfileProtocol.EXTRA_OK, false)) {
            return NativeOperationResult(true, null, null)
        }
        return NativeOperationResult(
            false,
            NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
            data.getStringExtra(WorkProfileProtocol.EXTRA_MESSAGE),
        )
    }

    private fun nativeAppState(json: JSONObject): NativeManagedAppState =
        NativeManagedAppState(
            packageName = json.getString("packageName"),
            label = json.getString("label"),
            presentPersonal = json.optBoolean("presentPersonal", false),
            presentWork = json.optBoolean("presentWork", true),
            launchableWork = json.optBoolean("launchableWork", false),
            systemApp = json.optBoolean("systemApp", false),
            suspended = json.optBoolean("suspended", false),
            hidden = json.optBoolean("hidden", false),
            cloneEligibility = runCatching {
                NativeCloneEligibility.valueOf(json.getString("cloneEligibility"))
            }.getOrDefault(NativeCloneEligibility.UNSUPPORTED),
            installerActionRequired = json.optBoolean("installerActionRequired", false),
            iconBytes =
                json.optString("iconBase64")
                    .takeIf { it.isNotBlank() }
                    ?.let { encoded ->
                        runCatching { Base64.decode(encoded, Base64.DEFAULT) }
                            .getOrNull()
                            ?.takeIf { it.size <= MAX_APP_ICON_BYTES }
                    },
        )

    private fun personalPackageState(packageName: String): NativeManagedAppState? {
        return try {
            val app = context.packageManager.getApplicationInfo(packageName, 0)
            val system = app.flags and ApplicationInfo.FLAG_SYSTEM != 0
            NativeManagedAppState(
                packageName = packageName,
                label = context.packageManager.getApplicationLabel(app).toString(),
                presentPersonal = true,
                presentWork = false,
                launchableWork =
                    context.packageManager.getLaunchIntentForPackage(packageName) != null,
                systemApp = system,
                suspended = app.flags and ApplicationInfo.FLAG_SUSPENDED != 0,
                hidden = false,
                cloneEligibility = if (system) {
                    NativeCloneEligibility.SYSTEM_APP
                } else {
                    NativeCloneEligibility.ELIGIBLE
                },
                installerActionRequired = !system,
                iconBytes = boundedAppIconPng(context.packageManager, app),
            )
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun stagePackageApks(app: ApplicationInfo): List<File> {
        val root = File(context.cacheDir, CloneTransferProvider.TRANSFER_DIR)
        if (!root.exists() && !root.mkdirs()) {
            throw IllegalStateException("Unable to create clone transfer directory.")
        }

        val token = UUID.randomUUID().toString()
        val sources = WorkProfileNativePolicy.apkSourcePaths(
            app.sourceDir,
            app.splitSourceDirs,
        ).map(::File)
        val created = mutableListOf<File>()
        try {
            return sources.mapIndexed { index, source ->
                if (!source.isFile) {
                    throw IllegalStateException(
                        "APK source is unavailable: ${source.name}",
                    )
                }
                val role = if (index == 0) "base" else "split_$index"
                val safeName =
                    source.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val target = File(root, "${token}_${role}_${safeName}")
                source.copyTo(target, overwrite = true)
                created += target
                target
            }
        } catch (error: Exception) {
            created.forEach { file -> runCatching { file.delete() } }
            throw error
        }
    }

    private fun bridgeIntent(action: String): Intent =
        Intent(action)
            .addCategory(Intent.CATEGORY_DEFAULT)
            .putExtra(
                WorkProfileProtocol.EXTRA_CONTROL_TOKEN,
                WorkProfileControlToken.read(context),
            )

    private fun isBridgeResolvable(): Boolean =
        context.packageManager.queryIntentActivities(
            bridgeIntent(WorkProfileProtocol.ACTION_LIST_WORK_APPS),
            PackageManager.MATCH_DEFAULT_ONLY,
        ).isNotEmpty()

    private fun waitForProvisionedProfile(
        callback: (Result<NativeOperationResult>) -> Unit,
        attempt: Int,
    ) {
        if (isBridgeResolvable()) {
            callback(Result.success(NativeOperationResult(true, null, null)))
            return
        }
        if (attempt >= 20) {
            callback(
                Result.success(
                    NativeOperationResult(
                        false,
                        NativeWorkProfileErrorCode.OEM_UNSUPPORTED,
                        "Android returned from provisioning before the managed profile became reachable.",
                    ),
                ),
            )
            return
        }
        Handler(Looper.getMainLooper()).postDelayed(
            { waitForProvisionedProfile(callback, attempt + 1) },
            250,
        )
    }

    private fun bridgeResultPendingIntent(requestCode: Int): PendingIntent {
        val resultIntent =
            Intent(context, WorkProfileResultReceiver::class.java)
                .setData(Uri.parse("private-vault://work-result/$requestCode"))
                .putExtra(WorkProfileProtocol.EXTRA_REQUEST_ID, requestCode)
        val mutableFlag =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            resultIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
        )
    }

    private fun allocateRequestCode(): Int {
        if (nextRequestCode >= 32000) nextRequestCode = 17000
        while (
            pendingResults.containsKey(nextRequestCode) ||
                WorkProfileResultRegistry.contains(nextRequestCode)
        ) {
            nextRequestCode += 1
        }
        return nextRequestCode++
    }

    private fun failure(code: NativeWorkProfileErrorCode): NativeOperationResult =
        NativeOperationResult(false, code, null)
}
