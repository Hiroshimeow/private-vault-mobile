package io.hiroshimeow.private_vault_mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CloneProfileBridge(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            val value = runCatching {
                when (call.method) {
                    "getCapability" -> capability()
                    "listApps" -> listApps()
                    "clone" -> {
                        val packageName = call.argument<String>("packageName")
                        val slot = call.argument<Int>("slot")
                        if (!isPackageName(packageName) || slot == null || slot !in 0..1) invalid("invalid package or slot")
                        else registerIntoSlot(slot, packageName!!)
                    }
                    "launch" -> {
                        val packageName = call.argument<String>("packageName")
                        val slot = call.argument<Int>("slot")
                        if (!isPackageName(packageName) || slot == null || slot !in 0..1) invalid("invalid package or slot")
                        else verifiedSlotCall(slot, packageName!!, "launch")
                    }
                    "uninstall" -> {
                        val slot = call.argument<Int>("slot")
                        if (slot == null || slot !in 0..1) invalid("invalid slot") else helperCall(slot, "remove", null)
                    }
                    else -> null
                }
            }.getOrElse { error ->
                mapOf("state" to STATE_OPERATION_FAILED, "ok" to false, "message" to (error.message ?: "clone operation failed"))
            }
            if (call.method in SUPPORTED_METHODS) result.success(value) else result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun capability(): Map<String, Any?> {
        val slots = slotStatuses()
        if (slots.any { it["state"] == STATE_HELPER_MISSING }) {
            return mapOf(
                "state" to STATE_HELPER_MISSING,
                "message" to "Both fixed plugin helper slots must be installed with the same signing identity as Private Vault.",
                "slots" to slots,
            )
        }
        return mapOf("state" to STATE_READY, "slots" to slots)
    }

    private fun listApps(): Map<String, Any?> {
        val cap = capability()
        if (cap["state"] != STATE_READY) return cap
        val slots = cap["slots"] as List<Map<String, Any?>>
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val excluded = setOf(activity.packageName, PLUGIN_HOST_SLOT0, PLUGIN_HOST_SLOT1)
        val seen = mutableSetOf<String>()
        val apps = activity.packageManager.queryIntentActivities(launcher, 0)
            .mapNotNull { info ->
                val packageName = info.activityInfo.packageName
                if (packageName in excluded || !seen.add(packageName)) return@mapNotNull null
                val instanceSlots = slots.filter { it["packageName"] == packageName }.mapNotNull { it["slot"] as? Int }
                mapOf(
                    "packageName" to packageName,
                    "label" to info.loadLabel(activity.packageManager).toString(),
                    "slots" to instanceSlots,
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
        return mapOf("state" to STATE_READY, "slots" to slots, "apps" to apps)
    }

    private fun slotStatuses(): List<Map<String, Any?>> = (0..1).map { slot ->
        val response = helperCall(slot, "status", null)
        response + mapOf("slot" to slot)
    }

    private fun registerIntoSlot(slot: Int, packageName: String): Map<String, Any?> {
        val status = helperCall(slot, "status", null)
        if (status["state"] != STATE_READY) return status
        val occupied = status["occupied"] == true
        val existing = status["packageName"] as? String
        if (occupied && existing != packageName) {
            return mapOf("state" to STATE_NO_FREE_SLOT, "ok" to false, "message" to "slot ${slot + 1} is already occupied")
        }
        return helperCall(slot, "register", packageName)
    }

    private fun verifiedSlotCall(slot: Int, packageName: String, method: String): Map<String, Any?> {
        val status = helperCall(slot, "status", null)
        if (status["state"] != STATE_READY || status["packageName"] != packageName) {
            return mapOf("state" to STATE_LAUNCH_FAILED, "ok" to false, "message" to "slot does not contain requested package")
        }
        return helperCall(slot, method, null)
    }

    private fun helperCall(slot: Int, method: String, arg: String?): Map<String, Any?> {
        val host = if (slot == 0) PLUGIN_HOST_SLOT0 else PLUGIN_HOST_SLOT1
        return try {
            val bundle = activity.contentResolver.call(Uri.parse("content://$host.control"), method, arg, null)
                ?: return mapOf("state" to STATE_OPERATION_FAILED, "ok" to false, "message" to "empty helper response")
            bundle.toMap()
        } catch (_: IllegalArgumentException) {
            mapOf("state" to STATE_HELPER_MISSING, "ok" to false, "message" to "plugin helper slot $slot is not installed")
        } catch (_: SecurityException) {
            mapOf("state" to STATE_HELPER_MISSING, "ok" to false, "message" to "plugin helper slot $slot signing permission mismatch")
        }
    }

    private fun Bundle.toMap(): Map<String, Any?> = keySet().associateWith { key -> get(key) }
    private fun invalid(message: String): Map<String, Any?> =
        mapOf("state" to STATE_OPERATION_FAILED, "ok" to false, "message" to message)

    private fun isPackageName(value: String?): Boolean =
        value != null && PACKAGE_NAME.matches(value)

    companion object {
        private const val CHANNEL_NAME = "private_vault/clone_profile"
        const val PLUGIN_HOST_SLOT0 = "io.hiroshimeow.private_vault.pluginhost.slot0"
        const val PLUGIN_HOST_SLOT1 = "io.hiroshimeow.private_vault.pluginhost.slot1"
        private const val STATE_READY = "ready"
        private const val STATE_HELPER_MISSING = "helper_missing"
        private const val STATE_NO_FREE_SLOT = "no_free_slot"
        private const val STATE_LAUNCH_FAILED = "launch_failed"
        private const val STATE_OPERATION_FAILED = "operation_failed"
        private val PACKAGE_NAME = Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+")
        private val SUPPORTED_METHODS = setOf("getCapability", "listApps", "clone", "launch", "uninstall")
    }
}
