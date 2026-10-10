package io.hiroshimeow.private_vault_mobile

import android.net.Uri
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloneRuntimeInstrumentedTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun twoSlotsRegisterLaunchAndRemoveIndependently() {
        val pm = context.packageManager
        val slot0 = "io.hiroshimeow.private_vault.clonehost.slot0"
        val slot1 = "io.hiroshimeow.private_vault.clonehost.slot1"
        val fixture = "io.hiroshimeow.clonefixture.supported"
        val unsupported = "io.hiroshimeow.clonefixture.unsupported"
        val uid0 = pm.getApplicationInfo(slot0, 0).uid
        val uid1 = pm.getApplicationInfo(slot1, 0).uid
        val vaultUid = pm.getApplicationInfo(context.packageName, 0).uid
        assertEquals(vaultUid, context.applicationInfo.uid)
        assertNotEquals(uid0, uid1)
        assertNotEquals(vaultUid, uid0)
        assertNotEquals(vaultUid, uid1)

        removeIfPresent(slot0)
        removeIfPresent(slot1)

        val r0 = call(slot0, REGISTER_INSTALLED, "packageName", fixture)
        val r1 = call(slot1, REGISTER_INSTALLED, "packageName", fixture)
        assertTrue(r0.getBoolean("ok"))
        assertTrue(r1.getBoolean("ok"))
        val id0 = r0.getString("instanceId")!!
        val id1 = r1.getString("instanceId")!!
        assertNotEquals(id0, id1)

        assertTrue(call(slot0, LAUNCH, "instanceId", id0).getBoolean("ok"))
        assertTrue(call(slot1, LAUNCH, "instanceId", id1).getBoolean("ok"))
        assertEquals(id0, call(slot0, STATE).getString("instanceId"))
        assertEquals(id1, call(slot1, STATE).getString("instanceId"))

        assertTrue(call(slot0, REMOVE, "instanceId", id0).getBoolean("ok"))
        assertEquals("empty", call(slot0, STATE).getString("state"))
        assertEquals(id1, call(slot1, STATE).getString("instanceId"))

        val occupied = call(slot1, REGISTER_INSTALLED, "packageName", fixture)
        assertFalse(occupied.getBoolean("ok"))
        assertEquals("slot_occupied", occupied.getString("errorCode"))

        assertTrue(call(slot1, REMOVE, "instanceId", id1).getBoolean("ok"))
        val rejected = call(slot0, REGISTER_INSTALLED, "packageName", unsupported)
        assertFalse(rejected.getBoolean("ok"))
        assertEquals("unsupported_service_component", rejected.getString("errorCode"))
    }

    @Test
    fun protocolRejectsUnexpectedExtras() {
        val extras = Bundle().apply {
            putString("packageName", "io.hiroshimeow.clonefixture.supported")
            putString("path", "/data/local/tmp/not-allowed")
        }
        val result = context.contentResolver.call(
            Uri.parse("content://io.hiroshimeow.private_vault.clonehost.slot0.control"),
            REGISTER_INSTALLED,
            null,
            extras,
        )!!
        assertFalse(result.getBoolean("ok"))
        assertEquals("invalid_extras", result.getString("errorCode"))
    }

    private fun removeIfPresent(hostPackage: String) {
        val state = call(hostPackage, STATE)
        state.getString("instanceId")?.let { call(hostPackage, REMOVE, "instanceId", it) }
    }

    private fun call(hostPackage: String, method: String, key: String? = null, value: String? = null): Bundle {
        val extras = if (key == null) null else Bundle().apply { putString(key, value) }
        return context.contentResolver.call(Uri.parse("content://$hostPackage.control"), method, null, extras)!!
    }

    private companion object {
        const val STATE = "state"
        const val REGISTER_INSTALLED = "registerInstalled"
        const val LAUNCH = "launch"
        const val REMOVE = "remove"
    }
}
