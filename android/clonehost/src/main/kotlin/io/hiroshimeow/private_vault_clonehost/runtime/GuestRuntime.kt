package io.hiroshimeow.private_vault_clonehost.runtime

import android.app.Activity
import android.app.Application
import android.content.Context
import io.hiroshimeow.private_vault_clonehost.engine.CloneRecord
import io.hiroshimeow.private_vault_clonehost.engine.CloneRegistry

internal data class RuntimeResult(
    val ok: Boolean,
    val errorCode: String? = null,
    val message: String? = null,
)

internal class GuestRuntime(
    private val context: Context,
    private val registry: CloneRegistry,
) {
    private data class PreparedGuest(
        val record: CloneRecord,
        val loaded: LoadedGuest,
        val environment: GuestEnvironment,
        val application: Application,
    )

    private var prepared: PreparedGuest? = null

    fun prepare(instanceId: String): RuntimeResult {
        val record = registry.current()
            ?: return RuntimeResult(false, "instance_not_found")
        if (record.instanceId != instanceId) return RuntimeResult(false, "instance_not_found")
        val files = registry.imageFiles(record)
        if (files.isEmpty() || files.any { !it.isFile }) return RuntimeResult(false, "package_unreadable")
        prepared?.takeIf { it.record.instanceId == instanceId }?.let { return RuntimeResult(true) }

        val loaded = GuestClassLoader.create(context, instanceId, files).getOrElse {
            return RuntimeResult(false, "launch_failed", it.message)
        }
        val environment = GuestResources.create(
            host = context,
            packageName = record.packageName,
            apkFiles = files,
            classLoader = loaded.classLoader,
            nativeDir = loaded.nativeDir,
        ).getOrElse {
            return RuntimeResult(false, "launch_failed", it.message)
        }
        val application = GuestApplicationBootstrap.create(
            environment.context,
            loaded.classLoader,
            record.applicationClass,
        ).getOrElse {
            return RuntimeResult(false, "launch_failed", it.message)
        }
        GuestProviderBootstrap.create(
            environment.context,
            loaded.classLoader,
            files.first(),
            files.drop(1),
            record.packageName,
        ).getOrElse {
            return RuntimeResult(false, "unsupported_provider", it.message)
        }
        prepared = PreparedGuest(record, loaded, environment, application)
        return RuntimeResult(true)
    }

    fun launchInto(container: Activity, instanceId: String): RuntimeResult {
        val preparation = prepare(instanceId)
        if (!preparation.ok) return preparation
        val guest = prepared ?: return RuntimeResult(false, "launch_failed")
        val files = registry.imageFiles(guest.record)
        GuestActivityHook.launch(
            container = container,
            record = guest.record,
            environment = guest.environment,
            classLoader = guest.loaded.classLoader,
            application = guest.application,
            baseApk = files.first(),
            splitApks = files.drop(1),
        ).getOrElse {
            return RuntimeResult(false, "launch_failed", it.message)
        }
        return RuntimeResult(true)
    }

    fun stop(instanceId: String): RuntimeResult {
        val current = registry.current() ?: return RuntimeResult(false, "instance_not_found")
        if (current.instanceId != instanceId) return RuntimeResult(false, "instance_not_found")
        prepared = null
        return RuntimeResult(true)
    }
}
