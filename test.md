# Agent Android build and test guide

This file is the default procedure for an agent validating Android changes in this repository. Do not ask the user to download and install an APK until this local procedure has been attempted and the exact blocker has been reported.

## Local environment

The following tools are already installed on this machine:

```text
Repository:  E:\git-project\private-vault-mobile
Flutter:     E:\git-project\private-vault-mobile\.tooling\flutter
Java 17:     F:\Data\AndroidStudioPlace\Android Studio\jbr
Android SDK: F:\Data\AndroidStudioPlace\sdk
AVD:         private_vault_api34
Device ID:   emulator-5554
```

The ignored file `android/local.properties` must contain the real SDK path:

```properties
sdk.dir=F:\\Data\\AndroidStudioPlace\\sdk
flutter.sdk=E:\\git-project\\private-vault-mobile\\.tooling\\flutter
```

Do not commit `android/local.properties`, `.pub/`, `.dart_tool/`, `build/`, APKs, logs, screenshots, AVD files, or SDK files.

## Required shell setup

Run commands from PowerShell in the repository root unless stated otherwise:

```powershell
Set-Location E:\git-project\private-vault-mobile

$env:JAVA_HOME = 'F:\Data\AndroidStudioPlace\Android Studio\jbr'
$env:ANDROID_HOME = 'F:\Data\AndroidStudioPlace\sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PUB_CACHE = 'E:\git-project\private-vault-mobile\.pub'
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\emulator;$env:Path"

$Flutter = 'E:\git-project\private-vault-mobile\.tooling\flutter\bin\flutter.bat'
$Dart = 'E:\git-project\private-vault-mobile\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe'
$Adb = 'F:\Data\AndroidStudioPlace\sdk\platform-tools\adb.exe'
$Emulator = 'F:\Data\AndroidStudioPlace\sdk\emulator\emulator.exe'
$Avd = 'private_vault_api34'
$Device = 'emulator-5554'
```

`PUB_CACHE` is mandatory on this machine. The repository is on drive `E:` while the default Pub cache is on drive `C:`. Kotlin compilation of Android plugins can fail with `this and base files have different roots` if the default cache is used.

## Preflight

```powershell
& $Flutter --version
& "$env:JAVA_HOME\bin\java.exe" -version
& $Flutter doctor -v
& $Emulator -list-avds
& $Adb devices -l
```

Expected essentials:

- Flutter `3.47.4` and Dart `3.13.3`;
- Java 17;
- Android toolchain accepted;
- AVD `private_vault_api34` listed;
- Android SDK platform 36 and build-tools 36 available.

`flutter doctor` may warn that multiple `adb.exe` files exist. Always use the explicit `$Adb` path above so the same ADB server and device are used throughout the run.

## Start or reuse the emulator

First check whether the configured emulator is already ready:

```powershell
$Booted = (& $Adb -s $Device shell getprop sys.boot_completed 2>$null).Trim()
```

If `$Booted` is not `1`, terminate stale emulator processes and start a fresh headless instance:

```powershell
Get-Process emulator, qemu-system-x86_64-headless -ErrorAction SilentlyContinue |
    Stop-Process -Force

$EmulatorOut = Join-Path $env:TEMP 'private-vault-emulator.stdout.log'
$EmulatorErr = Join-Path $env:TEMP 'private-vault-emulator.stderr.log'

Start-Process -FilePath $Emulator -ArgumentList @(
    '-avd', $Avd,
    '-no-window',
    '-no-snapshot',
    '-no-boot-anim',
    '-no-audio',
    '-gpu', 'swiftshader_indirect',
    '-netdelay', 'none',
    '-netspeed', 'full'
) -RedirectStandardOutput $EmulatorOut -RedirectStandardError $EmulatorErr

$Ready = $false
for ($Attempt = 1; $Attempt -le 120; $Attempt++) {
    $State = (& $Adb -s $Device get-state 2>$null).Trim()
    $Booted = (& $Adb -s $Device shell getprop sys.boot_completed 2>$null).Trim()
    if ($State -eq 'device' -and $Booted -eq '1') {
        $Ready = $true
        break
    }
    Start-Sleep -Seconds 5
}

if (-not $Ready) {
    Get-Content $EmulatorErr -Tail 100 -ErrorAction SilentlyContinue
    throw 'Android emulator did not finish booting within 10 minutes.'
}

& $Adb -s $Device shell settings put global window_animation_scale 0
& $Adb -s $Device shell settings put global transition_animation_scale 0
& $Adb -s $Device shell settings put global animator_duration_scale 0
& $Adb devices -l
& $Flutter devices
```

WHPX is available on this machine. A Vulkan warning can occur with this older emulator version; `-gpu swiftshader_indirect` has been verified to boot the AVD successfully.

## Required verification sequence

### 1. Resolve exactly the locked dependencies

```powershell
& $Flutter pub get --enforce-lockfile
```

Do not run `flutter pub upgrade` as part of normal verification.

### 2. Format and analyze

```powershell
& $Dart format --output=none --set-exit-if-changed lib test integration_test tool
& $Flutter analyze
```

If a listed directory does not exist, remove only that missing directory from the format invocation; do not skip formatting the directories that do exist.

