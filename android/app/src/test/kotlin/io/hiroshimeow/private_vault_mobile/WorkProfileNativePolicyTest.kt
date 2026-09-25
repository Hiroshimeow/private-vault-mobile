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
    fun `short bridge operations fail quickly while user confirmation stays long`() {
        assertEquals(
            5_000L,
            WorkProfileNativePolicy.bridgeTimeoutMs(
                WorkProfileProtocol.ACTION_LIST_WORK_APPS,
            ),
        )
        assertEquals(
            5 * 60 * 1_000L,
            WorkProfileNativePolicy.bridgeTimeoutMs(WorkProfileProtocol.ACTION_CLONE),
        )
        assertEquals(
            5 * 60 * 1_000L,
            WorkProfileNativePolicy.bridgeTimeoutMs(
                WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT,
            ),
        )
        assertEquals(
            NativeWorkProfileErrorCode.BRIDGE_TIMEOUT,
            WorkProfileNativePolicy.bridgeTimeoutError(
                WorkProfileProtocol.ACTION_LAUNCH,
            ),
        )
        assertEquals(
            NativeWorkProfileErrorCode.USER_ACTION_REQUIRED,
            WorkProfileNativePolicy.bridgeTimeoutError(
                WorkProfileProtocol.ACTION_UNINSTALL,
            ),
        )
        assertEquals(
            NativeWorkProfileErrorCode.USER_ACTION_REQUIRED,
            WorkProfileNativePolicy.bridgeTimeoutError(
                WorkProfileProtocol.ACTION_PICK_WORK_DOCUMENT,
            ),
        )
    }

    @Test
    fun `launch package polling is bounded`() {
        assertEquals(true, WorkProfileNativePolicy.shouldContinuePolling(2_900, 3_000))
        assertEquals(false, WorkProfileNativePolicy.shouldContinuePolling(3_000, 3_000))
        assertEquals(false, WorkProfileNativePolicy.shouldContinuePolling(3_500, 3_000))
    }

    @Test
    fun `authenticated quiet profile is distinct from conflicting profile`() {
        assertEquals(
            NativeWorkProfileState.QUIET,
            WorkProfileNativePolicy.capabilityState(
                supported = true,
                profileOwner = false,
                bridgeResolvable = false,
                hasControlToken = true,
                provisioningAllowed = false,
                profileCount = 2,
                profileQuiet = true,
            ),
        )
    }

    @Test
    fun `quiet recovery calls direct API only when available and authorized`() {
        assertEquals(false, WorkProfileNativePolicy.shouldRequestQuietModeDirectly(27, true))
        assertEquals(false, WorkProfileNativePolicy.shouldRequestQuietModeDirectly(28, false))
        assertEquals(true, WorkProfileNativePolicy.shouldRequestQuietModeDirectly(28, true))
    }

    @Test
    fun `aggregate app payload budget drops excess icons`() {
        val budgetBytes = 256 * 1024
        val metadataBytes = 8 * 1024
        val iconDeltas = List(12) { 87_384 }

        val included = WorkProfileNativePolicy.iconInclusionMask(
            metadataPayloadBytes = metadataBytes,
            iconPayloadDeltas = iconDeltas,
            maxPayloadBytes = budgetBytes,
        )
        val finalBytes = metadataBytes + iconDeltas.zip(included).sumOf { (delta, keep) ->
            if (keep) delta else 0
        }

        assertEquals(iconDeltas.size, included.size)
        assertEquals(true, included.any { it })
        assertEquals(true, included.any { !it })
        assertEquals(true, finalBytes <= budgetBytes)
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
                profileQuiet = false,
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
                profileQuiet = false,
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
                profileQuiet = false,
            ),
        )
    }
}
