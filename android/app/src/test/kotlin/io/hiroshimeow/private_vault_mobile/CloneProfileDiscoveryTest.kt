package io.hiroshimeow.private_vault_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloneProfileDiscoveryTest {
    @Test
    fun parsesAospVerboseCloneRecord() {
        val output = """
            0: id=0, name=Owner, type=FULL.SYSTEM, flags=ADMIN|FULL
            1: id=10, name=PrivateVaultClone, type=profile.CLONE, flags=PROFILE (parentId=0)
        """.trimIndent()

        assertEquals(listOf(10), CloneProfileDiscovery.cloneProfileIds(output))
    }

    @Test
    fun parsesFullTypeAndMultipleUsersWithoutFalsePositive() {
        val output = """
            0: id=0, name=Owner, type=FULL.SYSTEM, flags=ADMIN|FULL
            1: id=10, name=Work, type=profile.MANAGED, flags=PROFILE (parentId=0)
            2: id=11, name=Clone, type=android.os.usertype.profile.CLONE, flags=PROFILE (parentId=0)
            3: id=12, name=Secondary, type=FULL.SECONDARY, flags=FULL
        """.trimIndent()

        assertEquals(listOf(11), CloneProfileDiscovery.cloneProfileIds(output))
    }

    @Test
    fun supportsLegacyUserInfoFallback() {
        val output = """
            UserInfo{0:Owner:c13} running
            UserInfo{10:PrivateVaultClone:1000} android.os.usertype.profile.CLONE
        """.trimIndent()

        assertEquals(listOf(10), CloneProfileDiscovery.cloneProfileIds(output))
    }

    @Test
    fun ownedClonePersistsAcrossRefresh() {
        val result = CloneProfileDiscovery.resolve(listOf(10), 10)

        assertEquals(CloneProfileDiscovery.State.ready, result.state)
        assertEquals(10, result.userId)
        assertFalse(result.clearOwned)
    }

    @Test
    fun externalCloneFailsClosed() {
        val result = CloneProfileDiscovery.resolve(listOf(10), -1)

        assertEquals(CloneProfileDiscovery.State.conflicting, result.state)
        assertEquals(10, result.userId)
        assertFalse(result.clearOwned)
    }

    @Test
    fun multipleCloneProfilesFailClosed() {
        val result = CloneProfileDiscovery.resolve(listOf(10, 11), 10)

        assertEquals(CloneProfileDiscovery.State.conflicting, result.state)
        assertFalse(result.clearOwned)
    }

    @Test
    fun failedUserListFailsClosedAndPreservesOwnership() {
        val result = CloneProfileDiscovery.fromListUsers(
            exitCode = 1,
            stdout = "",
            stderr = "permission denied",
            ownedUserId = 10,
        )

        assertEquals(CloneProfileDiscovery.State.operationFailed, result.state)
        assertEquals(null, result.userId)
        assertFalse(result.clearOwned)
        assertTrue(result.message!!.contains("permission denied"))
    }

    @Test
    fun missingCloneClearsStaleOwnershipOnlyAfterSuccessfulDiscovery() {
        val result = CloneProfileDiscovery.fromListUsers(
            exitCode = 0,
            stdout = "0: id=0, name=Owner, type=FULL.SYSTEM, flags=ADMIN",
            stderr = "",
            ownedUserId = 10,
        )

        assertEquals(CloneProfileDiscovery.State.ready, result.state)
        assertEquals(null, result.userId)
        assertTrue(result.clearOwned)
    }

    @Test
    fun failedPackageListFailsClosed() {
        val result = CloneProfilePackageList.fromCommand(
            exitCode = 1,
            stdout = "",
            stderr = "package manager unavailable",
        )

        assertFalse(result.ok)
        assertTrue(result.packages.isEmpty())
        assertTrue(result.message!!.contains("package manager unavailable"))
    }

    @Test
    fun successfulPackageListParsesOnlyValidPackageRows() {
        val result = CloneProfilePackageList.fromCommand(
            exitCode = 0,
            stdout = """
                package:com.example.alpha
                warning: ignored
                package:org.example.beta
            """.trimIndent(),
            stderr = "",
        )

        assertTrue(result.ok)
        assertEquals(
            setOf("com.example.alpha", "org.example.beta"),
            result.packages,
        )
    }

    @Test
    fun explicitCloneTypeUnsupportedIsClassifiedAsOemUnsupported() {
        assertEquals(
            CloneProfileCreatePolicy.FailureState.cloneProfileUnsupportedByOem,
            CloneProfileCreatePolicy.classifyFailure(
                "",
                "User type android.os.usertype.profile.CLONE is not available on this device",
            ),
        )
        assertEquals(
            CloneProfileCreatePolicy.FailureState.cloneProfileUnsupportedByOem,
            CloneProfileCreatePolicy.classifyFailure(
                "",
                "Unknown user type: android.os.usertype.profile.CLONE",
            ),
        )
    }

    @Test
    fun genericCannotAddFailureIsNotMisclassifiedAsOemUnsupported() {
        assertEquals(
            CloneProfileCreatePolicy.FailureState.operationFailed,
            CloneProfileCreatePolicy.classifyFailure(
                "",
                "Error: couldn't create User. Cannot add user. No more users allowed.",
            ),
        )
        assertEquals(
            CloneProfileCreatePolicy.FailureState.operationFailed,
            CloneProfileCreatePolicy.classifyFailure(
                "",
                "Cannot add profile of type android.os.usertype.profile.CLONE due to policy",
            ),
        )
    }

    @Test
    fun createdCloneProofRequiresMatchingCreateIdAndSinglePostCreateClone() {
        val result = CloneProfileCreatePolicy.verifyCreatedClone(
            createStdout = "Success: created user id 10",
            postCreateUsers = """
                0: id=0, name=Owner, type=FULL.SYSTEM, flags=ADMIN|FULL
                1: id=10, name=PrivateVaultClone, type=profile.CLONE, flags=PROFILE (parentId=0)
            """.trimIndent(),
        )

        assertEquals(CloneProfileDiscovery.State.ready, result.state)
        assertEquals(10, result.userId)
    }

    @Test
    fun createdCloneProofRejectsMissingOrMismatchedCreateIdentity() {
        val oneClone = """
            0: id=0, name=Owner, type=FULL.SYSTEM, flags=ADMIN|FULL
            1: id=10, name=PrivateVaultClone, type=profile.CLONE, flags=PROFILE (parentId=0)
        """.trimIndent()

        val missingCreateId = CloneProfileCreatePolicy.verifyCreatedClone(
            createStdout = "Success",
            postCreateUsers = oneClone,
        )
        assertEquals(CloneProfileDiscovery.State.operationFailed, missingCreateId.state)

        val mismatchedCreateId = CloneProfileCreatePolicy.verifyCreatedClone(
            createStdout = "Success: created user id 11",
            postCreateUsers = oneClone,
        )
        assertEquals(CloneProfileDiscovery.State.conflicting, mismatchedCreateId.state)
    }

    @Test
    fun createdCloneProofRejectsMultiplePostCreateCloneProfiles() {
        val result = CloneProfileCreatePolicy.verifyCreatedClone(
            createStdout = "Success: created user id 10",
            postCreateUsers = """
                1: id=10, name=PrivateVaultClone, type=profile.CLONE, flags=PROFILE (parentId=0)
                2: id=11, name=OtherClone, type=profile.CLONE, flags=PROFILE (parentId=0)
            """.trimIndent(),
        )

        assertEquals(CloneProfileDiscovery.State.conflicting, result.state)
    }

    @Test
    fun failedStartUserReturnsBoundedFailureAndSuccessfulStartDoesNot() {
        val huge = "x".repeat(5000)
        val failure = CloneProfileStartPolicy.failureMessage(
            exitCode = 1,
            stdout = huge,
            stderr = "start denied",
        )

        assertTrue(failure != null)
        assertTrue(failure!!.contains("start denied"))
        assertTrue(failure.length <= 2048)
        assertEquals(
            null,
            CloneProfileStartPolicy.failureMessage(
                exitCode = 0,
                stdout = "Success",
                stderr = "",
            ),
        )
    }
}
