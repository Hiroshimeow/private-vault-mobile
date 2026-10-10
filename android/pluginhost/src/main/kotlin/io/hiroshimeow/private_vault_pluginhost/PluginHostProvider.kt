package io.hiroshimeow.private_vault_pluginhost

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle

class PluginHostProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        val context = requireNotNull(context)
        val registry = PluginRegistry(context)
        val result = when (method) {
            "status" -> registry.status()
            "register" -> arg?.let(registry::register)
                ?: mapOf("state" to PluginResult.PACKAGE_UNREADABLE.wire, "ok" to false, "message" to "missing package")
            "remove" -> registry.remove()
            "launch" -> {
                val current = registry.currentArtifact()
                if (current == null) {
                    mapOf("state" to PluginResult.LAUNCH_FAILED.wire, "ok" to false, "message" to "slot is empty")
                } else {
                    runCatching {
                        context.startActivity(Intent(context, PluginContainerActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }.fold(
                        onSuccess = { mapOf("state" to PluginResult.READY.wire, "ok" to true, "packageName" to current.second.sourcePackage) },
                        onFailure = { mapOf("state" to PluginResult.LAUNCH_FAILED.wire, "ok" to false, "message" to (it.message ?: "launch failed")) },
                    )
                }
            }
            else -> mapOf("state" to PluginResult.OPERATION_FAILED.wire, "ok" to false, "message" to "unsupported operation")
        }
        return Bundle().apply { result.forEach { (key, value) -> when (value) {
            is Boolean -> putBoolean(key, value)
            is String -> putString(key, value)
            is Int -> putInt(key, value)
            is Long -> putLong(key, value)
            null -> Unit
            else -> putString(key, value.toString())
        } } }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
