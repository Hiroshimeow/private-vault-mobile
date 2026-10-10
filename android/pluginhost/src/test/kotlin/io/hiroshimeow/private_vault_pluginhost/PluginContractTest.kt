package io.hiroshimeow.private_vault_pluginhost

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.jf.dexlib2.immutable.reference.ImmutableFieldReference
import org.jf.dexlib2.immutable.reference.ImmutableMethodReference
import org.junit.Test
import java.io.File

class PluginContractTest {
    @Test
    fun metadata_roundTrip_preservesSourceEvidence() {
        val metadata = GuestArtifactMetadata(
            sourcePackage = "io.example.fixture",
            versionCode = 42,
            versionName = "4.2",
            sourceSignerDigests = listOf("aa", "bb"),
            sourceApkSha256 = linkedMapOf("base.apk" to "11", "split_config.en.apk" to "22"),
            launcherClass = "io.example.fixture.MainActivity",
            applicationClass = "io.example.fixture.FixtureApplication",
            transformSchemaVersion = TRANSFORM_SCHEMA_VERSION,
        )
        val file = File.createTempFile("plugin-metadata", ".properties")
        try {
            metadata.writeTo(file)
            assertEquals(metadata, GuestArtifactMetadata.readFrom(file))
        } finally {
            file.delete()
        }
    }

    @Test
    fun sourceHash_isStableAndDetectsMutation() {
        val file = File.createTempFile("plugin-source", ".apk")
        try {
            file.writeText("fixture-a")
            val first = ApkSource.sha256(file)
            assertEquals(first, ApkSource.sha256(file))
            file.writeText("fixture-b")
            assertFalse(first == ApkSource.sha256(file))
        } finally {
            file.delete()
        }
    }

    @Test
    fun updatePolicy_rejectsSignerChange_andAllowsSameSigner() {
        val current = listOf("aabb")
        assertTrue(PluginUpdatePolicy.sameSigner(current, listOf("aabb")))
        assertFalse(PluginUpdatePolicy.sameSigner(current, listOf("ccdd")))
    }

    @Test
    fun transformPolicy_hasStableTypedFailures() {
        assertEquals("unsupported_provider", PluginResult.UNSUPPORTED_PROVIDER.wire)
        assertEquals("unsupported_service", PluginResult.UNSUPPORTED_SERVICE.wire)
        assertEquals("unsupported_receiver", PluginResult.UNSUPPORTED_RECEIVER.wire)
        assertEquals("unsupported_multiprocess", PluginResult.UNSUPPORTED_MULTIPROCESS.wire)
        assertEquals("unsupported_split_code", PluginResult.UNSUPPORTED_SPLIT_CODE.wire)
        assertEquals("source_signer_changed", PluginResult.SOURCE_SIGNER_CHANGED.wire)
    }

    @Test
    fun transformPreflight_acceptsImplementedActivitySurface() {
        GuestCompatibilityValidator.validateMethod(
            ImmutableMethodReference(
                "Landroid/app/Activity;",
                "setTitle",
                listOf("Ljava/lang/CharSequence;"),
                "V",
            ),
        )
    }

    @Test
    fun transformPreflight_rejectsRewrittenFrameworkFields() {
        for (owner in listOf("Landroid/app/Activity;", "Landroid/app/Application;")) {
            val unsupportedField = runCatching {
                GuestCompatibilityValidator.validateField(
                    ImmutableFieldReference(owner, "unsupportedField", "I"),
                )
            }.exceptionOrNull() as PluginTypedException
            assertEquals(PluginResult.TRANSFORM_UNSUPPORTED, unsupportedField.result)
        }
    }

    @Test
    fun transformPreflight_rejectsUnsupportedActivityAndResourceShapes() {
        val unsupportedApi = runCatching {
            GuestCompatibilityValidator.validateMethod(
                ImmutableMethodReference(
                    "Landroid/app/Activity;",
                    "setContentView",
                    listOf("I"),
                    "V",
                ),
            )
        }.exceptionOrNull() as PluginTypedException
        assertEquals(PluginResult.TRANSFORM_UNSUPPORTED, unsupportedApi.result)

        val unsupportedResource = runCatching {
            GuestCompatibilityValidator.validateResourceOwner("Lio/example/fixture/R${'$'}layout;")
        }.exceptionOrNull() as PluginTypedException
        assertEquals(PluginResult.TRANSFORM_UNSUPPORTED, unsupportedResource.result)
    }
}
