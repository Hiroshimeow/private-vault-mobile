package io.hiroshimeow.private_vault_pluginfixture;

import android.app.Application;
import android.content.Context;

public final class FixtureApplication extends Application {
    private int starts;

    @Override
    public void onCreate() {
        super.onCreate();
        starts = getSharedPreferences("fixture", Context.MODE_PRIVATE).getInt("starts", 0) + 1;
        getSharedPreferences("fixture", Context.MODE_PRIVATE).edit().putInt("starts", starts).apply();
    }

    public int getStarts() {
        return starts;
    }
}
