# Shelter-style Clone + Hidden Unlock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a real Android Work Profile clone workspace modeled on Shelter's supported behavior, add concealed Calculator PIN→biometric unlock, and connect cloned apps to encrypted Vault through a bounded file shuttle.

**Architecture:** Keep Flutter as UI/state owner and Kotlin as Android policy/install/profile owner. Reuse the existing Pigeon WorkProfileHostApi prototype; harden it rather than replacing it. Use clean-room behavioral reimplementation from Android public APIs and Shelter failure modes; do not copy GPL source.

**Tech Stack:** Flutter 3.47.4/Dart 3.13, Kotlin/Android API 24–36, DevicePolicyManager, PackageInstaller, UserManager, Pigeon, flutter_secure_storage/local_auth, existing AES-GCM vault.

## Global Constraints

- No copied Shelter source, strings, assets, or branding; Shelter is GPL-3.0 reference only.
- No root/ADB/Shizuku/virtualization.
- Android Work Profile is the only app-clone mechanism.
- iOS app cloning remains unsupported.
- Biometric app UI is hidden, but OS BiometricPrompt remains mandatory.
- No claim that Vault encrypts arbitrary cloned-app private databases.
- Preserve existing vault, browser, panic, confidentiality-boundary, RC2 polish, and unrelated dirty work.
- TDD for every state transition and native policy helper.
- Android work-profile success requires API 36 device/emulator evidence; source-only tests cannot close it.

---

### Task 1: Preserve existing Work Profile prototype and integrate RC2 main

**Files:**
- Existing dirty Work Profile files in this worktree.
- Merge source: `main` at or after `4be30c592e70e18142fb3b47056cec2682cdb923`.
- Test: `test/unit/work_profile_*_test.dart`, `test/widget/work_profile_*_test.dart`.

**Interfaces:**
- Consumes: current `WorkProfileClient`, `WorkProfileHostApiAdapter`, `WorkProfileBridgeActivity`.
- Produces: a clean feature branch containing both RC2 polish and existing Work Profile prototype.

- [ ] **Step 1: Freshly verify the prototype-specific tests before committing it.**

Run:
```powershell
.\.tooling\flutter\bin\flutter.bat test test/unit/work_profile_models_test.dart test/unit/work_profile_native_contract_test.dart test/unit/work_profile_android_contract_test.dart test/widget/work_profile_home_test.dart test/widget/work_profile_navigation_test.dart
```
Expected: all tests pass.

- [ ] **Step 2: Commit only the existing Work Profile prototype as a baseline slice.**

```powershell
git add .github/workflows/ci.yml README.md android app docs lib pigeons pubspec.yaml pubspec.lock test/unit/work_profile_* test/widget/work_profile_*
git commit -m "feat: preserve work profile clone prototype"
```

- [ ] **Step 3: Merge current main into the feature branch.**

```powershell
git fetch origin
git merge --no-ff origin/main
```
Resolve conflicts by preserving both RC2 confidentiality/polish behavior and Apps navigation. Never discard either side wholesale.

- [ ] **Step 4: Run full Flutter regression.**

```powershell
.\.tooling\flutter\bin\flutter.bat analyze
.\.tooling\flutter\bin\flutter.bat test
```
Expected: analyze clean; all non-platform-specific tests pass.

---

### Task 2: Concealed Calculator PIN → biometric unlock

**Files:**
- Modify: `lib/features/cover/calculator_cover.dart`
- Modify: `lib/app/private_vault_app.dart`
- Modify: `lib/features/auth/secure_unlock_service.dart`
- Modify: `lib/features/auth/biometric_unlock.dart`
- Modify: `lib/features/settings/app_settings.dart`
- Test: `test/widget/locked_shell_test.dart`
- Test: `test/unit/secure_unlock_service_test.dart`

**Interfaces:**
- Produces: `CalculatorCover.onSecretDigits(String digits)` callback or equivalent bounded digit feed.
- Produces: `HiddenUnlockCoordinator.submitDigits(String digits)` semantics inside app shell; no visible biometric button required.
- Unlock policy values: `pinOnly`, `pinThenBiometric`.

- [ ] **Step 1: Add failing widget tests.**

Tests must prove:
```dart
// Correct PIN digits typed through calculator do not open a PIN sheet.
// Wrong digits reveal no secret text.
// Under pinThenBiometric, correct PIN invokes biometric exactly once.
// Biometric success unlocks; cancel/failure remains on Calculator.
// Arithmetic output remains correct.
```

- [ ] **Step 2: Run the focused tests and confirm RED.**

```powershell
.\.tooling\flutter\bin\flutter.bat test test/widget/locked_shell_test.dart test/unit/secure_unlock_service_test.dart
```

- [ ] **Step 3: Implement a bounded digit matcher independent of calculator expression state.**

