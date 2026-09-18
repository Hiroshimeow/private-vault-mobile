# Private Vault Mobile RC1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or the smallest matching implementation/test skill for each task. Track each checkbox and preserve unrelated work.

**Goal:** Harden V1 into a truthfully labeled, reproducible GitHub prerelease `v1.0.0-rc.1` with emulator-backed dynamic tests, fail-closed security/release gates, and verified release assets without claiming production signing.

**Architecture:** Keep the current Flutter app architecture. Add release metadata/contracts, a deterministic integration-test seam that does not weaken production security, a hosted Android emulator lane, and a tag-gated release workflow that builds exact-tag artifacts only after quality/security checks pass. Treat physical-device-only behavior as explicit residual evidence, not simulated proof.

**Tech Stack:** Flutter 3.47.4 / Dart, GitHub Actions, Semgrep CE 1.177.0, Android emulator, macOS iOS no-codesign smoke.

## Global Constraints

- Workspace: `E:\git-project\private-vault-mobile` only.
- Accepted baseline: `a4516c66a5fa7156c775d02bc83fef1b11eb0343`; local and `origin/main` verified equal and working tree clean at PLAN intake.
- Android `release` currently uses `signingConfigs.getByName("debug")`; never describe or distribute it as production-signed.
- Do not add signing secrets or keystores to git.
- Do not publish App Store / Google Play.
- Tag contract: `v1.0.0-rc.1`; source version must be machine-checked against the tag.
- Required independent REVIEW after implementation; tag/release only after REVIEW accepts and exact-tag CI is green.
- Physical-device validation is NOT EXECUTED unless fresh device evidence is produced.
- Preserve crypto/security behavior; testability must come from dependency injection/test harnesses, not weakened controls.

---

### Task 1: Release metadata and version contract

**Files:**
- Create: `CHANGELOG.md`
- Create: `docs/release/RELEASE_PROCESS.md`
- Modify: `pubspec.yaml`
- Create: `tool/check_release_version.dart`
- Create: `test/unit/release_version_contract_test.dart`

**Interfaces:**
- Consumes: git tag via CLI argument or `GITHUB_REF_NAME`, plus `pubspec.yaml`.
- Produces: fail-closed version validator used by release workflow.

- [ ] Set `pubspec.yaml` to `1.0.0-rc.1+1`.
- [ ] Add tests that accept tag `v1.0.0-rc.1` only when pubspec semantic version before `+build` is `1.0.0-rc.1`, and reject mismatches.
- [ ] Implement validator with Dart core I/O/string parsing; no extra dependency.
- [ ] Document tag/version/build semantics, debug-signing limitation, prerelease-only policy, rollback/rebuild rules, exact-tag reproducibility.
- [ ] Add RC1 changelog entry with explicit device-validation gaps.
- [ ] Run targeted test, format, analyze, `git diff --check`.

### Task 2: Security configuration hardening audit + regression contracts

**Files:**
- Modify as evidence requires: `android/app/src/main/AndroidManifest.xml`
- Create as evidence requires: `android/app/src/main/res/xml/backup_rules.xml`
- Create as evidence requires: `android/app/src/main/res/xml/data_extraction_rules.xml`
- Modify as evidence requires: iOS plist/native configuration.
- Modify: `test/unit/platform_privacy_contract_test.dart`
- Add focused unit tests for any concrete defect.

- [ ] Audit Android exported components, backup/data-extraction rules, cleartext policy, WebView debugging, FLAG_SECURE/screenshots/recents, temp plaintext handling, iOS Keychain/data-protection.
- [ ] For every concrete defect, write a failing regression test first.
- [ ] Apply the smallest security-preserving fix.
- [ ] Explicitly disable Android backup/data extraction for private vault data unless evidence proves a narrower safe policy.
- [ ] Explicitly disallow cleartext traffic unless a real feature requires it.
- [ ] Verify production WebView debugging is not enabled.
- [ ] Verify temp plaintext import/export handling and document plugin/OS residuals.
- [ ] Re-run dependency vulnerability audit and license inventory; preserve exact commands/results.

### Task 3: Deterministic dynamic integration harness

**Files:**
- Modify: `pubspec.yaml` to add Flutter SDK `integration_test`.
- Create: `integration_test/private_vault_rc_test.dart`
- Create: `lib/app/private_vault_test_harness.dart` only if needed for dependency-injected composition.
- Modify focused production files only when a testability seam is necessary.

