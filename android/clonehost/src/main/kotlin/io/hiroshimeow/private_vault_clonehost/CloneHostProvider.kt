package io.hiroshimeow.private_vault_clonehost

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import io.hiroshimeow.private_vault_clonehost.engine.CloneRegistry
import io.hiroshimeow.private_vault_clonehost.runtime.GuestRuntime

class CloneHostProvider : ContentProvider() {
    private lateinit var registry: CloneRegistry
    private lateinit var runtime: GuestRuntime

    override fun onCreate(): Boolean {
        val appContext = context?.applicationContext ?: return false
        registry = CloneRegistry(appContext)
        runtime = GuestRuntime(appContext, registry)
        return true
    }

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        if (method !in CloneHostProtocol.calls) {
            return CloneHostProtocol.result(false, "operation_failed", "unsupported_operation")
        }
        if (arg != null || !CloneHostProtocol.hasExactExtras(method, extras?.keySet().orEmpty())) {
            return CloneHostProtocol.result(false, "operation_failed", "invalid_extras")
        }
        return when (method) {
            CloneHostProtocol.CAPABILITY -> capability()
            CloneHostProtocol.STATE -> state()
            CloneHostProtocol.REGISTER_INSTALLED -> register(extras)
            CloneHostProtocol.LAUNCH -> launch(extras)
            CloneHostProtocol.STOP -> stop(extras)
            CloneHostProtocol.REMOVE -> remove(extras)
            else -> CloneHostProtocol.result(false, "operation_failed", "unsupported_operation")
        }
    }

    private fun capability(): Bundle = CloneHostProtocol.result(true, "ready")

    private fun state(): Bundle {
        val record = registry.current()
        return CloneHostProtocol.result(
            ok = true,
            state = if (record == null) "empty" else record.state,
            packageName = record?.packageName,
            instanceId = record?.instanceId,
        ).apply {
            record?.label?.let { putString("label", it) }
        }
    }

    private fun register(extras: Bundle?): Bundle {
        val packageName = CloneHostProtocol.packageName(extras)
            ?: return CloneHostProtocol.result(false, "operation_failed", "invalid_package")
        val result = registry.registerInstalled(packageName)
        return if (result.ok) {
            CloneHostProtocol.result(true, "ready", packageName = packageName, instanceId = result.record?.instanceId)
        } else {
            CloneHostProtocol.result(false, "operation_failed", result.errorCode ?: "operation_failed")
        }
    }

    private fun launch(extras: Bundle?): Bundle {
        val instanceId = CloneHostProtocol.instanceId(extras)
            ?: return CloneHostProtocol.result(false, "operation_failed", "invalid_instance")
        val preparation = runtime.prepare(instanceId)
        if (!preparation.ok) {
            return CloneHostProtocol.result(false, "operation_failed", preparation.errorCode ?: "launch_failed", preparation.message)
        }
        val appContext = context ?: return CloneHostProtocol.result(false, "operation_failed", "launch_failed")
        val intent = Intent(appContext, GuestContainerActivity::class.java)
            .putExtra(GuestContainerActivity.EXTRA_INSTANCE_ID, instanceId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching {
            appContext.startActivity(intent)
            CloneHostProtocol.result(true, "ready", instanceId = instanceId)
        }.getOrElse {
            CloneHostProtocol.result(false, "operation_failed", "launch_failed", it.message)
        }
    }

    private fun stop(extras: Bundle?): Bundle {
        val instanceId = CloneHostProtocol.instanceId(extras)
            ?: return CloneHostProtocol.result(false, "operation_failed", "invalid_instance")
        val result = runtime.stop(instanceId)
        GuestContainerActivity.finishInstance(instanceId)
        return CloneHostProtocol.result(result.ok, if (result.ok) "ready" else "operation_failed", result.errorCode, result.message, instanceId = instanceId)
    }

    private fun remove(extras: Bundle?): Bundle {
        val instanceId = CloneHostProtocol.instanceId(extras)
            ?: return CloneHostProtocol.result(false, "operation_failed", "invalid_instance")
        runtime.stop(instanceId)
        GuestContainerActivity.finishInstance(instanceId)
        val result = registry.remove(instanceId)
        return CloneHostProtocol.result(result.ok, if (result.ok) "empty" else "operation_failed", result.errorCode, instanceId = instanceId)
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
