package io.hiroshimeow.private_vault_pluginhost

import android.app.Activity
import android.os.Bundle
import android.os.Process
import android.widget.TextView
import dalvik.system.DexClassLoader
import java.io.File

class PluginContainerActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val artifact = runCatching { PluginRegistry(this).currentArtifact() }.getOrNull()
        if (artifact == null) {
            finish()
            return
        }
        val (dex, metadata) = artifact
        val loader = DexClassLoader(dex.absolutePath, File(codeCacheDir, "plugin").absolutePath, null, classLoader)
        val application = try {
            val app = metadata.applicationClass?.let { loader.loadClass(it).getDeclaredConstructor().newInstance() }
                ?: PluginGuestApplication()
            app as PluginGuestApplication
        } catch (_: Throwable) {
            finish()
            return
        }
        application.attach(this)
        runCatching { application.onCreate() }.getOrElse { finish(); return }

        val guest = try {
            loader.loadClass(metadata.launcherClass).getDeclaredConstructor().newInstance() as PluginGuestActivity
        } catch (_: Throwable) {
            finish()
            return
        }
        guest.attach(this, application)
        setContentView(TextView(this).apply {
            text = "Plugin ${metadata.sourcePackage}\nhelper=${packageName}\nuid=${Process.myUid()}"
            textSize = 18f
            setPadding(32, 64, 32, 32)
        })
        runCatching {
            guest.javaClass.getDeclaredMethod("onCreate", Bundle::class.java).apply { isAccessible = true }.invoke(guest, savedInstanceState)
        }.getOrElse { finish() }
    }
}
