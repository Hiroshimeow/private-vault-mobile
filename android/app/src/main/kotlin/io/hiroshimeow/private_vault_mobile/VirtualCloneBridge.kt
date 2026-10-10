package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class VirtualCloneBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private data class Slot(val index: Int, val authority: String)
    private data class State(val slot: Slot, val reachable: Boolean, val state: String, val packageName: String?, val instanceId: String?)

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val slots = listOf(
        Slot(0, "io.hiroshimeow.private_vault.clonehost.slot0.control"),
        Slot(1, "io.hiroshimeow.private_vault.clonehost.slot1.control"),
    )

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        executor.execute {
            val response = runCatching { handle(call) }.getOrElse { failure("operation_failed", it.message) }
            activity.runOnUiThread { result.success(response) }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private fun handle(call: MethodCall): Map<String, Any?> = when (call.method) {
        "getCapability" -> capability(states())
        "listApps" -> listApps()
        "clone" -> clone(call.argument("packageName"))
        "launch" -> instanceCall("launch", call.argument("instanceId"))
        "stop" -> instanceCall("stop", call.argument("instanceId"))
        "uninstall" -> instanceCall("remove", call.argument("instanceId"))
        else -> failure("unsupported_operation")
    }

    private fun listApps(): Map<String, Any?> {
        val current = states()
        val cap = capability(current)
        if (cap["state"] != "ready") return cap + ("apps" to emptyList<Any>())
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val excluded = setOf(activity.packageName, SLOT0_PACKAGE, SLOT1_PACKAGE)
        val apps = activity.packageManager.queryIntentActivities(intent, 0)
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName !in excluded }
            .distinctBy { it.packageName }
            .map { app ->
                mapOf(
                    "packageName" to app.packageName,
                    "label" to app.loadLabel(activity.packageManager).toString(),
                    "instances" to current.filter { it.packageName == app.packageName && it.instanceId != null }.map {
                        mapOf("instanceId" to it.instanceId, "slot" to it.slot.index, "state" to it.state)
                    },
                )
            }
        return cap + ("apps" to apps)
    }

    private fun clone(packageName: String?): Map<String, Any?> {
        if (packageName == null || !PACKAGE_PATTERN.matches(packageName)) return failure("invalid_package")
        val before = states()
        val cap = capability(before)
        if (cap["state"] != "ready") return cap + mapOf("ok" to false, "errorCode" to "runner_missing")
        val slot = before.firstOrNull { it.state == "empty" } ?: return cap + mapOf("ok" to false, "errorCode" to "no_free_slot")
        val reply = hostCall(slot.slot, "registerInstalled", Bundle().apply { putString("packageName", packageName) })
            ?: return capability(states()) + mapOf("ok" to false, "errorCode" to "runner_missing")
        return reply.toMap() + capability(states()) + mapOf("ok" to reply.getBoolean("ok"), "slot" to slot.slot.index)
    }

    private fun instanceCall(method: String, instanceId: String?): Map<String, Any?> {
        val slot = when {
            instanceId?.startsWith("slot0:") == true -> slots[0]
            instanceId?.startsWith("slot1:") == true -> slots[1]
            else -> return failure("invalid_instance")
        }
        val reply = hostCall(slot, method, Bundle().apply { putString("instanceId", instanceId) })
            ?: return capability(states()) + mapOf("ok" to false, "errorCode" to "runner_missing")
        return reply.toMap() + capability(states()) + mapOf("ok" to reply.getBoolean("ok"), "slot" to slot.index)
    }

    private fun states(): List<State> = slots.map { slot ->
        val reply = hostCall(slot, "state", null)
        if (reply == null) State(slot, false, "unavailable", null, null)
        else State(slot, true, reply.getString("state") ?: "operation_failed", reply.getString("packageName"), reply.getString("instanceId"))
    }

    private fun capability(states: List<State>): Map<String, Any?> {
        val missing = states.filterNot { it.reachable }.map { it.slot.index }
        return mapOf(
            "state" to if (missing.isEmpty()) "ready" else "runner_missing",
            "message" to missing.takeIf { it.isNotEmpty() }?.let { "Missing clone-host slot(s): ${it.joinToString()}" },
            "slotsAvailable" to states.count { it.reachable && it.state == "empty" },
            "slotsTotal" to slots.size,
        )
    }

    private fun hostCall(slot: Slot, method: String, extras: Bundle?): Bundle? = runCatching {
        activity.contentResolver.call(Uri.parse("content://${slot.authority}"), method, null, extras)
    }.getOrNull()

    private fun failure(code: String, message: String? = null) = mapOf<String, Any?>(
        "ok" to false, "state" to "operation_failed", "errorCode" to code, "message" to message,
        "slotsAvailable" to 0, "slotsTotal" to slots.size,
    )

    private fun Bundle.toMap(): Map<String, Any?> = keySet().associateWith { get(it) }

    companion object {
        const val CHANNEL_NAME = "private_vault/clone_profile"
        private const val SLOT0_PACKAGE = "io.hiroshimeow.private_vault.clonehost.slot0"
        private const val SLOT1_PACKAGE = "io.hiroshimeow.private_vault.clonehost.slot1"
        private val PACKAGE_PATTERN = Regex("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+$")
    }
}
