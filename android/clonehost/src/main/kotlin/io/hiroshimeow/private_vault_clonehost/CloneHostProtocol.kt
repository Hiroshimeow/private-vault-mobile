package io.hiroshimeow.private_vault_clonehost

import android.os.Bundle

internal object CloneHostProtocol {
    const val PERMISSION = "io.hiroshimeow.private_vault.permission.CLONE_CONTROL"
    const val CAPABILITY = "capability"
    const val STATE = "state"
    const val REGISTER_INSTALLED = "registerInstalled"
    const val LAUNCH = "launch"
    const val STOP = "stop"
    const val REMOVE = "remove"

    val calls = setOf(CAPABILITY, STATE, REGISTER_INSTALLED, LAUNCH, STOP, REMOVE)

    fun allowedExtraKeys(method: String): Set<String>? = when (method) {
        CAPABILITY, STATE -> emptySet()
        REGISTER_INSTALLED -> setOf("packageName")
        LAUNCH, STOP, REMOVE -> setOf("instanceId")
        else -> null
    }

    fun hasExactExtras(method: String, keys: Set<String>): Boolean = allowedExtraKeys(method) == keys

    private val packagePattern = Regex("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+$")
    private val instancePattern = Regex("^slot[01]:[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+$")

    fun packageName(extras: Bundle?): String? = extras?.getString("packageName")
        ?.takeIf { packagePattern.matches(it) }

    fun instanceId(extras: Bundle?): String? = extras?.getString("instanceId")
        ?.takeIf { instancePattern.matches(it) }

    fun result(
        ok: Boolean,
        state: String,
        errorCode: String? = null,
        message: String? = null,
        packageName: String? = null,
        instanceId: String? = null,
    ) = Bundle().apply {
        putBoolean("ok", ok)
        putString("state", state)
        errorCode?.let { putString("errorCode", it) }
        message?.let { putString("message", it) }
        packageName?.let { putString("packageName", it) }
        instanceId?.let { putString("instanceId", it) }
        putInt("slot", BuildConfig.CLONE_SLOT)
    }
}