- [ ] Use production widgets/controllers with deterministic fake biometric/unlock/platform boundaries.
- [ ] Device integration: launch -> locked/cover state; secret workspace absent.
- [ ] Wrong PIN -> no disclosure.
- [ ] Valid PIN and deterministic biometric test-double unlock.
- [ ] Background/foreground lifecycle relock.
- [ ] Panic conceal -> cover.
- [ ] Production `VaultCrypto` + isolated temp directory encrypted add/read round-trip.
- [ ] Mutate encrypted envelope -> tamper rejection.
- [ ] Browser/profile isolation at deepest deterministic layer available, proving cookie/cache clearing on profile switch/close.
- [ ] Keep real WebView, secure storage, camera, sensors, real biometric, FLAG_SECURE visual behavior, launcher aliases/OEM behavior as residual physical-device checks if emulator cannot prove them.
- [ ] Confirm these tests execute on an actual Android emulator; unit/widget tests do not count as device integration.

### Task 4: Hosted Android emulator CI lane

**Files:**
- Create: `.github/workflows/android-integration.yml` or equivalent dedicated job.
- Add workflow contract test under `test/unit/`.

- [ ] Configure Ubuntu + Java 17 + Flutter 3.47.4.
- [ ] Use a maintained Android emulator action with fixed version reference consistent with repo policy.
- [ ] Boot a stable API image, disable animations, run `integration_test/private_vault_rc_test.dart` on the emulator.
- [ ] Upload logs/test evidence on failure; fail closed.
- [ ] Do not imply emulator PASS proves physical-only controls.

### Task 5: Exact-tag prerelease workflow

**Files:**
- Create: `.github/workflows/release-rc.yml`
- Add release workflow contract tests under `test/unit/`.
- Update release docs.

- [ ] Trigger on RC tag push matching `v*.*.*-rc.*`; exact checkout and record `git rev-parse HEAD`.
- [ ] Resolve Flutter 3.47.4 and locked dependencies.
- [ ] Run format, analyze, full tests, explicit security contract tests, dependency/license audit, Semgrep fail-closed, and hosted emulator integration.
- [ ] Android artifacts must be truthful: never attach the current debug-key-signed release APK as production. Prefer a clearly labeled `DEBUG-TEST-ONLY` installable APK and an unsigned release compile artifact only if reproducible without secrets.
- [ ] Build iOS `--release --no-codesign` smoke on macOS.
- [ ] Generate SHA-256 checksums for every attached asset.
- [ ] Generate deterministic dependency manifest from lock/config inputs; use a maintained pinned SBOM tool only if reproducible. Otherwise explicitly call it a dependency manifest, not SBOM.
- [ ] Generate release evidence containing exact SHA, test totals, signing status, supported platforms, workflow context, physical-device gaps.
- [ ] Create GitHub release with `prerelease: true` only after all prerequisite jobs pass.

### Task 6: Local verification, coherent commits, independent review

- [ ] Run full format/analyze/tests/security scan/workflow contracts/version contract/`git diff --check`.
- [ ] Run Android builds locally where host support permits; do not convert host inability into PASS.
- [ ] Check diff for secrets, keystores, debug-signing mislabeling.
- [ ] Commit coherent changes and push only after gates pass, as explicitly authorized.
- [ ] Route to independent REVIEW with exact SHA and evidence. Do not create tag yet.

### Task 7: Post-REVIEW tag/release and verification

**Prerequisite:** independent REVIEW accepts implementation on an exact SHA.

- [ ] Confirm clean tree and remote SHA equals reviewed SHA.
- [ ] Push tag exactly `v1.0.0-rc.1`.
- [ ] Require exact-tag workflow success; never bypass failed gates.
- [ ] Verify release is marked prerelease.
- [ ] Download every asset, recompute SHA-256, compare against published checksums.
- [ ] Record release URL, tag, SHA, run IDs, asset names/sizes/checksums, test totals, signing limitations, supported platforms, remaining manual-device checklist.
- [ ] If GitHub permissions/Actions block a required gate, stop at safe boundary with concrete evidence.

## Physical-device residual checklist

Keep as **NOT EXECUTED** unless fresh evidence exists:

- Android launcher alias/icon refresh across OEM launchers.
- Android FLAG_SECURE screenshot/recents on physical device.
- Real biometric prompt and secure-storage persistence/invalidation.
- Real WebView cookie/cache/profile isolation across process/lifecycle edges.
- Camera plugin temporary-file lifecycle and import cleanup.
- Shake/face-down sensors and panic timing.
- iOS alternate-icon confirmation UX.
- iOS Keychain/data-protection behavior across lock/backup/restore.
