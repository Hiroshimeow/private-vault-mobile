# Private Vault Mobile — Product Specification

## Purpose
Private Vault Mobile is a local-first privacy utility for Android and iOS. It provides benign cover tools while keeping a separate encrypted workspace locked by default. It is inspired only by public behavior descriptions of privacy-vault products; no third-party code, branding, text, assets, or store metadata are reused.

## V1 goals
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

## Non-goals and platform limits
- V1 does not clone arbitrary native apps or bypass service restrictions.
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
7. Browser logical profile -> clear shared WebView state on profile switch -> browse -> direct HTTPS responses can be saved into the vault. Authenticated WebView-cookie downloads are outside V1.

## Settings
Cover selection, panic enablement, shake sensitivity, face-down delay, auto-lock duration, biometrics, browser clear-on-close, export confirmation, theme.

## Accessibility
Semantic labels, minimum touch targets, keyboard-safe forms, scalable text, light/dark themes, and no color-only critical state indicators.

## Acceptance
Security-critical behavior is test-first. CI must format, analyze, test, build Android, and build iOS without codesign. README and threat model must describe limitations exactly.
