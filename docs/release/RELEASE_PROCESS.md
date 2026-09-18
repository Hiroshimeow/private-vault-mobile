# RC Release Process

## Version contract

RC tags use `vMAJOR.MINOR.PATCH-rc.N`. The source `pubspec.yaml` version before the `+build` suffix must exactly match the tag without the leading `v`.

For RC1:
- tag: `v1.0.0-rc.1`
- pubspec: `1.0.0-rc.1+1`

The release workflow runs:

```
dart run tool/check_release_version.dart "$GITHUB_REF_NAME"
```

A mismatch fails closed.

## Required gates

The tag workflow checks out the exact tag and records its commit SHA, then resolves dependencies with `flutter pub get --enforce-lockfile` so the committed `pubspec.lock` is fail-closed. It then requires formatting, static analysis, full Flutter tests, explicit security contract tests, OSV-Scanner v2.6.0 dependency vulnerability scanning against `pubspec.lock`, pinned Semgrep, hosted Android-emulator integration, Android debug test artifact build, and iOS no-codesign compile smoke.

GitHub prerelease creation is downstream of all required jobs.

## Artifact truth model

There is no production Android signing key in this repository. `android/app/build.gradle.kts` currently points the release build type at the debug signing config.

Therefore RC1:
- does not claim production signing;
- does not publish a debug-key-signed release APK;
- may publish only the debug APK under a `DEBUG-TEST-ONLY` filename;
- builds iOS only with `--no-codesign`;
- does not publish to App Store or Google Play.

A future production release requires externally managed signing credentials and a separate reviewed signing design.

## Reproducibility evidence

The release bundle includes:
- exact Git commit SHA;
- dependency manifest generated from the resolved Flutter package graph;
- deterministic third-party license inventory generated from resolved package roots;
- machine-readable unit/widget and Android-emulator test logs plus summarized test totals;
- Semgrep SARIF;
- release evidence markdown that records the required OSV vulnerability gate status;
- SHA-256 checksums for attached evidence/assets.

The dependency manifest is intentionally called a dependency manifest, not an SBOM, because RC1 does not introduce an additional pinned SBOM generator.

## Rebuild / rollback

Do not move or overwrite an existing RC tag. If source or evidence changes, create a new reviewed RC number. Failed workflows do not publish a prerelease because publication depends on all required jobs.

## Residual physical-device validation

Hosted emulator PASS is not evidence for real biometric/secure-storage persistence, WebView process-level behavior, camera temporary-file lifecycle, sensors, FLAG_SECURE screenshots/recents, launcher alias refresh on OEM launchers, iOS alternate-icon confirmation, or Keychain behavior across device lock/backup/restore. Those remain NOT EXECUTED until fresh device evidence is recorded.
