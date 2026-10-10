package io.hiroshimeow.private_vault_clonehost

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloneHostIsolationTest {
    @Test
    fun companionRunsOutsideVaultApplicationIdentity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue(context.packageName.startsWith("io.hiroshimeow.private_vault.clonehost.slot"))
        assertFalse(context.packageName == "io.hiroshimeow.private_vault_mobile")
        assertTrue(Process.myUid() > 0)
        assertFalse(context.filesDir.absolutePath.contains("private_vault_mobile"))
    }
}
