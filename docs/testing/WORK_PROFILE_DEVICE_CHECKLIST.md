# Android Work Profile Verification

This checklist is the runtime acceptance lane for V1.2. Build, static analysis,
and unit/contract tests are not substitutes for these checks.

## Preconditions

- Use synthetic/demo accounts and files only.
- Start from a device where Private Vault is not already a Profile Owner.
- Record Android version, OEM/model, Private Vault build SHA, and whether an
  employer/other-DPC work profile already exists.
- Run at least one Pixel/AOSP-like device and one Samsung-class device before
  claiming broad OEM support.

## Provisioning and conflict

1. Unlock Private Vault and open **Apps**.
2. Verify Apps appears before Browser on Android.
3. On a device without managed-user support, verify the unsupported state.
4. On a clean supported device, tap **Set up work profile** and complete the
   Android system provisioning UI.
5. Verify Android work-profile badging appears and Private Vault reports ready.
6. On a device with an incompatible existing employer/other-DPC work profile,
   verify Private Vault refuses takeover and reports a conflict/policy state.

## Ordinary app clone

1. Install a deterministic fixture app in the personal profile.
2. Ensure the fixture has separate base/split APK variants for the split test.
3. In Private Vault, clone the fixture.
4. Complete any Android install-source or package confirmation UI.
5. Verify the same package exists independently in personal and work profiles.
6. Launch the work-profile copy and verify it starts with fresh app data and no
   inherited account/session state.
7. Repeat with a split APK fixture and verify launch succeeds.
8. On an OEM that rejects direct APK copy, verify Private Vault reports the
   limitation and does not claim success; use Play/OEM-store or Browser fallback.

## System app path

1. Select an eligible system app not already enabled in the work profile.
2. Clone/enable it.
3. Verify the work-profile instance appears and launches.
4. Verify no APK-copy success is claimed for an ineligible system package.

## Work-profile controls

For an installed work-profile fixture:

1. **Open** launches the work-profile copy.
2. **Freeze** prevents normal use according to Android policy.
3. **Unfreeze** restores launch.
4. **Hide** removes normal visibility where the device/API supports it.
5. **Unhide** restores visibility.
6. **Uninstall** removes only the work-profile copy.
7. Verify the personal-profile installation remains installed and usable.

## Privacy and lock boundary

1. Lock Private Vault while the cloned app is already running.
2. Verify the Private Vault cover shows no app/package metadata.
3. Verify locking Private Vault does **not** falsely claim to stop the running
   clone.
4. Reopen Private Vault and verify **Freeze** remains a separate explicit action.
5. Verify no default cross-profile clipboard copy path is exposed.
6. Verify no cross-profile contacts/files path is exposed by Private Vault.

## Profile destruction

1. Tap **Remove work profile**.
2. Verify the dialog explicitly warns that all work-profile app data/accounts
   are deleted.
3. Cancel once and verify the profile remains.
4. Confirm removal.
5. Verify the work profile and its app data are gone.
6. Verify corresponding personal-profile apps/data remain.

## Evidence

For each device, record:

- device/OEM + Android version
- build SHA
- provisioning result
- ordinary base APK result
- split APK result
- store fallback result
- system-app result
- launch/freeze/hide/uninstall result
- profile destruction result
- lock-boundary result
- any OEM-specific error message

Do not label an emulator or physical-device run as passing if provisioning was
skipped or if only build/unit tests ran.
