package io.hiroshimeow.private_vault_mobile

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.Parcel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.util.concurrent.Executors

class CloneProfileBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    @Volatile private var serviceBinder: IBinder? = null
    @Volatile private var disposed = false
    private var binding = false
    private val serviceWaiters = mutableListOf<(IBinder?) -> Unit>()

    private val serviceArgs = Shizuku.UserServiceArgs(
        ComponentName(activity, CloneProfileUserService::class.java),
    )
        .processNameSuffix("clone_profile")
        .tag("private-vault-clone-profile")
        .version(1)
        .daemon(false)

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            synchronized(serviceWaiters) {
                binding = false
                val activeService = if (disposed) null else service
                serviceBinder = activeService
                val waiters = serviceWaiters.toList()
                serviceWaiters.clear()
                waiters.forEach { it(activeService) }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            serviceBinder = null
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapability" -> withPrivilegedResult(result) { capability(it) }
                "requestPrivilege" -> requestPrivilege(result)
                "listApps" -> withPrivilegedResult(result) { listApps(it) }
                "clone" -> {
                    val packageName = call.argument<String>("packageName")
                    if (!isPackageName(packageName)) {
                        result.error("INVALID_PACKAGE", "Invalid package name", null)
                    } else {
                        withPrivilegedResult(result) { clonePackage(it, packageName!!) }
                    }
                }
                "launch" -> {
                    val packageName = call.argument<String>("packageName")
                    if (!isPackageName(packageName)) {
                        result.error("INVALID_PACKAGE", "Invalid package name", null)
                    } else {
                        withPrivilegedResult(result) { launchPackage(it, packageName!!) }
                    }
                }
                "uninstall" -> {
                    val packageName = call.argument<String>("packageName")
                    if (!isPackageName(packageName)) {
                        result.error("INVALID_PACKAGE", "Invalid package name", null)
                    } else {
                        withPrivilegedResult(result) { uninstallPackage(it, packageName!!) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPrivilege(result: MethodChannel.Result) {
        if (!Shizuku.pingBinder()) {
            result.success(false)
            return
        }
        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val listener = object : Shizuku.OnRequestPermissionResultListener {
            override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
                if (requestCode != PERMISSION_REQUEST) return
                Shizuku.removeRequestPermissionResultListener(this)
                activity.runOnUiThread {
                    result.success(grantResult == PackageManager.PERMISSION_GRANTED)
                }
            }
        }
        Shizuku.addRequestPermissionResultListener(listener)
        try {
            Shizuku.requestPermission(PERMISSION_REQUEST)
        } catch (error: RuntimeException) {
            Shizuku.removeRequestPermissionResultListener(listener)
            result.success(false)
        }
    }

    private fun withPrivilegedResult(
        result: MethodChannel.Result,
        operation: (IBinder) -> Any?,
    ) {
        if (!Shizuku.pingBinder() ||
            Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(
                mapOf(
                    "state" to STATE_PRIVILEGE_REQUIRED,
                    "message" to "Shizuku is not running or Private Vault has not been authorized.",
                ),
            )
            return
        }
        withService { binder ->
            if (binder == null) {
                activity.runOnUiThread {
                    result.success(
                        mapOf(
                            "state" to STATE_OPERATION_FAILED,
                            "message" to "Privileged clone service could not be started.",
                        ),
                    )
                }
                return@withService
            }
            executor.execute {
                try {
                    val value = operation(binder)
                    activity.runOnUiThread { result.success(value) }
                } catch (error: Exception) {
                    activity.runOnUiThread {
                        result.success(
                            mapOf(
                                "state" to STATE_OPERATION_FAILED,
                                "message" to (error.message ?: "Clone operation failed."),
                            ),
                        )
                    }
                }
            }
        }
    }

    private fun withService(callback: (IBinder?) -> Unit) {
        if (disposed) {
            callback(null)
            return
        }
        val current = serviceBinder
        if (current?.isBinderAlive == true) {
            callback(current)
            return
        }
        synchronized(serviceWaiters) {
            if (disposed) {
                callback(null)
                return
            }
            val rechecked = serviceBinder
            if (rechecked?.isBinderAlive == true) {
                callback(rechecked)
                return
            }
            serviceWaiters += callback
            if (binding) return
            binding = true
            try {
                Shizuku.bindUserService(serviceArgs, serviceConnection)
            } catch (_: RuntimeException) {
                binding = false
                val waiters = serviceWaiters.toList()
                serviceWaiters.clear()
                waiters.forEach { it(null) }
            }
        }
    }

    private fun capability(binder: IBinder): Map<String, Any?> {
        val users = run(binder, "list-users")
        val owned = prefs.getInt(KEY_OWNED_CLONE_USER, -1)
        val discovery = CloneProfileDiscovery.fromListUsers(
            exitCode = users.exitCode,
            stdout = users.stdout,
            stderr = users.stderr,
            ownedUserId = owned,
        )
        if (discovery.clearOwned) {
            prefs.edit().remove(KEY_OWNED_CLONE_USER).apply()
        }
        return when (discovery.state) {
            CloneProfileDiscovery.State.ready -> mapOf(
                "state" to STATE_READY,
                "userId" to discovery.userId,
            )
            CloneProfileDiscovery.State.conflicting -> mapOf(
                "state" to STATE_CONFLICTING_PROFILE,
                "message" to "An existing clone profile is not exclusively owned by Private Vault.",
                "userId" to discovery.userId,
            )
            CloneProfileDiscovery.State.operationFailed -> mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to discovery.message,
            )
        }
    }

    private fun listApps(binder: IBinder): Map<String, Any?> {
        val cap = capability(binder)
        if (cap["state"] != STATE_READY) return cap
        val cloneUser = cap["userId"] as Int?
        val installed = cloneUser?.let { userId ->
            val packages = run(binder, "list-packages", listOf(userId.toString()))
            val parsed = CloneProfilePackageList.fromCommand(
                exitCode = packages.exitCode,
                stdout = packages.stdout,
                stderr = packages.stderr,
            )
            if (!parsed.ok) {
                return mapOf(
                    "state" to STATE_OPERATION_FAILED,
                    "message" to parsed.message,
                    "userId" to cloneUser,
                )
            }
            parsed.packages
        } ?: emptySet()

        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = mutableSetOf<String>()
        val apps = activity.packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val packageName = info.activityInfo.packageName
                if (packageName == activity.packageName || !seen.add(packageName)) {
                    return@mapNotNull null
                }
                mapOf(
                    "packageName" to packageName,
                    "label" to info.loadLabel(activity.packageManager).toString(),
                    "cloned" to installed.contains(packageName),
                    "iconBytes" to boundedAppIconPng(
                        activity.packageManager,
                        info.activityInfo.applicationInfo,
                    ),
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
        return mapOf(
            "state" to STATE_READY,
            "userId" to cloneUser,
            "apps" to apps,
        )
    }

    private fun clonePackage(binder: IBinder, packageName: String): Map<String, Any?> {
        var cap = capability(binder)
        if (cap["state"] != STATE_READY) return cap
        var userId = cap["userId"] as Int?
        if (userId == null) {
            val currentUser = run(binder, "current-user")
            val parentUserId = currentUser.stdout.trim().toIntOrNull()
            if (currentUser.exitCode != 0 || parentUserId == null || parentUserId < 0) {
                return mapOf(
                    "state" to STATE_OPERATION_FAILED,
                    "message" to "Android current user could not be verified.",
                )
            }
            val create = run(
                binder,
                "create-clone",
                listOf(parentUserId.toString()),
            )
            if (create.exitCode != 0) {
                val details = "${create.stdout}\n${create.stderr}".trim()
                    .ifBlank { "Android did not create a clone profile." }
                    .take(2048)
                val failure = CloneProfileCreatePolicy.classifyFailure(
                    create.stdout,
                    create.stderr,
                )
                return mapOf(
                    "state" to if (
                        failure == CloneProfileCreatePolicy.FailureState.cloneProfileUnsupportedByOem
                    ) {
                        STATE_OEM_UNSUPPORTED
                    } else {
                        STATE_OPERATION_FAILED
                    },
                    "message" to details,
                )
            }
            val users = run(binder, "list-users")
            if (users.exitCode != 0) {
                return mapOf(
                    "state" to STATE_OPERATION_FAILED,
                    "message" to "${users.stdout}\n${users.stderr}".trim()
                        .ifBlank { "Clone profile was created but Android users could not be queried." }
                        .take(2048),
                )
            }
            val proof = CloneProfileCreatePolicy.verifyCreatedClone(
                createStdout = create.stdout,
                postCreateUsers = users.stdout,
            )
            if (proof.state != CloneProfileDiscovery.State.ready ||
                proof.userId == null
            ) {
                return mapOf(
                    "state" to if (proof.state == CloneProfileDiscovery.State.conflicting) {
                        STATE_CONFLICTING_PROFILE
                    } else {
                        STATE_OPERATION_FAILED
                    },
                    "message" to proof.message,
                    "userId" to proof.userId,
                )
            }
            userId = proof.userId
            prefs.edit().putInt(KEY_OWNED_CLONE_USER, userId).apply()
        }

        val start = run(binder, "start-user", listOf(userId.toString()))
        CloneProfileStartPolicy.failureMessage(
            exitCode = start.exitCode,
            stdout = start.stdout,
            stderr = start.stderr,
        )?.let { message ->
            return mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to message,
                "userId" to userId,
            )
        }
        val install = run(
            binder,
            "install-existing",
            listOf(userId.toString(), packageName),
        )
        if (install.exitCode != 0 ||
            !install.stdout.contains("installed", ignoreCase = true)
        ) {
            return mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to "${install.stdout}\n${install.stderr}".trim()
                    .ifBlank { "Package could not be installed in the clone profile." },
            )
        }
        return mapOf("state" to STATE_READY, "userId" to userId, "ok" to true)
    }

    private fun launchPackage(binder: IBinder, packageName: String): Map<String, Any?> {
        val cap = capability(binder)
        if (cap["state"] != STATE_READY) return cap
        val userId = cap["userId"] as Int?
            ?: return mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to "No Private Vault clone profile exists yet.",
            )
        val resolve = run(
            binder,
            "resolve-activity",
            listOf(userId.toString(), packageName),
        )
        val component = resolve.stdout
            .lineSequence()
            .map(String::trim)
            .firstOrNull { it.matches(COMPONENT_REGEX) }
            ?: return mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to "The cloned package has no launchable activity.",
            )
        val start = run(binder, "start-user", listOf(userId.toString()))
        CloneProfileStartPolicy.failureMessage(
            exitCode = start.exitCode,
            stdout = start.stdout,
            stderr = start.stderr,
        )?.let { message ->
            return mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to message,
                "userId" to userId,
            )
        }
        val launch = run(
            binder,
            "launch",
            listOf(userId.toString(), component),
        )
        return if (launch.exitCode == 0) {
            mapOf("state" to STATE_READY, "userId" to userId, "ok" to true)
        } else {
            mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to "${launch.stdout}\n${launch.stderr}".trim(),
            )
        }
    }

    private fun uninstallPackage(binder: IBinder, packageName: String): Map<String, Any?> {
        val cap = capability(binder)
        if (cap["state"] != STATE_READY) return cap
        val userId = cap["userId"] as Int?
            ?: return mapOf("state" to STATE_READY, "ok" to true)
        val uninstall = run(
            binder,
            "uninstall",
            listOf(userId.toString(), packageName),
        )
        return if (uninstall.exitCode == 0 &&
            uninstall.stdout.contains("success", ignoreCase = true)
        ) {
            mapOf("state" to STATE_READY, "userId" to userId, "ok" to true)
        } else {
            mapOf(
                "state" to STATE_OPERATION_FAILED,
                "message" to "${uninstall.stdout}\n${uninstall.stderr}".trim(),
            )
        }
    }

    private fun run(
        binder: IBinder,
        operation: String,
        args: List<String> = emptyList(),
    ): NativeCommandResult {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(CloneProfileUserService.DESCRIPTOR)
            data.writeString(operation)
            data.writeStringList(args)
            if (!binder.transact(
                    CloneProfileUserService.TRANSACTION_EXEC,
                    data,
                    reply,
                    0,
                )
            ) {
                throw IllegalStateException("Privileged clone service rejected the request.")
            }
            reply.readException()
            return NativeCommandResult(
                exitCode = reply.readInt(),
                stdout = reply.readString().orEmpty(),
                stderr = reply.readString().orEmpty(),
            )
        } finally {
            reply.recycle()
            data.recycle()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        var shouldUnbind = false
        val waiters = synchronized(serviceWaiters) {
            if (disposed) {
                emptyList()
            } else {
                disposed = true
                shouldUnbind = true
                binding = false
                serviceBinder = null
                serviceWaiters.toList().also { serviceWaiters.clear() }
            }
        }
        waiters.forEach { it(null) }
        if (shouldUnbind) {
            try {
                Shizuku.unbindUserService(serviceArgs, serviceConnection, true)
            } catch (_: RuntimeException) {
                // Service may already be gone; disposal remains idempotent.
            }
        }
        executor.shutdownNow()
    }

    private data class NativeCommandResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String,
    )

    companion object {
        const val CHANNEL_NAME = "private_vault/clone_profile"
        private const val PREFS = "clone_profile"
        private const val KEY_OWNED_CLONE_USER = "owned_clone_user"
        private const val PERMISSION_REQUEST = 0x4350
        private const val STATE_READY = "ready"
        private const val STATE_PRIVILEGE_REQUIRED = "privilege_required"
        private const val STATE_OEM_UNSUPPORTED = "clone_profile_unsupported_by_oem"
        private const val STATE_CONFLICTING_PROFILE = "conflicting_external_clone_profile"
        private const val STATE_OPERATION_FAILED = "operation_failed"
        private val PACKAGE_REGEX = Regex("""[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+""")
        private val COMPONENT_REGEX =
            Regex("""[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+/[A-Za-z0-9_.$]+""")

        private fun isPackageName(value: String?): Boolean =
            value != null && PACKAGE_REGEX.matches(value)
    }
}

