# Threat Model

## Assets
Encrypted vault contents, local unlock state, Android clone-profile ownership/package separation, browser session data, temporary decrypted previews, and export decisions.

## Intended adversary
A casual or opportunistic person who temporarily accesses the device or sees previews, gallery contents, clipboard contents, logs, or an unlocked UI left in the background.

## Defenses
- Locked-by-default cover workspace.
- Immediate lock on panic and configured lifecycle events.
- Authenticated encryption at rest.
- Operating-system protected storage for the vault key.
- No public-gallery writes except explicit export.
- Android `FLAG_SECURE` on the app activity.
- iOS privacy cover during app-switcher transitions.
- V1 exposes no secret-copy action and never intentionally writes vault plaintext to the clipboard; production Dart source also forbids direct print/debug logging.
- Browser profile switching clears the shared WebView cookie/cache/local-storage surface before changing logical profiles.
- Android V1.2 uses the OS `android.os.usertype.profile.CLONE` boundary where the OEM exposes it. Package operations are explicitly scoped to the proven clone user id; personal-user package state is not modified.
- Privileged clone control is limited to fixed Shizuku UserService operations. No arbitrary shell command is accepted.
- Clone ownership is persisted only after post-create discovery proves the created id; unowned or ambiguous CLONE profiles fail closed and are never adopted or removed.
- No broad `QUERY_ALL_PACKAGES` visibility is requested.

## Out of scope
Root/jailbreak, malicious or compromised Android/Shizuku/OEM framework, privileged forensic tooling, coercion, hardware attacks, attacks while secrets are legitimately displayed, guarantees of anonymous browsing, and bypassing OEM/enterprise/package-verification policy. Locking Private Vault does not stop or conceal a cloned app that is already running outside the Flutter process.

## Failure policy
Wrong unlock input reveals no secret workspace. Missing local key material or corrupt ciphertext returns no plaintext. Export always requires an explicit user action.

## Deletion limits
Deleting app data removes normal app access, but physical flash blocks may retain historical data because of wear leveling, filesystem behavior, backups, or snapshots. V1 does not claim forensic secure erase.

## Clone-profile limits
Clone-profile isolation relies on Android framework enforcement, the OEM implementation of `profile.CLONE`, and the integrity/authorization of Shizuku. Clone profiles provide a distinct Android user for private app data, but shared-storage behavior can vary by OEM, so Private Vault does not claim complete storage isolation. An OEM may omit or reject the CLONE user type; policy/capacity failures can also prevent creation. These conditions are reported rather than silently substituting a managed Work Profile. No Shelter/Insular source is vendored.

## Browser limits
Embedded browsing is not anonymity. Network infrastructure, destination services, device configuration, and the platform WebView engine may still observe traffic. Some services reject embedded WebViews. V1 logical profiles are sequential and ephemeral because the cross-platform WebView layer does not expose simultaneous independent retained cookie jars. Direct HTTPS download-to-vault uses a separate client and therefore does not inherit authenticated WebView cookies.

## Recovery and rotation
There is no server-side recovery. Loss of protected local key material can make encrypted content unrecoverable. Any future key rotation must preserve the previous valid state until replacement data is verified.
