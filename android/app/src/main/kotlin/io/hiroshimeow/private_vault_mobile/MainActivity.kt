package io.hiroshimeow.private_vault_mobile

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "private_vault/platform"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDisguiseCapabilities" -> result.success(
                        mapOf(
                            "androidLauncherAliases" to true,
                            "iosAlternateIcons" to false,
                        ),
                    )
                    "setDisguise" -> {
                        val choice = call.arguments as? String
                        if (choice == "calculator" || choice == "notes") {
                            setLauncherAlias(choice)
                            result.success(true)
                        } else {
                            result.error("invalid_choice", "Unknown disguise choice", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setLauncherAlias(choice: String) {
        val calculator = ComponentName(packageName, "$packageName.CalculatorAlias")
        val notes = ComponentName(packageName, "$packageName.NotesAlias")
        val enabled = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val disabled = PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        val flags = PackageManager.DONT_KILL_APP

        packageManager.setComponentEnabledSetting(
            calculator,
            if (choice == "calculator") enabled else disabled,
            flags,
        )
        packageManager.setComponentEnabledSetting(
            notes,
            if (choice == "notes") enabled else disabled,
            flags,
        )
    }
}