internal object CloneProfileDiscovery {
    enum class State { ready, conflicting, operationFailed }

    data class Result(
        val state: State,
        val userId: Int?,
        val clearOwned: Boolean = false,
        val message: String? = null,
    )

    fun fromListUsers(
        exitCode: Int,
        stdout: String,
        stderr: String,
        ownedUserId: Int,
    ): Result {
        if (exitCode != 0) {
            return Result(
                state = State.operationFailed,
                userId = null,
                message = "$stdout\n$stderr".trim()
                    .ifBlank { "Android user list could not be queried." },
            )
        }
        return resolve(cloneProfileIds(stdout), ownedUserId)
    }

    fun cloneProfileIds(output: String): List<Int> {
        val ids = mutableListOf<Int>()
        var legacyCurrentId: Int? = null
        for (raw in output.lineSequence()) {
            val line = raw.trim()
            val verboseTypeMatch = Regex(
                """(?:^|,\s*)type=(?:android\.os\.usertype\.)?profile\.CLONE(?:,|$)""",
            ).containsMatchIn(line)
            if (verboseTypeMatch) {
                Regex("""(?:^|\s|,)id=(\d+)(?:,|\s|$)""")
                    .find(line)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.toIntOrNull()
                    ?.let(ids::add)
                continue
            }

            Regex("""UserInfo\{(\d+):""")
                .find(line)
                ?.groupValues
                ?.getOrNull(1)
                ?.toIntOrNull()
                ?.let { legacyCurrentId = it }
            if (line.contains("android.os.usertype.profile.CLONE") ||
                line.contains("profile.CLONE")
            ) {
                legacyCurrentId?.let(ids::add)
            }
        }
        return ids.distinct()
    }

