# Private Vault Mobile

A local-first Flutter privacy utility for Android and iOS. The product is an original implementation based only on public behavior descriptions of privacy-vault apps; it does not reuse third-party proprietary code, branding, assets, copy, or store metadata.

## Security posture

V1 targets casual-inspection privacy: locked cover workspace, authenticated local encryption, lifecycle relock, app-switcher/screenshot hardening, controlled export, and isolated in-app browsing where platform APIs permit it. It does **not** claim protection against root/jailbreak, a malicious OS, privileged forensic tooling, coercion, or physical secure erase on flash storage.

See `SECURITY.md` and `docs/design/THREAT_MODEL.md` for the exact model and limits.

## Repository layout

- `docs/spec/PRODUCT_SPEC.md` — product contract
- `docs/design/` — architecture, threat model, UX flows
- `docs/plan/IMPLEMENTATION_PLAN.md` — implementation sequence
- `lib/core/` — security/storage primitives
- `lib/features/` — feature boundaries
- `test/` — unit/widget tests
- `android/`, `ios/` — platform shells and native privacy bridges

## Local toolchain

The repository can use a workspace-local Flutter SDK under `.tooling/flutter` so machine-wide PATH changes are unnecessary.

```powershell
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git .tooling/flutter
.\.tooling\flutter\bin\flutter.bat pub get
```

Some restricted Windows shells omit `ProgramFiles(x86)`. In that environment only, set it for the current shell before running Flutter tests; do not modify the system environment.

## Verification

```powershell
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe format --set-exit-if-changed lib test
.\.tooling\flutter\bin\flutter.bat analyze
.\.tooling\flutter\bin\flutter.bat test
```

Android/iOS build verification and GitHub Actions are part of the V1 delivery gate. iOS installation/App Store delivery requires normal Apple signing and is not performed by this repository automatically.
