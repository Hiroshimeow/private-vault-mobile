# Private Vault Mobile

[![CI](https://github.com/Hiroshimeow/private-vault-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/Hiroshimeow/private-vault-mobile/actions/workflows/ci.yml)
[![SAST](https://github.com/Hiroshimeow/private-vault-mobile/actions/workflows/sast.yml/badge.svg)](https://github.com/Hiroshimeow/private-vault-mobile/actions/workflows/sast.yml)

A local-first Flutter privacy utility for Android and iOS. This is an original implementation based only on public behavior descriptions of privacy-vault products; it does not reuse third-party proprietary code, branding, copy, assets, or store metadata.

## V1

- Functional locked covers: **Calculator** and **Notes/Todo**.
- PIN unlock stored as a salted PBKDF2 verifier in platform secure storage.
- Optional biometric unlock through Android/iOS platform authentication.
- AES-256-GCM authenticated encryption for local vault payloads.
- Protected notes plus image/video/document import, camera capture, transient viewing, delete, and explicit export.
- Embedded HTTPS browser with sequential ephemeral logical profiles and configurable clear-on-close.
- Direct HTTPS download-to-vault with a 25 MiB bound.
- Shake and face-down panic conceal with threshold, delay, and debounce controls.
- Background auto-lock.
- Android `FLAG_SECURE`; iOS app-switcher privacy cover.
- Android predeclared Calculator/Notes launcher aliases and icons.
- iOS predeclared alternate icon only; the runtime display name does not change.
- No analytics, ads, remote backend, or cloud sync by default.

## V1.2 — Android isolated apps

Android native app isolation uses the platform `android.os.usertype.profile.CLONE` user type when the OEM exposes it. Private Vault requests the required privileged operations through an allowlisted Shizuku UserService; it does **not** provision or reuse a managed Work Profile.

- Clone-profile creation is explicit and scoped to the current Android parent user.
- Package list/install/launch/uninstall operations always include the proven clone user id.
- Private Vault stores only the clone user id that it created. An existing OEM/third-party clone profile is treated as a conflict and is never adopted, modified, or removed.
- A cloned package starts with separate private app data for that Android user. Private Vault does not claim complete storage isolation because clone-profile shared-storage behavior can vary by Android/OEM implementation.
- If Shizuku is unavailable or not authorized, the Apps surface reports `privilege_required`; there is no managed-Work-Profile fallback.
- If the OEM explicitly rejects or omits the CLONE user type, the Apps surface reports `clone_profile_unsupported_by_oem`. Policy/capacity/ambiguous create failures remain generic operation failures.
- Locking Private Vault does not stop an already-running cloned app outside the Flutter process.
- iOS has no Android clone-profile equivalent and is not presented as having native app cloning.
- This is an independent Android implementation. No Shelter/Insular GPL source is vendored or copied.

## Security posture

V1 targets **casual-inspection and accidental-exposure privacy**, including a locked secret UI, authenticated encryption at rest, app-switcher/screenshot hardening, gallery-leak reduction, generic failure messages, and fail-closed missing-key/ciphertext handling.

It does **not** claim protection against:

- root/jailbreak or a malicious/compromised OS;
- privileged forensic tooling or hardware attacks;
- coercion or compelled disclosure;
- compromise while plaintext is legitimately displayed;
- physical secure erase on flash storage;
- network anonymity from the embedded WebView.

See [SECURITY.md](SECURITY.md) and [docs/design/THREAT_MODEL.md](docs/design/THREAT_MODEL.md).

## Important platform limits

### Android Clone Profile

Clone-profile behavior depends on Android framework enforcement, the OEM implementation of `profile.CLONE`, and an authorized Shizuku service. Build/unit tests do not by themselves prove clone-profile E2E behavior; runtime claims require a legal emulator or physical-device target that actually exposes the CLONE user type.

Private Vault requests launcher-intent package visibility rather than `QUERY_ALL_PACKAGES`. Privileged package operations are fixed and user-scoped; the app does not expose arbitrary shell execution.

### Browser profiles

The cross-platform WebView layer exposes a shared cookie/storage surface. V1 therefore implements **sequential ephemeral profiles**: switching profiles clears cookies, cache, and local storage before entering the next logical profile. It does not promise simultaneously retained independent cookie jars.

Direct HTTPS downloads use a separate HTTP client and are encrypted into the vault. Authenticated downloads that require WebView cookies are not supported in V1.

### Media

Imported files are read and encrypted into app-private storage; the original user-selected source remains where it already existed. Camera capture is read into the vault and plugin-owned temporary capture data is deleted on a best-effort basis. The app does not intentionally save captured media to the public gallery.

Export is always an explicit item action. Confirmation is enabled by default and may be disabled in Settings. An exported copy is outside vault protection.

### Deletion

Deleting an item removes the app-level ciphertext and metadata file. Flash wear leveling, snapshots, backups, and filesystem behavior mean this is **not** a forensic secure erase guarantee.

### Clipboard and logs

V1 exposes no secret-copy action and does not intentionally place decrypted vault content on the clipboard. Production Dart source has a contract test that forbids direct `print`/`debugPrint` logging and known synthetic secret fixtures.

## Architecture

```text
lib/
  app/                 app shell, lock-aware routing, settings wiring
  core/
    crypto/            authenticated encryption
    storage/           platform secure-storage abstraction
  features/
    apps/              Android Clone/Shizuku contract, client, isolated-app UI
    auth/              PIN, biometric, lock lifecycle
    browser/           WebView fallback, ephemeral profile policy, download-to-vault
    cover/             Calculator and Notes/Todo covers
    media/             import, camera, explicit export
    panic/             sensor normalization and trigger policy
    settings/          persisted non-secret settings
    vault/             encrypted repository and vault UI
  platform/            platform bridge wrappers + launcher/alternate-icon bridge
```

The UI depends on explicit feature/repository interfaces. Platform plugins are wrapped so security-critical policy is unit-testable without device state.

## Local setup

Flutter is intentionally not committed. Use either an existing Flutter 3.47.4 installation or a workspace-local SDK:

```powershell
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git .tooling/flutter
.\.tooling\flutter\bin\flutter.bat pub get
```

This repository was developed against:

- Flutter 3.47.4 stable
- Dart 3.13.3
- Java 17 for Android CI

Some restricted Windows shells omit `ProgramFiles(x86)`. In that environment, set it only for the current shell before Flutter test/analyze commands:

```powershell
Set-Item -Path 'Env:ProgramFiles(x86)' -Value 'C:\Program Files (x86)'
Set-Item -Path 'Env:ProgramW6432' -Value 'C:\Program Files'
```

No system-wide PATH or environment change is required.

## Verification

With workspace-local Flutter:

```powershell
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe format --output=none --set-exit-if-changed lib test
.\.tooling\flutter\bin\flutter.bat analyze
.\.tooling\flutter\bin\flutter.bat test
```

With Flutter already on PATH:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Builds

Android requires an installed Android SDK/cmdline-tools and Java 17:

```bash
flutter build apk --debug
flutter build apk --release
```

Android release builds never fall back to debug signing. Configure production signing through the ignored `android/key.properties` file (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) or the `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` environment variables. Missing signing inputs fail closed before release-capable app tasks run.

iOS requires macOS/Xcode:

```bash
flutter build ios --release --no-codesign
```

Installing on a device or publishing to the App Store requires normal Apple signing/provisioning.

## CI

`.github/workflows/ci.yml` runs on pushes to `main`, pull requests, and manual dispatch:

- Linux: dependency resolution, format gate, `flutter analyze`, full tests, security-contract tests.
- Android: Java 17, native bridge code compilation through the APK builds, debug APK build, release APK compile smoke, debug APK artifact upload.
- iOS/macOS: release build with `--no-codesign`.

Flutter SDK and pub caches use the Flutter Action's maintained GitHub cache integration.

`.github/workflows/sast.yml` is an independent source-security gate using pinned **Semgrep CE 1.177.0**. It runs the community `p/security-audit` pack plus repository-owned rules in `.semgrep.yml`, fails on `ERROR` findings, and uploads a SARIF report artifact. Repository rules explicitly cover Dart, Kotlin, and Swift for mobile-specific high-risk patterns such as TLS validation bypass, cleartext HTTP literals, Android WebView debugging, and manual iOS server-trust credentials. Dart support in Semgrep is less mature than Kotlin/Swift, so this is a bounded SAST layer rather than a claim of complete vulnerability detection. The scanner runs locally in GitHub Actions and does not depend on GitHub Advanced Security.

`.github/workflows/dependency-review.yml` runs on pull requests only when repository variable `ENABLE_DEPENDENCY_REVIEW=true`. GitHub Dependency Review on private repositories requires GitHub Advanced Security; leaving the variable unset prevents a false failing gate when that capability is unavailable.

## Documentation

- [Product spec](docs/spec/PRODUCT_SPEC.md)
- [Architecture](docs/design/ARCHITECTURE.md)
- [Threat model](docs/design/THREAT_MODEL.md)
- [UX flows](docs/design/UX_FLOWS.md)
- [Android Clone Profile device checklist](docs/testing/CLONE_PROFILE_DEVICE_CHECKLIST.md)
- [Implementation plan](docs/plan/IMPLEMENTATION_PLAN.md)
- [Security policy](SECURITY.md)

No personal-data screenshots or fixtures are committed. Tests use deterministic synthetic values only; any future screenshots must also use synthetic/demo data.