    fun resolve(cloneIds: List<Int>, ownedUserId: Int): Result {
        val unique = cloneIds.distinct()
        if (unique.isEmpty()) {
            return Result(
                state = State.ready,
                userId = null,
                clearOwned = ownedUserId >= 0,
            )
        }
        if (unique.size != 1 || ownedUserId < 0 || unique.single() != ownedUserId) {
            return Result(
                state = State.conflicting,
                userId = unique.first(),
            )
        }
        return Result(
            state = State.ready,
            userId = ownedUserId,
        )
    }
}

internal object CloneProfileCreatePolicy {
    enum class FailureState {
        cloneProfileUnsupportedByOem,
        operationFailed,
    }

    fun classifyFailure(stdout: String, stderr: String): FailureState {
        val details = "${stdout}\n${stderr}".lowercase()
        val mentionsCloneType =
            details.contains("android.os.usertype.profile.clone") ||
                details.contains("profile.clone")
        if (!mentionsCloneType) return FailureState.operationFailed

        val explicitlyUnsupported =
            details.contains("unknown user type") ||
                details.contains("unsupported user type") ||
                (
                    details.contains("user type") &&
                        (
                            details.contains("not available") ||
                                details.contains("unavailable") ||
                                details.contains("not supported") ||
                                details.contains("unsupported") ||
                                details.contains("disabled")
                        )
                )
        return if (explicitlyUnsupported) {
            FailureState.cloneProfileUnsupportedByOem
        } else {
            FailureState.operationFailed
        }
    }

