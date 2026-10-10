# Android packaging checkpoint — 2026-10-10

Goal: add APK source/configuration in E:\\git-project\\private-vault-mobile, compile exclusively on GitHub Actions, publish an explicitly authorized GitHub test prerelease.

Source: g6, main, intake SHA 46c5a4f48e1eba53bed6aaa58ce8ff5b869f18c5.
Preserved: React features; untracked AGENTS.md, docs/agent-program/, legacy android/.gradle/, android/app/ and ios/ files.
Complete: pinned Capacitor shell at android-capacitor/, lockfile, local HTTPS bundle, Android privacy flags, CI build and emulator instrumentation, fail-closed release signing and test prerelease publication with source/checksum evidence.
Fix: invalid job-level hashFiles CI expression and obsolete Flutter-only build/release jobs.
Non-goals: restore Flutter, native cloning, real ReVanced, production signing, iOS, physical-device acceptance.

Acceptance:
1. GitHub npm ci/lint/test/build and production audit pass.
2. GitHub Semgrep passes.
3. GitHub debug APK/test APK compile; unsigned production release fails with the expected signing guard.
4. Hosted Android emulator validates cover, secure local origin, crypto, encrypted synthetic storage and Android privacy flags.
5. Release appears only after all required gates pass, with APK, source/run identity and checksums.

Local compilation: NOT RUN, per owner instruction. Local dependency installation/scaffold and source inspection only.
Final GitHub run/release identity is recorded in the conversation and attached BUILD_INFO.txt.

Security correction found during packaging: LockController started unlocked and backgroundLock was disabled. Cold start now locks; native app inactivity immediately relocks and dismisses the PIN dialog. Regression checks run on GitHub.

Pre-release validation: source 51b94f88e40e383c529821bab2183daef5d025e6, GitHub run https://github.com/Hiroshimeow/private-vault-mobile/actions/runs/38057456962, all four jobs PASS (web, SAST, Android APK/signing guard, hosted emulator). Five Node regression/packaging checks and two Android instrumentation tests passed. Production/device security remains incomplete; persistent web master-key storage is documented in release notes.
