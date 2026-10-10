package io.hiroshimeow.private_vault_pluginhost

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle

open class PluginGuestApplication {
    private lateinit var pluginContext: Context
    internal fun attach(context: Context) { pluginContext = context }
    open fun onCreate() = Unit
    fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        pluginContext.getSharedPreferences("guest_app_$name", mode)
    fun getApplicationContext(): Context = pluginContext.applicationContext
}

open class PluginGuestActivity {
    private lateinit var host: PluginContainerActivity
    private lateinit var guestApplication: PluginGuestApplication
    internal fun attach(host: PluginContainerActivity, application: PluginGuestApplication) {
        this.host = host
        this.guestApplication = application
    }
    protected open fun onCreate(savedInstanceState: Bundle?) = Unit
    fun setTitle(title: CharSequence?) { host.title = title }
    fun getApplication(): PluginGuestApplication = guestApplication
    fun getApplicationContext(): Context = host.applicationContext
    fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        host.getSharedPreferences("guest_activity_$name", mode)
}