    fun verifyCreatedClone(
        createStdout: String,
        postCreateUsers: String,
    ): CloneProfileDiscovery.Result {
        val createdId = Regex("""(?:id\s+|UserInfo\{)(\d+)""")
            .find(createStdout)
            ?.groupValues
            ?.getOrNull(1)
            ?.toIntOrNull()
            ?: return CloneProfileDiscovery.Result(
                state = CloneProfileDiscovery.State.operationFailed,
                userId = null,
                message = "Clone profile was created but Android did not report its user id.",
            )

        val cloneIds = CloneProfileDiscovery.cloneProfileIds(postCreateUsers).distinct()
        if (cloneIds.size != 1) {
            return CloneProfileDiscovery.Result(
                state = if (cloneIds.isEmpty()) {
                    CloneProfileDiscovery.State.operationFailed
                } else {
                    CloneProfileDiscovery.State.conflicting
                },
                userId = cloneIds.firstOrNull(),
                message = if (cloneIds.isEmpty()) {
                    "Clone profile was created but could not be re-discovered."
                } else {
                    "Multiple clone profiles exist after creation; ownership is ambiguous."
                },
            )
        }
        if (cloneIds.single() != createdId) {
            return CloneProfileDiscovery.Result(
                state = CloneProfileDiscovery.State.conflicting,
                userId = cloneIds.single(),
                message = "Created clone identity does not match the discovered clone profile.",
            )
        }
        return CloneProfileDiscovery.Result(
            state = CloneProfileDiscovery.State.ready,
            userId = createdId,
        )
    }
}

internal object CloneProfileStartPolicy {
    fun failureMessage(
        exitCode: Int,
        stdout: String,
        stderr: String,
    ): String? {
        if (exitCode == 0) return null
        return listOf(stderr.trim(), stdout.trim())
            .filter(String::isNotEmpty)
            .joinToString("\n")
            .ifBlank { "Clone profile user could not be started." }
            .take(2048)
    }
}

internal object CloneProfilePackageList {
    data class Result(
        val ok: Boolean,
        val packages: Set<String> = emptySet(),
        val message: String? = null,
    )

    private val packageRegex =
        Regex("""[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+""")

    fun fromCommand(
        exitCode: Int,
        stdout: String,
        stderr: String,
    ): Result {
        if (exitCode != 0) {
            val detail = "$stdout\n$stderr".trim()
                .ifBlank { "Android package list could not be queried." }
                .take(2048)
            return Result(ok = false, message = detail)
        }
        val packages = stdout
            .lineSequence()
            .map { it.removePrefix("package:").trim() }
            .filter(packageRegex::matches)
            .toSet()
        return Result(ok = true, packages = packages)
    }
}
