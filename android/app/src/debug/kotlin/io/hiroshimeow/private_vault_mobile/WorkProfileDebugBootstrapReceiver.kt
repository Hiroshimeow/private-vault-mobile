package io.hiroshimeow.private_vault_mobile

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo

class WorkProfileDebugBootstrapReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            return
        }
        if (intent.action != ACTION_DEBUG_BOOTSTRAP) return

        val controlToken =
            intent.getStringExtra(WorkProfileProtocol.EXTRA_CONTROL_TOKEN)
                ?.takeIf { it.isNotBlank() }
                ?: return

        WorkProfileControlToken.store(context, controlToken)
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        if (dpm.isProfileOwnerApp(context.packageName)) {
            WorkProfileProvisioningConfigurator.configure(context, controlToken)
        }
    }

    companion object {
        const val ACTION_DEBUG_BOOTSTRAP =
            "io.hiroshimeow.private_vault_mobile.action.DEBUG_WORK_PROFILE_BOOTSTRAP"
    }
}
