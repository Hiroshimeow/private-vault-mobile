package io.hiroshimeow.clonefixture

import android.app.Service
import android.content.Intent
import android.os.IBinder

class FixtureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