Required behavior:
```dart
void recordDigit(String digit) {
  _secretDigits = (_secretDigits + digit);
  if (_secretDigits.length > maxConfiguredPinLength) {
    _secretDigits = _secretDigits.substring(_secretDigits.length - maxConfiguredPinLength);
  }
  onSecretDigits?.call(_secretDigits);
}
```
Do not expose whether any prefix is correct.

- [ ] **Step 4: Auto-trigger biometric only after verified PIN.**

```dart
if (await unlockService.verifyPin(candidate)) {
  if (settings.unlockPolicy == UnlockPolicy.pinThenBiometric) {
    final ok = await biometricUnlock.authenticate();
    if (!ok) return;
  }
  await lockController.unlock();
}
```

- [ ] **Step 5: Remove Calculator-cover fingerprint/PIN affordances from locked UI and make long-press fallback opt-in.**

No hidden workspace terminology may appear in semantics while locked.

- [ ] **Step 6: Run focused + full regression and commit.**

```powershell
.\.tooling\flutter\bin\flutter.bat test test/widget/locked_shell_test.dart test/unit/secure_unlock_service_test.dart
.\.tooling\flutter\bin\flutter.bat test
git add lib test
git commit -m "feat: add concealed calculator biometric unlock"
```

---

### Task 3: Harden Work Profile bridge readiness and quiet-mode recovery

**Files:**
- Modify: `android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt`
- Modify: `android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt`
- Modify: `android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileNativePolicy.kt`
- Modify: `pigeons/work_profile_api.dart`
- Regenerate: Pigeon Dart/Kotlin outputs.
- Test: `android/app/src/test/.../WorkProfileNativePolicyTest.kt`
- Test: `test/unit/work_profile_native_contract_test.dart`

**Interfaces:**
- New errors: `profileQuiet`, `bridgeTimeout`.
- Helper: `awaitPackageState(packageName, predicate, timeoutMs)`.
- Helper: `ensureProfileAvailable()` must be single-flight.

- [ ] **Step 1: Add failing native-policy tests for quiet profile, bridge timeout, and package convergence.**

Example:
```kotlin
@Test fun launchPollingTimesOutDeterministically() {
    assertEquals(false, WorkProfileNativePolicy.shouldContinuePolling(elapsedMs = 3100, timeoutMs = 3000))
}
```

- [ ] **Step 2: Add bounded bridge timeout independent of installer confirmation timeout.**

Read/list/launch readiness uses ~5s; install/uninstall user-confirmation operations retain their longer timeout.

- [ ] **Step 3: Detect managed profile quiet mode.**

Use `UserManager.isQuietModeEnabled(userHandle)` where supported. If quiet, request Android-supported profile enable/wake flow; if user/system refuses, return `profileQuiet` instead of hanging.

- [ ] **Step 4: Make readiness single-flight.**

Multiple Flutter refreshes must share one in-flight readiness operation rather than launch multiple profile-forwarding activities.

- [ ] **Step 5: Add package-state polling after enable/install/unhide.**

Poll at 100–200 ms intervals with a hard 3 s bound. Never sleep on the main/UI thread.

- [ ] **Step 6: Run native contract tests and commit.**

```powershell
.\android\gradlew.bat testDebugUnitTest
.\.tooling\flutter\bin\flutter.bat test test/unit/work_profile_native_contract_test.dart
git add android pigeons lib/platform/generated test
git commit -m "fix: harden work profile bridge readiness"
```

---

### Task 4: Shelter-style clone/open/freeze UX

**Files:**
- Modify: `lib/features/apps/work_profile_home.dart`
- Modify: `lib/features/apps/work_profile_models.dart`
- Modify: `lib/features/apps/work_profile_client.dart`
- Native app icon transport as needed through Pigeon.
- Test: `test/widget/work_profile_home_test.dart`
- Test: `test/widget/work_profile_navigation_test.dart`

**Interfaces:**
- App inventory exposes icon bytes/URI or deterministic fallback.
- Filters: `personal`, `isolated`.
- Primary actions: Personal→Clone; Isolated→Open.

- [ ] **Step 1: Add failing widget tests for two-filter inventory and direct primary actions.**

Required assertions:
```dart
// Personal filter never shows destructive work-only controls.
// Isolated filter tap opens app.
// Clone success moves/relabels app state after refresh.
// Freeze visibly changes Open semantics to Unfreeze/Open.
```

- [ ] **Step 2: Replace generic card list with app-centric grid/list using actual icons.**

Keep one-tap common actions; destructive actions remain overflow/confirmation.

- [ ] **Step 3: Provisioning screen becomes one Private Vault action plus Android system flow.**

Do not add another internal wizard.

- [ ] **Step 4: Add OEM/policy-specific actionable messages.**

