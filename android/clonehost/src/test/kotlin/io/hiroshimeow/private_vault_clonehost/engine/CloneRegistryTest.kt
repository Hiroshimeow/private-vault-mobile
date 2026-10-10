package io.hiroshimeow.private_vault_clonehost.engine

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class CloneRegistryTest {
    @get:Rule val temp = TemporaryFolder()

    @Test
    fun `register persists one record and occupied slot is not mutated`() {
        val prefs = MemoryPrefs()
        val source = source("example.fixture")
        val registry = CloneRegistry(prefs, temp.newFolder("images"), { SourceResult.Success(source) }, 0)

        val first = registry.registerInstalled(source.packageName)
        val second = registry.registerInstalled("example.other")

        assertTrue(first.ok)
        assertEquals("slot0:example.fixture", first.record?.instanceId)
        assertEquals("slot_occupied", second.errorCode)
        assertEquals("example.fixture", registry.current()?.packageName)
        assertTrue(registry.imageFiles(first.record!!).all(File::isFile))
    }

    @Test
    fun `failed record commit removes staged image and leaves slot empty`() {
        val prefs = MemoryPrefs(failNextCommit = true)
        val registry = CloneRegistry(prefs, temp.newFolder("images"), { SourceResult.Success(source("example.fixture")) }, 0)

        val result = registry.registerInstalled("example.fixture")

        assertFalse(result.ok)
        assertEquals("operation_failed", result.errorCode)
        assertNull(registry.current())
        assertFalse(File(temp.root, "images/current").exists())
    }

    @Test
    fun `remove commit failure preserves record and image`() {
        val prefs = MemoryPrefs()
        val registry = CloneRegistry(prefs, temp.newFolder("images"), { SourceResult.Success(source("example.fixture")) }, 1)
        val registered = registry.registerInstalled("example.fixture").record!!
        val image = registry.imageFiles(registered).single()
        var imagePresentWhenRemovalCommitRuns = false
        prefs.beforeCommit = { imagePresentWhenRemovalCommitRuns = image.isFile }
        prefs.failNextCommit = true

        val result = registry.remove(registered.instanceId)

        assertFalse(result.ok)
        assertEquals("operation_failed", result.errorCode)
        assertTrue(imagePresentWhenRemovalCommitRuns)
        assertNotNull(registry.current())
        assertTrue(image.isFile)
    }

    @Test
    fun `remove wrong instance does not mutate current slot`() {
        val prefs = MemoryPrefs()
        val registry = CloneRegistry(prefs, temp.newFolder("images"), { SourceResult.Success(source("example.fixture")) }, 0)
        val registered = registry.registerInstalled("example.fixture").record!!

        val result = registry.remove("slot0:example.other")

        assertEquals("instance_not_found", result.errorCode)
        assertEquals(registered, registry.current())
        assertTrue(registry.imageFiles(registered).single().isFile)
    }

    private fun source(packageName: String): GuestPackageImageSource {
        val base = File(temp.newFolder("src-${packageName.hashCode()}"), "base.apk").apply { writeText("apk") }
        return GuestPackageImageSource(packageName, "Fixture", "1", "FixtureActivity", null, emptyList(), base, emptyList())
    }

    private class MemoryPrefs(var failNextCommit: Boolean = false) : SharedPreferences {
        var beforeCommit: (() -> Unit)? = null
        private val values = linkedMapOf<String, Any?>()
        override fun getAll(): MutableMap<String, *> = values.toMutableMap()
        override fun getString(key: String?, defValue: String?): String? = values[key] as? String ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
        override fun contains(key: String?): Boolean = values.containsKey(key)
        override fun edit(): SharedPreferences.Editor = Editor()
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

        private inner class Editor : SharedPreferences.Editor {
            private val pending = linkedMapOf<String, Any?>()
            private val removals = linkedSetOf<String>()
            private var clear = false
            override fun putString(key: String?, value: String?): SharedPreferences.Editor = apply { if (key != null) pending[key] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor = apply { if (key != null) pending[key] = values }
            override fun putInt(key: String?, value: Int): SharedPreferences.Editor = apply { if (key != null) pending[key] = value }
            override fun putLong(key: String?, value: Long): SharedPreferences.Editor = apply { if (key != null) pending[key] = value }
            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = apply { if (key != null) pending[key] = value }
            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = apply { if (key != null) pending[key] = value }
            override fun remove(key: String?): SharedPreferences.Editor = apply { if (key != null) removals += key }
            override fun clear(): SharedPreferences.Editor = apply { clear = true }
            override fun commit(): Boolean {
                beforeCommit?.invoke()
                if (failNextCommit) { failNextCommit = false; return false }
                if (clear) values.clear()
                removals.forEach(values::remove)
                values.putAll(pending)
                return true
            }
            override fun apply() { commit() }
        }
    }
}
