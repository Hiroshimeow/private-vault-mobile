# Shelter-style Clone + Hidden Unlock Design

## Goal

Turn Private Vault Mobile into an Android privacy workspace centered on:
1. concealed unlock from the Calculator cover;
2. real app duplication/isolation through Android Managed Work Profile;
3. encrypted Vault file exchange with cloned apps.

## Research constraints

- Shelter is GPL-3.0. Private Vault may study its behavior, failure modes, and Android API choices, but must not copy Shelter source code.
- Managed Work Profile is the supported isolation primitive. No root, ADB privilege, virtualization, package-name rewriting, or fake native-app cloning.
- Android provisioning remains system-owned. Private Vault minimizes its own setup screens but cannot remove Android's consent/provisioning UI.
- AndroidX BiometricPrompt is system-provided. Private Vault can hide its own fingerprint button/icon, but cannot suppress the system biometric prompt.
- Cloned app internal data remains owned by Android's work profile. Private Vault cannot transparently encrypt arbitrary cloned-app internal databases without root/virtualization.

## Concealed unlock

- Calculator remains fully usable.
- Numeric key presses also feed a bounded secret PIN matcher.
- Locked Calculator shows no unlock affordance, fingerprint icon, biometric button, vault terminology, or PIN field.
- When the rolling numeric input matches the configured PIN:
  - PIN-only policy unlocks immediately;
  - PIN+biometric automatically invokes the OS biometric prompt;
  - only biometric success opens the secret workspace;
  - cancel/failure returns silently to Calculator.
- Wrong sequences reveal nothing.
- Existing long-press unlock becomes optional fallback disabled by default for Calculator.

## Work Profile / clone apps

### One-time setup
- Secret workspace exposes Apps.
- If no managed profile exists and provisioning is allowed, show one primary action: Enable isolated apps.
- It launches Android ACTION_PROVISION_MANAGED_PROFILE.
- After provisioning, return directly to Apps.

### App list
- Filters: Personal and Isolated.
- Show actual icon, label, state; package name only in details.
- Personal app primary action: Clone.
- Isolated app primary tap: Open.
- Secondary actions: Freeze/Unfreeze, Hide/Unhide, Uninstall from isolated profile.
- System apps use DevicePolicyManager.enableSystemApp when permitted.
- Non-system apps transfer base APK plus split APKs and install through PackageInstaller.
- OEM/policy blocks return precise fallback states.

### Reliability
- Never block Flutter/UI thread waiting for cross-profile readiness.
- Cross-profile operations have bounded timeout and retry states.
- Only one bridge readiness attempt may run at once.
- Detect quiet/disabled work profile and request wake through supported APIs where available.
- After install/unhide/unfreeze, poll PackageManager for bounded convergence before reporting success.
- Launch unhide/unfreezes first, polls for launchable activity, then starts it.
- Do not adopt Shelter PR #320's process-killing watchdog.

## Vault Shuttle

- Vault remains encrypted and app-private.
- Open in isolated app: decrypt selected item to short-lived app-private temp, expose read-only content URI, delete temp on completion/timeout/lock best-effort.
- Save to Vault: accept Android content URI from work profile and stream directly into Vault encryption.
- No MANAGE_EXTERNAL_STORAGE requirement for this flow.
- No claim that cloned-app private databases are encrypted by Vault.

## Media UX follow-up

After clone flow reaches real-device acceptance:
- image vault becomes a lazy thumbnail grid;
- import defaults to Copy to Vault and states source remains;
- Move to Vault encrypts and verifies first, then requests source deletion via MediaStore/SAF;
- denied deletion leaves encrypted copy and reports source-retained;
- no forensic deletion claim.

## Acceptance

### Concealed unlock
- Enter configured PIN on Calculator without opening unlock UI.
- Correct PIN under PIN+biometric automatically starts OS biometric prompt.
- Success unlocks; failure/cancel remains Calculator.
- Wrong PIN reveals nothing.
- Arithmetic remains correct.

### Clone
- Capability is truthful.
- API 36 supported device/emulator can provision managed profile.
- Personal and isolated inventories differ correctly.
- Normal APK clone handles split APKs.
- Freeze/unfreeze, hide/unhide, open, uninstall affect work profile only.
- Main-profile copy/data remain intact.
- Quiet/off work-profile state is recoverable, never a hung UI.

### Vault Shuttle
- Vault file opens/shares to cloned app without permanent public plaintext copy.
- Work-profile content imports into encrypted Vault.
- Lock/panic purges decrypted shuttle temp best-effort.

## Non-goals
- iOS native app cloning.
- Bypassing enterprise/device-owner policy.
- Root/ADB/Shizuku installation.
- Transparent encryption of arbitrary cloned-app internal data.
- Copying Shelter source, UI text, branding, or assets.
