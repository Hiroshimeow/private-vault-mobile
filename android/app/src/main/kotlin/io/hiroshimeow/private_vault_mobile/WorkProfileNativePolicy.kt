package io.hiroshimeow.private_vault_mobile

import android.content.pm.PackageInstaller

internal object WorkProfileNativePolicy {
    const val FAST_BRIDGE_TIMEOUT_MS = 5_000L
    const val USER_CONFIRMATION_TIMEOUT_MS = 5 * 60 * 1_000L
    const val PACKAGE_STATE_TIMEOUT_MS = 3_000L
    const val PACKAGE_STATE_POLL_MS = 100L

    fun apkSourcePaths(baseSource: String, splitSources: Array<String>?): List<String> =
        buildList {
            add(baseSource)
            splitSources?.forEach { add(it) }
        }

    fun installerFailureCode(status: Int): NativeWorkProfileErrorCode =
        when (status) {
            PackageInstaller.STATUS_FAILURE_BLOCKED ->
                NativeWorkProfileErrorCode.STORE_FALLBACK_REQUIRED
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                NativeWorkProfileErrorCode.USER_ACTION_REQUIRED
            PackageInstaller.STATUS_FAILURE_INVALID,
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE,
            -> NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE
            else -> NativeWorkProfileErrorCode.INSTALLER_FAILURE
        }

    fun bridgeTimeoutMs(action: String?): Long =
        when (action) {
            WorkProfileProtocol.ACTION_CLONE,
            WorkProfileProtocol.ACTION_UNINSTALL,
            WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT,
            -> USER_CONFIRMATION_TIMEOUT_MS
            else -> FAST_BRIDGE_TIMEOUT_MS
        }

    fun bridgeTimeoutError(action: String?): NativeWorkProfileErrorCode =
        when (action) {
            WorkProfileProtocol.ACTION_CLONE,
            WorkProfileProtocol.ACTION_UNINSTALL,
            WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT,
            -> NativeWorkProfileErrorCode.USER_ACTION_REQUIRED
            else -> NativeWorkProfileErrorCode.BRIDGE_TIMEOUT
        }

    fun shouldContinuePolling(elapsedMs: Long, timeoutMs: Long): Boolean =
        elapsedMs < timeoutMs

    fun shouldRequestQuietModeDirectly(sdkInt: Int, authorizedCaller: Boolean): Boolean =
        sdkInt >= 28 && authorizedCaller

    fun iconInclusionMask(
        metadataPayloadBytes: Int,
        iconPayloadDeltas: List<Int>,
        maxPayloadBytes: Int,
    ): List<Boolean> {
        var payloadBytes = metadataPayloadBytes
        return iconPayloadDeltas.map { delta ->
            if (delta > 0 && payloadBytes + delta <= maxPayloadBytes) {
                payloadBytes += delta
                true
            } else {
                false
            }
        }
    }

    fun capabilityState(
        supported: Boolean,
        profileOwner: Boolean,
        bridgeResolvable: Boolean,
        hasControlToken: Boolean,
        provisioningAllowed: Boolean,
        profileCount: Int,
        profileQuiet: Boolean,
    ): NativeWorkProfileState {
        if (!supported) return NativeWorkProfileState.UNSUPPORTED
        if (profileOwner) return NativeWorkProfileState.READY
        if (hasControlToken && profileQuiet) return NativeWorkProfileState.QUIET
        if (bridgeResolvable && hasControlToken) return NativeWorkProfileState.READY
        if (provisioningAllowed) return NativeWorkProfileState.ABSENT
        return if (profileCount > 1) {
            NativeWorkProfileState.CONFLICTING_PROFILE
        } else {
            NativeWorkProfileState.POLICY_DENIED
        }
    }
}
