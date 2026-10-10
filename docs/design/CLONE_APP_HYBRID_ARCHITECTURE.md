# Hybrid Clone Space Architecture Specification

## 1. Executive Summary & Architectural Decisions

Private Vault requires true app cloning without compromising security, breaking Google authentication, or risking Google Play bans.

### Decommissioned Approaches (Dead-ends):
* **Standalone Repackaging (ARCHIVED):** Fails due to Split APKs/AABs, breaks cryptographic signatures (killing Google Sign-In, Firebase Auth, and FCM push notifications), and breaks ContentProvider authorities.
* **Virtual Container Hooking (ARCHIVED):** Fails on modern Android (13, 14, 15) due to non-SDK hidden API blocking, 64-bit ART kernel restrictions, and Google Play Protect malware flags (Trojan.Dropper categorization).

### The Chosen Solution: Hybrid OS-Level Profile Architecture
Private Vault implements an OS-level multi-user strategy:
1. **Tier 1 (Standard / 100% of Users): Managed Work Profile DPC (Device Policy Controller)**
   * **Privilege Requirement:** None (Zero-ADB, Zero-Root).
   * **Mechanism:** Private Vault acts as a Profile Owner using `DevicePolicyManager`.
   * **App Installation:** `dpm.installExistingPackage(adminComponent, packageName)`.
   * **Integrity:** Retains the original APK signature. Google Play Services, Google Sign-in, and push notifications work natively.
   * **Storage:** Complete kernel-level Linux UID and directory separation (`/data/user/10/...`).

2. **Tier 2 (Advanced / Power-Users): Shizuku `profile.CLONE`**
   * **Privilege Requirement:** ADB permission via Shizuku.
   * **Mechanism:** Invokes `pm create-user --profileOf 0 --user-type android.os.usertype.profile.CLONE`.
   * **Advantage:** No launcher briefcase badge; native Android OEM clone space.

---

## 2. Panic Conceal Lifecycle Integration

When a panic event is triggered (device shake, face-down sensor, or manual hotkey):
1. **Instant Profile Suspension:**
   ```kotlin
   // Suspends all apps in the Work Profile in a single frame
   val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
   val admin = ComponentName(context, VaultDeviceAdminReceiver::class.java)
   dpm.setWorkProfileEnabled(admin, false)
   ```
2. **Process Eviction:** The OS immediately terminates all foreground and background clone processes.
3. **UI Concealment:** The app drops all secret views and presents the Calculator or Notes Cover.
4. **Resumption:** When the valid PIN is re-entered, `dpm.setWorkProfileEnabled(admin, true)` restores the space.

---

## 3. Direct Vault Ingestion Pipeline

To avoid leaking sensitive media into the device's public `MediaStore` (Gallery):
1. Cloned apps output files to their private storage or internal cache.
2. Private Vault exposes a `DocumentsProvider` (Cross-Profile Storage Access).
3. Files transferred to Private Vault are encrypted on-the-fly using **AES-256-GCM** (Web Crypto / Android Keystore) and written directly into the encrypted Vault store.
4. The unencrypted temporary file in the clone space is unlinked immediately.

---

## 4. Reference Android Implementation

### `VaultDeviceAdminReceiver.kt`
```kotlin
package io.hiroshimeow.private_vault_mobile.dpc

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class VaultDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        // Work profile setup finished; initialize isolated vault bindings
    }
}
```

### `WorkProfileManager.kt`
```kotlin
package io.hiroshimeow.private_vault_mobile.dpc

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

class WorkProfileManager(private val context: Context) {
    private val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    private val adminComponent = ComponentName(context, VaultDeviceAdminReceiver::class.java)

    fun isProfileOwner(): Boolean = dpm.isProfileOwnerApp(context.packageName)

    fun installExistingApp(packageName: String): Boolean {
        if (!isProfileOwner()) return false
        return dpm.installExistingPackage(adminComponent, packageName)
    }

    fun setSpaceEnabled(enabled: Boolean) {
        if (isProfileOwner()) {
            dpm.setWorkProfileEnabled(adminComponent, enabled)
        }
    }
}
```
