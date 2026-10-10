package io.hiroshimeow.clonefixture

import android.app.Activity
import android.os.Bundle
import android.os.Process
import android.widget.TextView

class FixtureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("fixture", MODE_PRIVATE)
        val launches = prefs.getInt("launches", 0) + 1
        prefs.edit().putInt("launches", launches).apply()
        setContentView(TextView(this).apply {
            text = "fixture uid=${Process.myUid()} data=${filesDir.name} launches=$launches"
        })
    }
}
