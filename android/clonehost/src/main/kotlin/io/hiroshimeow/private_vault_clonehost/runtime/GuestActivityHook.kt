package io.hiroshimeow.private_vault_clonehost.runtime

import android.app.Activity
import android.app.Application
import android.app.Instrumentation
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.view.Window
import io.hiroshimeow.private_vault_clonehost.engine.CloneRecord
import java.io.File

internal object GuestActivityHook {
    fun launch(
        container: Activity,
        record: CloneRecord,
        environment: GuestEnvironment,
        classLoader: ClassLoader,
        application: Application,
        baseApk: File,
        splitApks: List<File>,
    ): Result<Activity> = runCatching {
        val packageInfo = archivePackageInfo(container, baseApk, splitApks)
        val activityInfo = packageInfo.activities.orEmpty().firstOrNull { it.name == record.launcherActivity }
            ?: error("launch_failed")
        activityInfo.applicationInfo = environment.applicationInfo

        val guestActivity = classLoader.loadClass(record.launcherActivity)
            .getDeclaredConstructor().newInstance() as Activity
        attach(container, guestActivity, environment.context, application, activityInfo, record)

        val instrumentation = Instrumentation()
        instrumentation.callActivityOnCreate(guestActivity, Bundle())
        instrumentation.callActivityOnStart(guestActivity)
        instrumentation.callActivityOnResume(guestActivity)
        container.setContentView(guestActivity.window.decorView)
        guestActivity
    }

    @Suppress("DEPRECATION")
    private fun archivePackageInfo(context: Context, baseApk: File, splitApks: List<File>) =
        (if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageArchiveInfo(
                baseApk.absolutePath,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_ACTIVITIES.toLong()),
            )
        } else {
            context.packageManager.getPackageArchiveInfo(baseApk.absolutePath, PackageManager.GET_ACTIVITIES)
        } ?: error("launch_failed")).also { info ->
            info.applicationInfo?.apply {
                sourceDir = baseApk.absolutePath
                publicSourceDir = baseApk.absolutePath
                splitSourceDirs = splitApks.map(File::getAbsolutePath).toTypedArray().takeIf { it.isNotEmpty() }
                splitPublicSourceDirs = splitSourceDirs
            }
        }

    private fun attach(
        container: Activity,
        guest: Activity,
        guestContext: Context,
        guestApplication: Application,
        info: ActivityInfo,
        record: CloneRecord,
    ) {
        val activityThreadClass = Class.forName("android.app.ActivityThread")
        val currentThread = activityThreadClass.getDeclaredMethod("currentActivityThread").apply { isAccessible = true }.invoke(null)
        val instrumentation = activityThreadClass.getDeclaredField("mInstrumentation").apply { isAccessible = true }
            .get(currentThread) as Instrumentation
        val token = Activity::class.java.getDeclaredField("mToken").apply { isAccessible = true }.get(container) as? IBinder
        val guestIntent = Intent().setComponent(ComponentName(record.packageName, record.launcherActivity))
        val attach = Activity::class.java.declaredMethods
            .filter { it.name == "attach" }
            .maxByOrNull { it.parameterCount }
            ?: error("launch_failed")
        attach.isAccessible = true
        val args = attach.parameterTypes.map { type ->
            when {
                Context::class.java.isAssignableFrom(type) -> guestContext
                type.name == "android.app.ActivityThread" -> currentThread
                Instrumentation::class.java.isAssignableFrom(type) -> instrumentation
                IBinder::class.java.isAssignableFrom(type) -> token
                type == Int::class.javaPrimitiveType -> 0
                type == Boolean::class.javaPrimitiveType -> false
                Application::class.java.isAssignableFrom(type) -> guestApplication
                Intent::class.java.isAssignableFrom(type) -> guestIntent
                ActivityInfo::class.java.isAssignableFrom(type) -> info
                CharSequence::class.java.isAssignableFrom(type) -> record.label
                Activity::class.java.isAssignableFrom(type) -> null
                Configuration::class.java.isAssignableFrom(type) -> guestContext.resources.configuration
                Window::class.java.isAssignableFrom(type) -> null
                type == String::class.java -> null
                else -> null
            }
        }.toTypedArray()
        attach.invoke(guest, *args)
    }
}