Examples:
- direct APK clone blocked → install Play/OEM store inside work profile;
- conflicting enterprise profile → do not take ownership;
- package lacks launchable activity → clone allowed but Open unavailable.

- [ ] **Step 5: Run widget tests + full regression and commit.**

---

### Task 5: Reliable launch/unfreeze/install behavior

**Files:**
- Modify: `WorkProfileBridgeActivity.kt`
- Modify: `WorkProfileHostApiAdapter.kt`
- Test native policy and Flutter client result mapping.

**Interfaces:**
- `launchWorkApp(packageName)` becomes:
  1. ensure profile available;
  2. unhide/unfreeze;
  3. await package visible and launchable;
  4. launch;
  5. return success only after launch dispatch.

- [ ] **Step 1: Add RED tests for launch-after-unfreeze race.**
- [ ] **Step 2: Implement bounded package/activity polling off UI thread.**
- [ ] **Step 3: Preserve PackageInstaller status callback as authoritative install result.**
- [ ] **Step 4: Verify system-app enable, split APK clone, blocked-install fallback, freeze/unfreeze, hide/unhide, uninstall.**
- [ ] **Step 5: Commit `fix: make cloned app lifecycle deterministic`.**

---

### Task 6: Vault Shuttle

**Files:**
- Create: `lib/features/apps/vault_shuttle_service.dart`
- Create: Android read-only shuttle provider under Private Vault package.
- Modify: `vault_home.dart` / Apps action surface.
- Modify: lock/panic confidentiality cleanup hooks.
- Test: unit shuttle lifecycle tests and Android contract tests.

**Interfaces:**
```dart
abstract interface class VaultShuttleService {
  Future<Uri> stageForIsolatedApp(String vaultItemId);
  Future<String> importFromContentUri(Uri uri, {required String displayName});
  Future<void> purgeStagedPlaintext();
}
```

- [ ] **Step 1: RED tests: stage creates no public file; lock invokes purge; import streams into encrypted vault.**
- [ ] **Step 2: Implement short-lived app-private plaintext staging with random opaque names.**
- [ ] **Step 3: Expose only read-only content URI grants to selected target app/profile.**
- [ ] **Step 4: Work→Vault import streams into existing repository encryption and releases permission.**
- [ ] **Step 5: Wire manual/panic/background lock to purge staged plaintext.**
- [ ] **Step 6: Commit `feat: add encrypted vault shuttle for isolated apps`.**

---

### Task 7: Real Android acceptance

**Files:**
- Update: `docs/testing/WORK_PROFILE_DEVICE_CHECKLIST.md`
- CI: add API 36 emulator job only where managed-profile provisioning is actually supported; otherwise keep as documented device gate.

- [ ] **Step 1: Build Android on API 36 toolchain.**
- [ ] **Step 2: Provision work profile on supported emulator/device.**
- [ ] **Step 3: Clone a normal single APK and an app with split APKs.**
- [ ] **Step 4: Verify main-profile app/data remain intact.**
- [ ] **Step 5: Verify freeze/unfreeze, hide/unhide, open, uninstall, remove profile.**
- [ ] **Step 6: Turn profile quiet/off and verify recoverable UX/no hang.**
- [ ] **Step 7: Verify Vault Shuttle both directions and purge on lock.**
- [ ] **Step 8: Run full Flutter tests/analyze, Android unit tests, CI/SAST, independent REVIEW.**

---

### Task 8: Media gallery + Move to Vault follow-up

Only begin after Task 7 is green.

**Files:**
- Modify: `lib/features/vault/vault_home.dart`
- Modify: `lib/features/media/media_vault_service.dart`
- Extend metadata for encrypted thumbnail or safe in-memory thumbnail strategy.
- Add source-delete platform bridge using MediaStore/SAF.

- [ ] **Step 1: Build lazy thumbnail gallery with bounded decode/cache.**
- [ ] **Step 2: Separate Copy to Vault vs Move to Vault.**
- [ ] **Step 3: Move path encrypts + verifies first, then requests source deletion.**
- [ ] **Step 4: Deletion denial reports source retained, never rolls back valid encrypted copy.**
- [ ] **Step 5: Test large gallery scrolling, source-retained behavior, and lock cleanup.**

## Self-review

- Covers concealed PIN+biometric flow without impossible hidden biometric claim.
- Reuses current Work Profile prototype instead of rewriting.
- Incorporates Shelter PR #320 failure lessons without copying GPL code or adopting its process-kill watchdog.
- Includes actual split APK clone, profile lifecycle, freeze/unfreeze, install/uninstall and real-device gate.
- Integrates Vault through file shuttle rather than false transparent encryption claim.
- Defers gallery/source-delete polish until clone acceptance, matching current user priority.
- No TODO/TBD placeholders.
