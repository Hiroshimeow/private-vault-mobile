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
}
