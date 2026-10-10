package io.hiroshimeow.private_vault_mobile

import com.reandroid.apk.ApkModule
import com.reandroid.app.AndroidManifest
import com.reandroid.archive.ByteInputSource
import com.reandroid.arsc.chunk.TableBlock
import com.reandroid.arsc.chunk.xml.AndroidManifestBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class StandaloneCloneEngineTest {
    @Test
    fun rewriteModuleChangesResourceIdentityButPreservesCodeClassNames() {
        val sourcePackage = "com.example.demo"
        val clonePackage = "com.example.demo.pvclone.c123456789abc"
        val module = syntheticModule(sourcePackage)

        StandaloneCloneEngine.rewriteModuleForClone(module, sourcePackage, clonePackage)

        val manifest = module.androidManifestBlock
        assertEquals(clonePackage, manifest.packageName)
        assertEquals(clonePackage, module.tableBlock.pickOne().name)
        val application = manifest.applicationElement
        val activity = application.listElements("activity").single()
        val provider = application.listElements("provider").single()
        val alias = application.listElements("activity-alias").single()

        assertEquals(
            "$sourcePackage.MainActivity",
            activity.searchAttributeByName("name").valueAsString,
        )
        assertEquals(
            "$sourcePackage.MainActivity",
            alias.searchAttributeByName("targetActivity").valueAsString,
        )
        assertEquals(
            "$clonePackage.files;$clonePackage.cache",
            provider.searchAttributeByName("authorities").valueAsString,
        )
    }

    @Test
    fun manifestInspectionRejectsAmbiguousGlobalsAndVerifiedLinks() {
        val sourcePackage = "com.example.demo"
        val module = syntheticModule(sourcePackage)
        val manifest = module.androidManifestBlock
        val application = manifest.applicationElement
        val provider = application.listElements("provider").single()
        provider.searchAttributeByName("authorities").setValueAsString("org.shared.provider")
        val activity = application.listElements("activity").single()
        activity.getOrCreateAndroidAttribute("process", 0).setValueAsString("org.shared.process")
        activity.getOrCreateAndroidAttribute("taskAffinity", 0).setValueAsString("org.shared.task")
        val filter = activity.newElement("intent-filter")
        filter.getOrCreateAndroidAttribute("autoVerify", 0).setValueAsBoolean(true)

        val facts = StandaloneCloneEngine.inspectManifestFacts(
            manifest = manifest,
            sourcePackage = sourcePackage,
            hasHardcodedApplicationId = false,
            hasGoogleIdentityBinding = false,
        )

        assertTrue(facts.hasUnsafeProviderAuthority)
        assertTrue(facts.hasUnsafeAbsoluteProcess)
        assertTrue(facts.hasUnsafeTaskAffinity)
        assertTrue(facts.hasVerifiedAppLink)
        assertFalse(facts.hasHardcodedApplicationId)
    }

    @Test
    fun rewriteModuleRewritesDeclarationBackedPermissionReferences() {
        val sourcePackage = "com.example.demo"
        val clonePackage = "com.example.demo.pvclone.c123456789abc"
        val sourcePermission = "$sourcePackage.permission.INTERNAL"
        val clonePermission = "$clonePackage.permission.INTERNAL"
        val module = syntheticModule(sourcePackage)
        val manifest = module.androidManifestBlock
        val root = manifest.manifestElement
        root.newElement("permission").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name).setValueAsString(sourcePermission)
        }
        root.newElement("uses-permission").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name).setValueAsString(sourcePermission)
        }
        val application = manifest.applicationElement
        application.getOrCreateAndroidAttribute("permission", 0).setValueAsString(sourcePermission)
        application.listElements("activity").single()
            .getOrCreateAndroidAttribute("permission", 0).setValueAsString(sourcePermission)
        application.newElement("service").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name).setValueAsString(".DemoService")
            getOrCreateAndroidAttribute("permission", 0).setValueAsString(sourcePermission)
        }
        application.newElement("receiver").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name).setValueAsString(".DemoReceiver")
            getOrCreateAndroidAttribute("permission", 0).setValueAsString(sourcePermission)
        }
        application.listElements("provider").single().apply {
            getOrCreateAndroidAttribute("permission", 0).setValueAsString(sourcePermission)
            getOrCreateAndroidAttribute("readPermission", 0).setValueAsString(sourcePermission)
            getOrCreateAndroidAttribute("writePermission", 0).setValueAsString(sourcePermission)
        }

        StandaloneCloneEngine.rewriteModuleForClone(module, sourcePackage, clonePackage)

        val rewritten = module.androidManifestBlock
        val elements = rewritten.manifestElement.recursiveElements().asSequence().toList()
        val declaration = elements.single { it.name == "permission" }
        val usesPermission = elements.single { it.name == "uses-permission" }
        assertEquals(clonePermission, declaration.searchAttributeByName("name").valueAsString)
        assertEquals(clonePermission, usesPermission.searchAttributeByName("name").valueAsString)
        assertEquals(clonePermission, rewritten.applicationElement.searchAttributeByName("permission").valueAsString)
        for (tag in listOf("activity", "service", "receiver")) {
            assertEquals(
                clonePermission,
                rewritten.applicationElement.listElements(tag).first()
                    .searchAttributeByName("permission").valueAsString,
            )
        }
        val provider = rewritten.applicationElement.listElements("provider").single()
        for (attribute in listOf("permission", "readPermission", "writePermission")) {
            assertEquals(clonePermission, provider.searchAttributeByName(attribute).valueAsString)
        }
    }

    @Test
    fun manifestInspectionRejectsUndeclaredPackageDerivedPermissionReference() {
        val sourcePackage = "com.example.demo"
        val module = syntheticModule(sourcePackage)
        module.androidManifestBlock.applicationElement
            .getOrCreateAndroidAttribute("permission", 0)
            .setValueAsString("$sourcePackage.permission.MISSING")

        val facts = StandaloneCloneEngine.inspectManifestFacts(
            manifest = module.androidManifestBlock,
            sourcePackage = sourcePackage,
            hasHardcodedApplicationId = false,
            hasGoogleIdentityBinding = false,
        )

        assertTrue(facts.hasUnsafePermissionReference)
    }

    @Test
    fun nonVerifiedCustomDeepLinkProducesDegradedWarning() {
        val sourcePackage = "com.example.demo"
        val module = syntheticModule(sourcePackage)
        val filter = module.androidManifestBlock.applicationElement
            .listElements("activity").single()
            .newElement("intent-filter")
        filter.newElement("action").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name)
                .setValueAsString("android.intent.action.VIEW")
        }
        filter.newElement("category").apply {
            getOrCreateAndroidAttribute("name", AndroidManifest.ID_name)
                .setValueAsString("android.intent.category.BROWSABLE")
        }
        filter.newElement("data").apply {
            getOrCreateAndroidAttribute("scheme", 0).setValueAsString("demo")
        }

        val facts = StandaloneCloneEngine.inspectManifestFacts(
            manifest = module.androidManifestBlock,
            sourcePackage = sourcePackage,
            hasHardcodedApplicationId = false,
            hasGoogleIdentityBinding = false,
        )
        val compatibility = StandaloneClonePolicy.classifyArchive(
            entries = listOf("AndroidManifest.xml", "classes.dex"),
            manifestFacts = facts,
        )

        assertTrue(facts.hasCustomDeepLink)
        assertTrue(compatibility.supported)
        assertEquals(listOf("deep_link_degraded"), compatibility.warnings)
    }

    @Test
    fun sourceIdentityRejectsMissingOrMultipleCurrentSigners() {
        val signer = "signer-one".toByteArray()

        assertEquals(
            "1d506da3f991fdd0bb1dad5f9c5b39d7b7307c3162d4e6289556e1bc68d85a55",
            StandaloneCloneEngine.sourceSignerSha256(listOf(signer)),
        )
        assertNull(StandaloneCloneEngine.sourceSignerSha256(emptyList()))
        assertNull(
            StandaloneCloneEngine.sourceSignerSha256(
                listOf(signer, "signer-two".toByteArray()),
            ),
        )
    }

    @Test
    fun transformWritesAndReopensValidatedCloneIdentity() {
        val sourcePackage = "com.example.demo"
        val clonePackage = "com.example.demo.pvclone.c123456789abc"
        val tempDir = Files.createTempDirectory("clone-roundtrip").toFile()
        try {
            val sourceApk = tempDir.resolve("source.apk")
            val unsignedApk = tempDir.resolve("unsigned.apk")
            syntheticModule(sourcePackage).use { module ->
                module.add(ByteInputSource(byteArrayOf(0x64, 0x65, 0x78), "classes.dex"))
                module.writeApk(sourceApk)
            }
            val inspection = StandaloneCloneInspection(
                compatibility = StandaloneCloneCompatibility(blockers = emptyList()),
                sourcePackage = sourcePackage,
                clonePackage = clonePackage,
            )

            StandaloneCloneEngine().transform(sourceApk, inspection, unsignedApk)

            ApkModule.loadApkFile(unsignedApk).use { reopened ->
                assertEquals(clonePackage, reopened.androidManifestBlock.packageName)
                assertEquals(clonePackage, reopened.tableBlock.pickOne().name)
            }
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test(expected = IllegalStateException::class)
    fun postTransformValidationRejectsSourceDerivedGlobalRemainingInUnsignedApk() {
        val sourcePackage = "com.example.demo"
        val clonePackage = "com.example.demo.pvclone.c123456789abc"
        val tempDir = Files.createTempDirectory("clone-invalid-roundtrip").toFile()
        try {
            val apk = tempDir.resolve("bad.apk")
            syntheticModule(sourcePackage).use { module ->
                StandaloneCloneEngine.rewriteModuleForClone(module, sourcePackage, clonePackage)
                module.androidManifestBlock.applicationElement.listElements("provider").single()
                    .searchAttributeByName("authorities")
                    .setValueAsString("$sourcePackage.files")
                module.writeApk(apk)
            }
            StandaloneCloneEngine.validateTransformedApk(apk, sourcePackage, clonePackage)
        } finally {
            tempDir.deleteRecursively()
        }
    }

    @Test
    fun asciiSearchDoesNotTreatSlashQualifiedCodePackageAsApplicationIdLiteral() {
        val dot = "prefix com.example.demo suffix".toByteArray()
        val slash = "Lcom/example/demo/MainActivity;".toByteArray()

        assertTrue(StandaloneCloneEngine.containsAsciiLiteral(dot, "com.example.demo"))
        assertFalse(StandaloneCloneEngine.containsAsciiLiteral(slash, "com.example.demo"))
    }

    @Test
    fun dexPreservationFilterCoversDoubleDigitMultidex() {
        assertTrue(StandaloneCloneEngine.isDexEntry("classes.dex"))
        assertTrue(StandaloneCloneEngine.isDexEntry("classes2.dex"))
        assertTrue(StandaloneCloneEngine.isDexEntry("classes10.dex"))
        assertTrue(StandaloneCloneEngine.isDexEntry("classes123.dex"))
        assertFalse(StandaloneCloneEngine.isDexEntry("classes1.dex"))
        assertFalse(StandaloneCloneEngine.isDexEntry("assets/classes10.dex"))
    }

    private fun syntheticModule(sourcePackage: String): ApkModule {
        val module = ApkModule()
        val manifest = AndroidManifestBlock().apply {
            packageName = sourcePackage
            versionCode = 7
        }
        val application = manifest.orCreateApplicationElement
        application.newElement("activity").apply {
            getOrCreateAndroidAttribute(AndroidManifest.NAME_name, AndroidManifest.ID_name)
                .setValueAsString(".MainActivity")
        }
        application.newElement("activity-alias").apply {
            getOrCreateAndroidAttribute(AndroidManifest.NAME_name, AndroidManifest.ID_name)
                .setValueAsString(".LauncherAlias")
            getOrCreateAndroidAttribute(AndroidManifest.NAME_targetActivity, 0)
                .setValueAsString(".MainActivity")
        }
        application.newElement("provider").apply {
            getOrCreateAndroidAttribute(AndroidManifest.NAME_name, AndroidManifest.ID_name)
                .setValueAsString(".DemoProvider")
            getOrCreateAndroidAttribute(AndroidManifest.NAME_authorities, AndroidManifest.ID_authorities)
                .setValueAsString("$sourcePackage.files;$sourcePackage.cache")
        }
        val table = TableBlock().apply {
            newPackage(0x7f, sourcePackage)
        }
        module.setManifest(manifest)
        module.setTableBlock(table)
        return module
    }
}
