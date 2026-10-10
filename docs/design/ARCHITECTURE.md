# Architecture

Flutter owns application logic and UI. Native platform integrations stay behind narrow interfaces.

## Boundaries
- app shell/navigation: boot, route gating, lifecycle
- cover workspace: Calculator and Notes/Todo
- authentication/lock state: lock state machine and local unlock verification
- crypto/key management: protected local key access and authenticated encryption
- vault repository/storage: encrypted files and minimal metadata
- media: import, camera capture, preview, explicit export
- browser: embedded browser abstraction, profile identity, download-to-vault
- panic: sensor normalization, thresholds, debounce
- privacy/disguise bridge: screenshot/app-switcher protection and supported launcher/icon features
- settings: local non-secret preferences

## Dependency direction
UI -> feature services/interfaces -> core storage/security/platform abstractions. Platform plugins are wrapped so unit tests can use deterministic substitutes.

## Data model
Vault items use opaque identifiers and encrypted payloads with minimal metadata. Source paths and original filenames are not required to persist.

## Encryption boundary
Use a vetted authenticated-encryption package. Every item encryption operation uses a fresh nonce. Integrity failure returns no plaintext. The vault key is kept through the operating system secure-storage facility.

## Lifecycle
The app starts locked. Backgrounding, panic, or timeout clears transient secret state and routes back to the configured cover. Secret routes verify lock state before rendering.

## Native bridges
Android: `FLAG_SECURE` currently protects the whole Flutter activity, and launcher disguise switches only between predeclared Calculator/Notes aliases. iOS: a privacy overlay covers inactive/app-switcher snapshots; runtime disguise can switch only to predeclared alternate icons, never the display name.

## Browser isolation
The cross-platform WebView API exposes one app-level cookie/storage surface on supported platforms. V1 therefore implements **sequential ephemeral profiles**: switching profiles clears WebView cookies, cache, and local storage before opening the selected logical profile. It does not promise simultaneously retained independent cookie jars, native-app cloning, anonymity, or cross-app isolation. Direct HTTPS downloads can be encrypted to the vault, but V1 does not transfer authenticated WebView cookies into its separate download client.

## Persistence
Encrypted content stays in app-private storage. Non-secret settings stay local. Imported source files remain at their user-selected source location; camera capture is read into the vault and plugin-owned temporary capture data is deleted on a best-effort basis. Explicit export creates an unprotected copy outside the vault. There is no remote backend in V1.
