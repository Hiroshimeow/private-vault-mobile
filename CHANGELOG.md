# Changelog

## 1.0.0-rc.1 — 2026-09-18

Release-candidate hardening for GitHub prerelease evaluation.

### Added
- Android emulator integration gate covering locked launch, wrong PIN non-disclosure, PIN and deterministic biometric unlock, lifecycle relock, panic conceal, vault crypto round-trip/tamper rejection, and browser profile clearing.
- Fail-closed tag/pubspec version contract for `v1.0.0-rc.1`.
- Android backup/data-extraction exclusion and cleartext-traffic denial.
- Tag-triggered prerelease workflow with exact-source evidence, machine-readable test totals, dependency manifest, OSV dependency vulnerability scanning, third-party license inventory, Semgrep, checksums, and explicit signing labels.

### Signing / distribution status
- Android production signing is **not configured**. The current Gradle release build still references the debug signing config and must not be distributed as production-signed.
- RC automation publishes only an installable artifact labeled `DEBUG-TEST-ONLY`.
- iOS validation is compile-only with `--no-codesign`.
- No App Store or Google Play publication is part of RC1.

### Physical-device residuals — NOT EXECUTED
Real biometric/secure-storage persistence, WebView process behavior, camera temporary files, sensors, FLAG_SECURE visual behavior, launcher aliases/OEM refresh, iOS alternate-icon confirmation UX, and Keychain backup/restore behavior remain device-only validation items.
