package io.hiroshimeow.private_vault_mobile

import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class StandaloneClonePolicyTest {
    @Test
    fun cloneIdentityIsStableAndSignerSpecific() {
        val first = StandaloneClonePolicy.deriveClonePackage(
            "com.example.demo",
            "AA:BB:CC",
        )
        val same = StandaloneClonePolicy.deriveClonePackage(
            "com.example.demo",
            "aa:bb:cc",
        )
        val otherSigner = StandaloneClonePolicy.deriveClonePackage(
            "com.example.demo",
            "11:22:33",
        )

        assertEquals(first, same)
        assertNotEquals(first, otherSigner)
        assertTrue(first.matches(Regex("com\\.example\\.demo\\.pvclone\\.c[0-9a-f]{12}")))

        val alias = StandaloneClonePolicy.deriveSigningAlias(
            "com.example.demo",
            "AA:BB:CC",
        )
        assertTrue(alias.matches(Regex("private_vault_clone_lab_[0-9a-f]{24}")))
        assertEquals(
            alias,
            StandaloneClonePolicy.deriveSigningAlias("com.example.demo", "aa:bb:cc"),
        )
    }

    @Test
    fun excessivelyLongPackageUsesSafeFallback() {
        val source = (1..80).joinToString(".") { "segment$it" }

        val clone = StandaloneClonePolicy.deriveClonePackage(source, "abc123")

        assertTrue(clone.matches(Regex("io\\.hiroshimeow\\.pvclone\\.c[0-9a-f]{24}")))
        assertTrue(clone.length <= 255)
    }

    @Test
    fun componentNamesStayAnchoredToSourceCodeNamespace() {
        assertEquals(
            "com.example.demo.MainActivity",
            StandaloneClonePolicy.expandComponentName("com.example.demo", ".MainActivity"),
        )
        assertEquals(
            "com.example.demo.MainActivity",
            StandaloneClonePolicy.expandComponentName("com.example.demo", "MainActivity"),
        )
        assertEquals(
            "org.vendor.Component",
            StandaloneClonePolicy.expandComponentName("com.example.demo", "org.vendor.Component"),
        )
    }

    @Test
    fun onlyPackageDerivedGlobalNamesAreRewritten() {
        val source = "com.example.demo"
        val clone = "com.example.demo.pvclone.c123456789abc"

        assertEquals(
            clone,
            StandaloneClonePolicy.rewritePackageDerivedName(source, clone, source),
        )
        assertEquals(
            "$clone.provider",
            StandaloneClonePolicy.rewritePackageDerivedName(source, clone, "$source.provider"),
        )
        assertNull(
            StandaloneClonePolicy.rewritePackageDerivedName(source, clone, "org.shared.provider"),
        )
    }

    @Test
    fun installedOwnershipRequiresExactlyOneMatchingCurrentSigner() {
        val expected = "aa".repeat(32)
        val other = "00".repeat(32)
        assertTrue(
            StandaloneClonePolicy.matchesExpectedSingleSigner(
                expected,
                listOf(expected.uppercase()),
            ),
        )
        assertFalse(StandaloneClonePolicy.matchesExpectedSingleSigner(expected, emptyList()))
        assertFalse(
            StandaloneClonePolicy.matchesExpectedSingleSigner(
                expected,
                listOf(other),
            ),
        )
        assertFalse(
            StandaloneClonePolicy.matchesExpectedSingleSigner(
                expected,
                listOf(expected, other),
            ),
        )
    }

    @Test
    fun uninstallCleanupIdentityDoesNotCrossRegistryGuard() {
        val record = StandaloneCloneRecord(
            cloneId = "clone-a",
            sourcePackage = "com.example.demo",
            sourceSignerSha256 = "11".repeat(32),
            clonePackage = "com.example.demo.pvclone.c123456789abc",
            signingAlias = "private_vault_clone_lab_1234567890abcdef12345678",
            cloneSignerSha256 = "22".repeat(32),
            artifactRelativePath = "clone-a/base.apk",
            versionCode = 1,
            versionName = "1.0",
            compatibilityWarnings = emptyList(),
            createdAtMs = 1L,
            updatedAtMs = 2L,
            installStatus = "installed",
        )

        assertTrue(record.matchesOwnershipIdentity(record.copy(updatedAtMs = 3L, installStatus = "uninstall_requested")))
        assertFalse(record.matchesOwnershipIdentity(record.copy(cloneId = "clone-b")))
        assertFalse(record.matchesOwnershipIdentity(record.copy(clonePackage = "com.attacker.foreign")))
        assertFalse(record.matchesOwnershipIdentity(record.copy(cloneSignerSha256 = "33".repeat(32))))
    }

    @Test
    fun confirmedCleanupPreservesArtifactWhenRegistryFinalizationFails() {
        var artifactDeleteAttempts = 0

        val error = assertThrows(IllegalStateException::class.java) {
            commitConfirmedUninstallCleanup(
                persistRegistryRemoval = { error("injected registry finalization failure") },
                deleteArtifact = {
                    artifactDeleteAttempts += 1
                    true
                },
            )
        }

        assertEquals("injected registry finalization failure", error.message)
        assertEquals(0, artifactDeleteAttempts)
    }

    @Test
    fun registryFinalizationFailureLeavesExistingRegistryUntouched() {
        val root = Files.createTempDirectory("clone-registry-finalize-test").toFile()
        val registry = File(root, "registry.json").apply { writeText("old") }
        val temp = File(root, "registry.json.tmp").apply { writeText("new") }

        val error = assertThrows(IOException::class.java) {
            finalizeCloneRegistryFile(temp, registry) { _, _ ->
                throw IOException("injected rename failure")
            }
        }

        assertEquals("injected rename failure", error.message)
        assertEquals("old", registry.readText())
        assertEquals("new", temp.readText())
        root.deleteRecursively()
    }

    @Test
    fun confirmedCleanupTreatsPostCommitArtifactDeleteFailureAsMaintenance() {
        var registryCommitted = false

        val artifactDeleted = commitConfirmedUninstallCleanup(
            persistRegistryRemoval = { registryCommitted = true },
            deleteArtifact = { false },
        )

        assertTrue(registryCommitted)
        assertFalse(artifactDeleted)
    }

    @Test
    fun benignMonolithicArchiveIsSupported() {
        val result = StandaloneClonePolicy.classifyArchive(
            entries = listOf("AndroidManifest.xml", "classes.dex", "resources.arsc"),
            manifestFacts = StandaloneCloneManifestFacts(),
        )

        assertTrue(result.supported)
        assertTrue(result.blockers.isEmpty())
    }

    @Test
    fun nativeLibrariesAndSplitMetadataAreRejected() {
        val native = StandaloneClonePolicy.classifyArchive(
            entries = listOf("AndroidManifest.xml", "lib/arm64-v8a/libdemo.so"),
            manifestFacts = StandaloneCloneManifestFacts(),
        )
        val split = StandaloneClonePolicy.classifyArchive(
            entries = listOf("AndroidManifest.xml", "classes.dex"),
            manifestFacts = StandaloneCloneManifestFacts(hasSplitMetadata = true),
        )

        assertEquals(listOf("native_libs_unsupported"), native.blockers)
        assertEquals(listOf("split_apk_unsupported"), split.blockers)
    }

    @Test
    fun identityAndGlobalNameRisksFailClosed() {
        val facts = StandaloneCloneManifestFacts(
            hasSharedUserId = true,
            hasUnsafeProviderAuthority = true,
            hasUnsafeAbsoluteProcess = true,
            hasUnsafeTaskAffinity = true,
            hasVerifiedAppLink = true,
            hasGoogleIdentityBinding = true,
            hasSignatureBoundPermission = true,
            hasHardcodedApplicationId = true,
        )

        val result = StandaloneClonePolicy.classifyArchive(
            entries = listOf("AndroidManifest.xml", "classes.dex"),
            manifestFacts = facts,
        )

        assertFalse(result.supported)
        assertEquals(
            listOf(
                "shared_uid_unsupported",
                "provider_authority_unsupported",
                "absolute_process_unsupported",
                "task_affinity_unsupported",
                "verified_app_link_unsupported",
                "google_identity_bound_unsupported",
                "signature_permission_unsupported",
                "hardcoded_application_id_unsupported",
            ),
            result.blockers,
        )
    }
}
