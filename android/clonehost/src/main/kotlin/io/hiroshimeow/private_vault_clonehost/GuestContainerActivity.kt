package io.hiroshimeow.private_vault_clonehost

import android.app.Activity
import android.os.Bundle
import android.widget.TextView
import io.hiroshimeow.private_vault_clonehost.engine.CloneRegistry
import io.hiroshimeow.private_vault_clonehost.runtime.GuestRuntime
import java.lang.ref.WeakReference

class GuestContainerActivity : Activity() {
    private var instanceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val requested = intent.getStringExtra(EXTRA_INSTANCE_ID)
        if (requested.isNullOrBlank()) {
            finish()
            return
        }
        instanceId = requested
        active = WeakReference(this)
        val result = GuestRuntime(applicationContext, CloneRegistry(applicationContext)).launchInto(this, requested)
        if (!result.ok) {
            setContentView(TextView(this).apply { text = result.errorCode ?: "launch_failed" })
        }
    }

    override fun onDestroy() {
        if (active?.get() === this) active = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_INSTANCE_ID = "instanceId"
        private var active: WeakReference<GuestContainerActivity>? = null

        fun finishInstance(instanceId: String) {
            val activity = active?.get() ?: return
            if (activity.instanceId == instanceId) activity.runOnUiThread(activity::finish)
        }
    }
}
