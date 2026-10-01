# Android Clone Profile Device Checklist

Use this checklist only on a device or emulator you are authorized to modify.

## Preconditions
- Private Vault debug/acceptance build is installed.
- Shizuku is installed, running, and available to Private Vault.
- The device/OEM exposes `android.os.usertype.profile.CLONE`.
- No unrelated clone profile will be created, adopted, modified, or removed for this test.

## Capability states
1. With Shizuku stopped or authorization denied, open Apps and verify `privilege_required`.
2. Start Shizuku, authorize once, and verify Apps refreshes without managed-Work-Profile provisioning.
3. On a device that explicitly lacks/rejects CLONE user type, verify `clone_profile_unsupported_by_oem`.
4. If an unowned clone profile already exists, verify `conflicting_external_clone_profile` and stop; do not mutate it.

## Owned clone flow
1. On a clean supported target, choose one synthetic/test app and invoke Clone.
2. Verify Android creates one `profile.CLONE` under the current parent user.
3. Verify Private Vault only persists ownership after the created user id matches post-create discovery.
4. Verify package installation targets only that clone user.
5. Verify the personal-user package/data remains unchanged.
6. Launch the cloned app and confirm separate private app state for the clone user.
7. Remove the clone package and confirm the personal-user package remains installed.

## Failure behavior
- Force/observe a failed `start-user`; verify install/launch does not proceed.
- Verify operation errors remain bounded and the UI stays retryable.
- Verify Browser remains a separate user-selected surface and is never an automatic fallback.
- Do not claim full storage isolation: shared-storage behavior is OEM/platform dependent.

## Evidence
Record device model, Android build, Shizuku version/state, clone user id, commands/results needed to prove user scoping, and the exact app build/commit. Never label build/unit evidence alone as clone-profile E2E proof.
