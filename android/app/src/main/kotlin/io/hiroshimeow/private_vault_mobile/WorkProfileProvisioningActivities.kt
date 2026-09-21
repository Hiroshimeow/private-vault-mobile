package io.hiroshimeow.private_vault_mobile

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle

class WorkProfileProvisioningModeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val mode = selectManagedProfileMode(intent)
        if (mode == null) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val result = Intent().putExtra(DevicePolicyManager.EXTRA_PROVISIONING_MODE, mode)
        @Suppress("DEPRECATION")
        val adminExtras =
            intent.getParcelableExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
            ) as? PersistableBundle
        if (adminExtras != null) {
            result.putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE,
                adminExtras,
            )
        }
        setResult(RESULT_OK, result)
        finish()
    }

    private fun selectManagedProfileMode(intent: Intent): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE
        }
        val allowed =
            intent.getIntegerArrayListExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_ALLOWED_PROVISIONING_MODES,
            )
        if (allowed.isNullOrEmpty()) {
            return DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE_ON_PERSONAL_DEVICE
        }
        return when {
            allowed.contains(
                DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE_ON_PERSONAL_DEVICE,
            ) -> DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE_ON_PERSONAL_DEVICE
            allowed.contains(DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE) ->
                DevicePolicyManager.PROVISIONING_MODE_MANAGED_PROFILE
            else -> null
        }
    }
}

class WorkProfilePolicyComplianceActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dpm = getSystemService(DevicePolicyManager::class.java)
        setResult(
            if (dpm.isProfileOwnerApp(packageName)) RESULT_OK else RESULT_CANCELED,
        )
        finish()
    }
}
