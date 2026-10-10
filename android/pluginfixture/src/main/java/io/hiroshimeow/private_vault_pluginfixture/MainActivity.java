package io.hiroshimeow.private_vault_pluginfixture;

import android.app.Activity;
import android.os.Bundle;
import android.os.Process;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        FixtureApplication app = (FixtureApplication) getApplication();
        setTitle("Plugin fixture uid=" + Process.myUid() + " starts=" + app.getStarts());
    }
}
