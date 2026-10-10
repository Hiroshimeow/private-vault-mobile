package me.hculab.privatevault.web;

import android.os.Bundle;
import android.view.WindowManager;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        super.onCreate(savedInstanceState);
        if (getBridge() != null) {
            getBridge().getWebView().setFilterTouchesWhenObscured(true);
        }
    }
}
