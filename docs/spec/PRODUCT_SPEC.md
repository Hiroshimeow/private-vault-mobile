# Private Vault Mobile — Product Specification

## Purpose
Private Vault Mobile is a local-first privacy utility for Android and iOS. It provides benign cover tools while keeping a separate encrypted workspace locked by default. It is inspired only by public behavior descriptions of privacy-vault products; no third-party code, branding, text, assets, or store metadata are reused.

## V1/V1.1 foundation
- Two functional covers: Calculator and Notes/Todo.
- Locked launch exposes only the selected cover.
- PIN unlock with optional biometric convenience after a valid key has been provisioned.
- Local encrypted vault for notes, images, videos, and documents.
- Import/capture into app-owned storage; no public-gallery write unless explicitly exported.
- Embedded private browser with sequential ephemeral logical profiles, optional clear-on-close, and direct HTTPS download-to-vault.
- Profile switching clears the shared WebView cookie/cache/local-storage surface. V1 does not claim simultaneously retained independent WebView cookie jars where the platform/plugin does not expose them.
- Panic conceal using shake and face-down signals with sensitivity/debounce controls.
- Platform-accurate disguise controls.
- Privacy hardening for lifecycle, screenshots/app-switcher previews, no secret-copy action in V1, and no direct production logging of secret values.
- No analytics, ads, remote backend, or cloud sync by default.

## V1.2 Android isolated apps
- Android native app isolation uses the official `android.os.usertype.profile.CLONE` user type when the OEM exposes it.
- Private Vault performs only allowlisted clone/profile operations through an authorized Shizuku UserService. It does not provision, reuse, or fall back to a managed Work Profile.
- Private Vault creates a clone profile only under the current Android user and persists ownership only after post-create discovery proves the created clone id unambiguously.
- Any existing clone profile that is not proven to be the Private Vault-created id fails closed as `conflicting_external_clone_profile`; Private Vault never adopts, removes, or modifies it.
- Package inventory, install-existing, launch, and uninstall are explicitly scoped to the proven clone user id.
- Cloned packages start with separate private app data for that Android user. The product does not claim complete storage isolation because shared-storage behavior can vary by Android/OEM clone-profile implementation.
- Shizuku unavailable/not authorized is `privilege_required`; explicit CLONE-type absence/unsupported evidence is `clone_profile_unsupported_by_oem`; ambiguous policy/capacity/create errors are `operation_failed`.
- Locking Private Vault hides this app's UI but does not claim to stop an already-running cloned app.
- Browser/WebView remains a separate user-selected surface, not a managed-profile fallback.
- The Android implementation is independent; Shelter/Insular GPL source is not vendored or copied.

## Non-goals and platform limits
- iOS does not expose Android-style clone-profile app isolation; Private Vault does not emulate or claim parity there.
- V1.2 does not bypass service restrictions, DRM, anti-abuse systems, enterprise policy, Android package verification, or OEM policy.
- Embedded WebViews do not provide anonymity and can be blocked by services.
- Android can expose only predeclared launcher aliases/icons/names.
- iOS supports only predeclared alternate icons; runtime display-name changes are not supported.
- Flash storage does not guarantee physical secure deletion after file deletion because of wear leveling and filesystem behavior.
- V1 does not claim resistance to forensic extraction, root/jailbreak, malicious OS, compromised device, or compelled disclosure.

## Security requirements
- No custom cryptography.
- One random vault master key is stored only through platform secure storage.
- Vault items use authenticated encryption with unique nonces and integrity tags.
- PIN verification uses a vetted deliberately slow KDF wrapper and never stores plaintext PIN.
- Wrong PIN, missing key, or corrupt ciphertext fails closed.
- Plaintext secret payloads are never persisted outside transient memory.
- Secret values are redacted from logs and exception text.
- Key rotation requires authentication. There is no silent password recovery path that weakens encryption.

## Core user flows
1. Launch -> selected cover.
2. Unlock affordance -> PIN -> optional biometric -> secret workspace.
3. Create note/import/capture -> encrypt -> persist ciphertext plus minimal metadata.
4. Open vault item -> decrypt in memory -> view.
5. Export -> explicit item action -> confirmation by default -> platform save. Confirmation may be explicitly disabled in Settings.
6. Panic/background/timeout -> lock -> cover.
7. Android Apps -> clone capability check -> authorize Shizuku when required -> create and re-discover a real `profile.CLONE` if no owned clone exists -> choose a personal app -> install-existing into the proven clone user.
8. Installed clone app -> start clone user -> resolve/launch or remove the package in that clone user only.
9. Existing unowned/ambiguous clone profile -> fail closed; do not adopt, alter, or remove it.
10. Browser logical profile -> clear shared WebView state on profile switch -> browse -> direct HTTPS responses can be saved into the vault. Authenticated WebView-cookie downloads are outside V1.

## Settings
Cover selection, panic enablement, shake sensitivity, face-down delay, auto-lock duration, biometrics, browser clear-on-close, export confirmation, theme.

## Accessibility
Semantic labels, minimum touch targets, keyboard-safe forms, scalable text, light/dark themes, and no color-only critical state indicators.

## Acceptance
Security-critical behavior is test-first. CI must format, analyze, test, compile the Android native layer, build Android, and build iOS without codesign. README and threat model must describe limitations exactly. Clone-profile E2E claims require a legal emulator or physical-device target that actually exposes `android.os.usertype.profile.CLONE` and Shizuku authorization; build/unit success alone is not labeled cloning E2E proof.
