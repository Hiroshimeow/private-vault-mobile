package me.hculab.privatevault.web;

import static org.junit.Assert.*;
import android.content.pm.ApplicationInfo;
import android.view.WindowManager;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class PackagingSmokeTest {
    private String evaluate(ActivityScenario<MainActivity> scenario, String script) throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<String> value = new AtomicReference<>();
        scenario.onActivity(activity -> activity.getBridge().getWebView().evaluateJavascript(script, result -> {
            value.set(result);
            latch.countDown();
        }));
        assertTrue("WebView did not reply", latch.await(10, TimeUnit.SECONDS));
        return value.get();
    }

    private void awaitTrue(ActivityScenario<MainActivity> scenario, String expression) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45);
        do {
            if ("true".equals(evaluate(scenario, expression))) return;
            Thread.sleep(200);
        } while (System.nanoTime() < deadline);
        fail("Bundled WebView smoke condition failed: " + expression);
    }

    @Test
    public void coverCryptoAndEncryptedStorageWorkWithoutRemoteServer() throws Exception {
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            awaitTrue(scenario, "!!document.querySelector('#root button')");
            assertEquals("true", evaluate(scenario,
                "window.isSecureContext && location.origin === 'https://localhost' && !!crypto.subtle && !!indexedDB"));
            assertEquals("true", evaluate(scenario,
                "document.body.innerText.includes('Calculator') && !document.body.innerText.includes('YouTube')"));

            // Synthetic ciphertext only. No user vault or real media is accessed.
            evaluate(scenario, "(function(){window.__packagingSmoke='pending';(async()=>{" +
                "const plain=new TextEncoder().encode('SYNTHETIC-CI-ONLY');" +
                "const key=await crypto.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']);" +
                "const iv=crypto.getRandomValues(new Uint8Array(12));" +
                "const sealed=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,plain);" +
                "const request=indexedDB.open('packaging_smoke_fixture',1);" +
                "request.onupgradeneeded=()=>request.result.createObjectStore('ciphertext');" +
                "const db=await new Promise((resolve,reject)=>{request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error)});" +
                "await new Promise((resolve,reject)=>{const tx=db.transaction('ciphertext','readwrite');tx.objectStore('ciphertext').put(sealed,'fixture');tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error)});" +
                "const stored=await new Promise((resolve,reject)=>{const get=db.transaction('ciphertext').objectStore('ciphertext').get('fixture');get.onsuccess=()=>resolve(get.result);get.onerror=()=>reject(get.error)});" +
                "const opened=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,stored);" +
                "if(new TextDecoder().decode(opened)!=='SYNTHETIC-CI-ONLY')throw new Error('roundtrip');" +
                "if(new TextDecoder().decode(stored).includes('SYNTHETIC-CI-ONLY'))throw new Error('plaintext');" +
                "db.close();indexedDB.deleteDatabase('packaging_smoke_fixture');window.__packagingSmoke='pass';" +
                "})().catch(()=>window.__packagingSmoke='fail');return true})()");
            awaitTrue(scenario, "window.__packagingSmoke === 'pass'");
        }
    }

    @Test
    public void captureAndBackupAreDisabled() {
        try (ActivityScenario<MainActivity> scenario = ActivityScenario.launch(MainActivity.class)) {
            scenario.onActivity(activity -> {
                assertNotEquals(0, activity.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_SECURE);
                assertTrue(activity.getBridge().getWebView().getFilterTouchesWhenObscured());
            });
            ApplicationInfo info = InstrumentationRegistry.getInstrumentation().getTargetContext().getApplicationInfo();
            assertEquals(0, info.flags & ApplicationInfo.FLAG_ALLOW_BACKUP);
        }
    }
}
