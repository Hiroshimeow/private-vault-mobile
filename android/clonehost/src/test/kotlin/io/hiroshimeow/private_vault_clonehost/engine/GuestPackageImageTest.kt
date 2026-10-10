package io.hiroshimeow.private_vault_clonehost.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class GuestPackageImageTest {
    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun `package image copies base and splits in deterministic name order`() {
        val source = temp.newFolder("source")
        val base = File(source, "base.apk").apply { writeText("base") }
        val splitZ = File(source, "z.apk").apply { writeText("z") }
        val splitA = File(source, "a.apk").apply { writeText("a") }
        val target = temp.newFolder("target")

        val result = GuestPackageImage.stage(
            packageName = "example.fixture",
            baseApk = base,
            splitApks = listOf(splitZ, splitA),
            destination = target,
        )

        assertTrue(result is PackageImageResult.Success)
        val success = result as PackageImageResult.Success
        assertEquals(listOf("base.apk", "split-000-a.apk", "split-001-z.apk"), success.image.files.map { it.file.name })
        assertEquals(64, success.image.files.first().sha256.length)
    }

    @Test
    fun `missing split fails without replacing previous image`() {
        val source = temp.newFolder("source")
        val base = File(source, "base.apk").apply { writeText("base") }
        val missing = File(source, "missing.apk")
        val target = temp.newFolder("target")
        File(target, "sentinel").writeText("keep")

        val result = GuestPackageImage.stage(
            packageName = "example.fixture",
            baseApk = base,
            splitApks = listOf(missing),
            destination = target,
        )

        assertEquals(PackageImageFailure.MISSING_SPLIT, (result as PackageImageResult.Failure).reason)
        assertTrue(File(target, "sentinel").exists())
        assertFalse(File(target, "base.apk").exists())
    }

    @Test
    fun `invalid package name is rejected before filesystem work`() {
        assertFalse(GuestPackageImage.isValidPackageName("../vault"))
        assertFalse(GuestPackageImage.isValidPackageName("io.example/escape"))
        assertTrue(GuestPackageImage.isValidPackageName("io.example.fixture"))
    }
}
