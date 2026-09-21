# Architecture

Flutter owns application logic and UI. Native platform integrations stay behind narrow interfaces.

## Boundaries
- app shell/navigation: boot, route gating, lifecycle
- cover workspace: Calculator and Notes/Todo
- authentication/lock state: lock state machine and local unlock verification
- crypto/key management: protected local key access and authenticated encryption
- vault repository/storage: encrypted files and minimal metadata
- media: import, camera capture, preview, explicit export
- apps/work profile: Android managed-profile capability, DPC provisioning, cross-profile command bridge, APK transfer/install, and work-app policy controls
- browser: embedded browser abstraction, profile identity, download-to-vault fallback
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
Android: `FLAG_SECURE` protects the Flutter activity, launcher disguise switches only between predeclared Calculator/Notes aliases, and a generated Pigeon host API exposes typed work-profile operations. Managed-profile provisioning installs the same signed app as Profile Owner. Its `DeviceAdminReceiver` enables a dedicated bridge activity in the work profile and installs narrowly scoped parent-to-managed cross-profile intent filters. The personal-profile instance stages only the selected app's base/split APK files in app cache and grants temporary read-only content URIs; the work-profile bridge streams them into one `PackageInstaller` session. Package inventory and DPC controls execute inside their owning profile rather than pretending one process can query both profiles. Transient APK files are deleted and URI grants revoked after the operation returns.

The bridge activity is disabled in the personal profile and enabled only by successful Profile Owner provisioning. Provisioning carries a random 256-bit capability token through Android's admin-extras bundle; both profile instances store it in their private app storage, and every bridge command is verified in constant time before execution. This avoids relying on system IntentForwarder permission identity while still rejecting other work-profile callers. The bridge accepts only fixed Private Vault operation actions. The manifest exposes launcher-query visibility rather than `QUERY_ALL_PACKAGES`.

iOS: a privacy overlay covers inactive/app-switcher snapshots; runtime disguise can switch only to predeclared alternate icons, never the display name. There is no iOS work-profile bridge or native clone emulation.

## Browser isolation
The cross-platform WebView API exposes one app-level cookie/storage surface on supported platforms. Browser mode therefore implements **sequential ephemeral profiles**: switching profiles clears WebView cookies, cache, and local storage before opening the selected logical profile. It does not promise simultaneously retained independent cookie jars, anonymity, or native cross-app isolation. On Android V1.2, managed Work Profile apps are the primary native-isolation path and Browser is a fallback. Direct HTTPS downloads can be encrypted to the vault, but browser mode does not transfer authenticated WebView cookies into its separate download client.

## Persistence
Encrypted content stays in app-private storage. Non-secret settings stay local. Imported source files remain at their user-selected source location; camera capture is read into the vault and plugin-owned temporary capture data is deleted on a best-effort basis. Explicit export creates an unprotected copy outside the vault. There is no remote backend in V1.
