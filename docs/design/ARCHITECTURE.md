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
Android: secure-window protection for secret surfaces and predeclared launcher aliases.
iOS: privacy overlay during inactive/background transitions and predeclared alternate icons only.

## Browser isolation
Each logical profile receives app-owned browser storage where the selected engine supports it. The product does not describe this as anonymity or cross-app isolation.

## Persistence
Encrypted content stays in app-private storage. Non-secret settings stay local. There is no remote backend in V1.