### 3. Run unit, widget, golden, and contract tests

```powershell
& $Flutter test
```

The verified baseline on 2026-09-23 was 97 passing tests. Treat the current command result, not that historical count, as authoritative.

### 4. Run Android integration tests

The emulator must be booted first:

```powershell
& $Flutter test integration_test/private_vault_rc_test.dart -d $Device
```

This suite must prove:

- locked calculator cover does not expose the vault;
- wrong PIN is rejected and the deterministic test PIN unlocks;
- lifecycle pause relocks the app;
- deterministic biometric flow unlocks;
- panic returns to the cover;
- production crypto round-trip works and tampering is rejected;
- browser logical-profile switching clears shared state.

A verified run completed with 3 passing integration tests.

### 5. Build the debug APK

```powershell
& $Flutter build apk --debug
$Apk = 'E:\git-project\private-vault-mobile\build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path $Apk)) {
    throw "APK was not generated at $Apk"
}
Get-Item $Apk | Select-Object FullName, Length, LastWriteTime
```

The generated debug APK is for automated testing only. The repository's current release build also uses debug signing for compile-smoke purposes and must not be represented as a production-signed artifact.

### 6. Install and launch the packaged APK

```powershell
& $Adb -s $Device install -r $Apk
if ($LASTEXITCODE -ne 0) {
    throw 'ADB APK installation failed.'
}

$Package = 'io.hiroshimeow.private_vault_mobile'
& $Adb -s $Device logcat -c
& $Adb -s $Device shell monkey -p $Package -c android.intent.category.LAUNCHER 1
Start-Sleep -Seconds 8

& $Adb -s $Device shell dumpsys window |
    Select-String 'mCurrentFocus|mFocusedApp'
```

Expected focused activity includes:

```text
io.hiroshimeow.private_vault_mobile/.CalculatorAlias
```

This verifies the installed APK launches through the calculator disguise rather than exposing a secret route directly.

### 7. Collect bounded evidence

```powershell
$Evidence = 'E:\git-project\private-vault-mobile\build\agent-evidence'
New-Item -ItemType Directory -Force $Evidence | Out-Null

& $Adb -s $Device logcat -d -t 500 '*:W' |
    Set-Content -Encoding utf8 "$Evidence\logcat-warnings.txt"

$Fatal = Select-String -Path "$Evidence\logcat-warnings.txt" -Pattern @(
    'FATAL EXCEPTION',
    'AndroidRuntime',
    'Process: io.hiroshimeow.private_vault_mobile'
)
if ($Fatal) {
    $Fatal
    throw 'Fatal Android error found after launching the APK.'
}
```

The app enables Android `FLAG_SECURE`. A screenshot can therefore be blank, empty, or blocked and must not be treated as a test failure. Do not disable `FLAG_SECURE` merely to obtain a screenshot. Use integration assertions, focused activity, and bounded logcat output as the normal evidence.

Never collect or commit real personal vault content. Use only synthetic test values.

## Stop the emulator

After testing, stop it unless another active task needs it:

```powershell
& $Adb -s $Device emu kill
```

If that does not terminate it:

```powershell
Get-Process emulator, qemu-system-x86_64-headless -ErrorAction SilentlyContinue |
    Stop-Process -Force
```

## Failure handling

Before asking the user to test manually:

1. Report the exact failed command and the relevant final error lines.
2. Confirm `$env:PUB_CACHE` points to the repository-local `.pub` directory.
3. Confirm `android/local.properties` points to `F:\Data\AndroidStudioPlace\sdk`.
4. Confirm `& $Adb devices -l` shows `emulator-5554` as `device`, not `offline`.
5. For stale Gradle/Kotlin state, run the following once and retry the failing command:

```powershell
& 'E:\git-project\private-vault-mobile\android\gradlew.bat' -p android --stop
& $Flutter clean
& $Flutter pub get --enforce-lockfile
```

6. If boot fails, inspect `$env:TEMP\private-vault-emulator.stderr.log` and retry with a cold boot as documented above.
7. Do not hide a failed integration test by reporting only a successful APK build.

## What the emulator cannot fully prove

A passing local run does not replace physical-device validation for:

- biometric hardware and real enrollment/system prompts;
- Android Keystore persistence across device lock, OS update, backup, or restore;
- real camera lifecycle and plugin-owned temporary files;
- physical shake and face-down sensors;
- screenshot/recents behavior on different OEM builds;
- launcher alias behavior on OEM launchers;
- production release signing;
- iOS Keychain, alternate icon, camera, WebView, or app-switcher behavior.

Ask for focused manual validation only when a change directly affects one of these physical-device or iOS-only boundaries. For ordinary Dart logic, UI, lifecycle, crypto-policy, build, install, and launch changes, complete the automated sequence first and report its evidence.

## Agent completion report

An agent claiming Android verification should report all of the following:

```text
- format: pass/fail
- analyze: pass/fail
- Flutter tests: pass/fail and count
- Android integration tests: pass/fail and count
- debug APK build: pass/fail and exact path
- APK install: pass/fail
- launched activity: exact focused activity
- fatal logcat scan: clean/findings
- emulator-only limitations relevant to the change
```
