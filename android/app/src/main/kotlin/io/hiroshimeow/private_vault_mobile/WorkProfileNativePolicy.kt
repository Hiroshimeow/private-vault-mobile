package io.hiroshimeow.private_vault_mobile

import android.content.pm.PackageInstaller

internal object WorkProfileNativePolicy {
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

    fun capabilityState(
        supported: Boolean,
        profileOwner: Boolean,
        bridgeResolvable: Boolean,
        hasControlToken: Boolean,
        provisioningAllowed: Boolean,
        profileCount: Int,
    ): NativeWorkProfileState {
        if (!supported) return NativeWorkProfileState.UNSUPPORTED
        if (profileOwner || (bridgeResolvable && hasControlToken)) {
            return NativeWorkProfileState.READY
        }
        if (provisioningAllowed) return NativeWorkProfileState.ABSENT
        return if (profileCount > 1) {
            NativeWorkProfileState.CONFLICTING_PROFILE
        } else {
            NativeWorkProfileState.POLICY_DENIED
        }
    }
}
