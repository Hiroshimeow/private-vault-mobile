# Private Vault 1.0.0 — Android test build

This APK packages the current React/Vite application with Capacitor 8.5.3. The web bundle and APK are compiled on GitHub Actions from the exact release tag, without a remote application server.

## Installation

Download Private-Vault-1.0.0-DEBUG-TEST-ONLY.apk from this GitHub prerelease and allow installation from that source. Android 7.0/API 24 or later is required. The application ID is me.hculab.privatevault.web, separate from older Flutter builds.

This is a DEBUG-TEST-ONLY APK signed with the GitHub runner's temporary Android debug key. It is not a production-signed release or a Play Store distribution. A later runner's APK may have a different signature: do not uninstall an existing vault to solve an update conflict without preserving your data.

## Verified gates

The publishing workflow requires TypeScript checks, packaging contract tests, production dependency audit, pinned Semgrep source scan, Android debug compilation, an unsigned-production signing rejection, and hosted emulator instrumentation. Emulator tests check initial cover rendering, local HTTPS origin/Web Crypto availability, encrypted IndexedDB round-trip, screen-capture protection and disabled backup. BUILD_INFO.txt identifies the source SHA and GitHub run; SHA256SUMS.txt covers the attached evidence.

## Current limitations

- Apps/YouTube/ReVanced screens are web demonstrations, not real Android app cloning or patched YouTube execution.
- Native biometric unlock, OEM CLONE/Shizuku, isolated browser profiles, Android file export and real camera/sensor behavior have not been accepted on a physical device.
- Vault payloads use the current web application's IndexedDB encryption model, but its master key is persisted in localStorage rather than Android Keystore or PIN-derived protected key storage. A PIN locks the UI; it does not cryptographically protect that persisted key. Do not use this test build for sensitive data.
- This packaging change does not restore the previous Flutter/Portable Vault V2 implementation.
- iOS is not built or distributed by this workflow.
- This release is for testing with synthetic data; production security/device acceptance is incomplete.

## Production signing

No signing key is stored in Git. Android release tasks fail unless VAULT_RELEASE_STORE_FILE, VAULT_RELEASE_STORE_PASSWORD, VAULT_RELEASE_KEY_ALIAS and VAULT_RELEASE_KEY_PASSWORD are supplied. A separate reviewed production signing and acceptance step is required before a production release.
