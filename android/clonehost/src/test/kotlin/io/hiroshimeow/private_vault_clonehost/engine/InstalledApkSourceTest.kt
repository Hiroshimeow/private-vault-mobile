package io.hiroshimeow.private_vault_clonehost.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class InstalledApkSourceTest {
    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun `preflight rejects unreadable base and missing split with typed reasons`() {
        val missingBase = File(temp.root, "missing-base.apk")
        assertEquals(
            SourceFailure.PACKAGE_UNREADABLE,
            preflightPackageShape("example.fixture", emptyList(), false, missingBase, emptyList(), arrayOf("arm64-v8a")),
        )

        val base = apk("base.apk")
        val missingSplit = File(temp.root, "missing-split.apk")
        assertEquals(
            SourceFailure.MISSING_SPLIT,
            preflightPackageShape("example.fixture", emptyList(), false, base, listOf(missingSplit), arrayOf("arm64-v8a")),
        )
    }

    @Test
    fun `preflight rejects multiprocess and service shapes before runtime`() {
        val base = apk("base.apk")
        assertEquals(
            SourceFailure.UNSUPPORTED_MULTIPROCESS,
            preflightPackageShape("example.fixture", listOf("example.fixture:remote"), false, base, emptyList(), arrayOf("arm64-v8a")),
        )
        assertEquals(
            SourceFailure.UNSUPPORTED_SERVICE_COMPONENT,
            preflightPackageShape("example.fixture", listOf("example.fixture"), true, base, emptyList(), arrayOf("arm64-v8a")),
        )
    }

    @Test
    fun `preflight rejects incompatible packaged native abi and accepts compatible or java-only apk`() {
        val incompatible = apk("x86.apk", "lib/x86/libfixture.so")
        assertEquals(
            SourceFailure.UNSUPPORTED_ABI,
            preflightPackageShape("example.fixture", emptyList(), false, incompatible, emptyList(), arrayOf("arm64-v8a")),
        )

        val compatible = apk("arm64.apk", "lib/arm64-v8a/libfixture.so")
        assertNull(preflightPackageShape("example.fixture", emptyList(), false, compatible, emptyList(), arrayOf("arm64-v8a")))
        assertNull(preflightPackageShape("example.fixture", emptyList(), false, apk("java.apk"), emptyList(), arrayOf("arm64-v8a")))
    }

    private fun apk(name: String, vararg entries: String): File = File(temp.root, name).also { file ->
        ZipOutputStream(file.outputStream()).use { zip ->
            for (entry in entries) {
                zip.putNextEntry(ZipEntry(entry))
                zip.write(byteArrayOf(1))
                zip.closeEntry()
            }
        }
    }
}
