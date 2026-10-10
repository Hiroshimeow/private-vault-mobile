package io.hiroshimeow.private_vault_clonehost

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CloneHostProtocolTest {
    @Test
    fun `fixed calls accept only their exact extras`() {
        assertEquals(emptySet<String>(), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.CAPABILITY))
        assertEquals(emptySet<String>(), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.STATE))
        assertEquals(setOf("packageName"), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.REGISTER_INSTALLED))
        assertEquals(setOf("instanceId"), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.LAUNCH))
        assertEquals(setOf("instanceId"), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.STOP))
        assertEquals(setOf("instanceId"), CloneHostProtocol.allowedExtraKeys(CloneHostProtocol.REMOVE))
        assertEquals(null, CloneHostProtocol.allowedExtraKeys("unknown"))
    }

    @Test
    fun `extra validation rejects unknown and surplus keys`() {
        assertTrue(CloneHostProtocol.hasExactExtras(CloneHostProtocol.CAPABILITY, emptySet()))
        assertTrue(CloneHostProtocol.hasExactExtras(CloneHostProtocol.REGISTER_INSTALLED, setOf("packageName")))
        assertFalse(CloneHostProtocol.hasExactExtras(CloneHostProtocol.REGISTER_INSTALLED, setOf("packageName", "path")))
        assertFalse(CloneHostProtocol.hasExactExtras(CloneHostProtocol.LAUNCH, setOf("packageName")))
        assertFalse(CloneHostProtocol.hasExactExtras("unknown", emptySet()))
    }
}
