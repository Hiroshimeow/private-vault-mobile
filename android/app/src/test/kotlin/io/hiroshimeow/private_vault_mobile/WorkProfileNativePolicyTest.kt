package io.hiroshimeow.private_vault_mobile

import android.content.pm.PackageInstaller
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkProfileNativePolicyTest {
    @Test
    fun `base apk is first and all splits are preserved`() {
        assertEquals(
            listOf("/apps/base.apk", "/apps/config.en.apk", "/apps/config.arm64.apk"),
            WorkProfileNativePolicy.apkSourcePaths(
                "/apps/base.apk",
                arrayOf("/apps/config.en.apk", "/apps/config.arm64.apk"),
            ),
        )
    }

    @Test
    fun `blocked installer result requires store fallback`() {
        assertEquals(
            NativeWorkProfileErrorCode.STORE_FALLBACK_REQUIRED,
            WorkProfileNativePolicy.installerFailureCode(
                PackageInstaller.STATUS_FAILURE_BLOCKED,
            ),
        )
    }

    @Test
    fun `invalid and incompatible installer results are package ineligible`() {
        assertEquals(
            NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
            WorkProfileNativePolicy.installerFailureCode(
                PackageInstaller.STATUS_FAILURE_INVALID,
            ),
        )
        assertEquals(
            NativeWorkProfileErrorCode.PACKAGE_INELIGIBLE,
            WorkProfileNativePolicy.installerFailureCode(
                PackageInstaller.STATUS_FAILURE_INCOMPATIBLE,
            ),
        )
    }

    @Test
    fun `cancelled installer result requires user action`() {
        assertEquals(
            NativeWorkProfileErrorCode.USER_ACTION_REQUIRED,
            WorkProfileNativePolicy.installerFailureCode(
                PackageInstaller.STATUS_FAILURE_ABORTED,
            ),
        )
    }

    @Test
    fun `ready state requires owner or authenticated reachable bridge`() {
        assertEquals(
            NativeWorkProfileState.READY,
            WorkProfileNativePolicy.capabilityState(
                supported = true,
                profileOwner = true,
                bridgeResolvable = false,
                hasControlToken = false,
                provisioningAllowed = false,
                profileCount = 1,
            ),
        )
        assertEquals(
            NativeWorkProfileState.READY,
            WorkProfileNativePolicy.capabilityState(
                supported = true,
                profileOwner = false,
                bridgeResolvable = true,
                hasControlToken = true,
                provisioningAllowed = false,
                profileCount = 2,
            ),
        )
        assertEquals(
            NativeWorkProfileState.CONFLICTING_PROFILE,
            WorkProfileNativePolicy.capabilityState(
                supported = true,
                profileOwner = false,
                bridgeResolvable = true,
                hasControlToken = false,
                provisioningAllowed = false,
                profileCount = 2,
            ),
        )
    }
}
