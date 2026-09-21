# Threat Model

## Assets
Encrypted vault contents, local unlock state, Android work-profile separation and package inventory, browser session data, temporary decrypted previews, and export decisions.

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
- Android V1.2 uses an OS-managed Work Profile and Profile Owner DPC boundary; personal app data/accounts are not copied into work-profile apps.
- Cross-profile control is limited to fixed bridge actions authenticated with a random provisioning-time capability token stored privately in both profile instances. Selected APK base/split files are exposed only through temporary read grants and removed from staging after the operation returns.
- Work-profile clipboard crossing is disabled by DPC policy; no broad `QUERY_ALL_PACKAGES` visibility is requested.

## Out of scope
Root/jailbreak, malicious or compromised OS/DPC framework, privileged forensic tooling, coercion, hardware attacks, attacks while secrets are legitimately displayed, guarantees of anonymous browsing, and bypassing OEM/enterprise/package-verification policy. Locking Private Vault does not stop or conceal a cloned app that is already running outside the Flutter process; freeze is a separate Android policy action.

## Failure policy
Wrong unlock input reveals no secret workspace. Missing local key material or corrupt ciphertext returns no plaintext. Export always requires an explicit user action.

## Deletion limits
Deleting app data removes normal app access, but physical flash blocks may retain historical data because of wear leveling, filesystem behavior, backups, or snapshots. V1 does not claim forensic secure erase.

## Work-profile limits
Work-profile isolation relies on Android framework enforcement, the device OEM, PackageInstaller, and the integrity of the Private Vault DPC. Ordinary APK-copy installation may require the user to trust the install source and confirm the package; an OEM may refuse the flow. In that case the product reports the limitation and uses Play/OEM-store installation or Browser fallback rather than claiming a silent clone. Removing the managed profile deletes its apps, accounts, and data; it does not uninstall corresponding personal-profile apps. No Shelter/Insular source is vendored.

## Browser limits
Embedded browsing is not anonymity. Network infrastructure, destination services, device configuration, and the platform WebView engine may still observe traffic. Some services reject embedded WebViews. V1 logical profiles are sequential and ephemeral because the cross-platform WebView layer does not expose simultaneous independent retained cookie jars. Direct HTTPS download-to-vault uses a separate client and therefore does not inherit authenticated WebView cookies.

## Recovery and rotation
There is no server-side recovery. Loss of protected local key material can make encrypted content unrecoverable. Any future key rotation must preserve the previous valid state until replacement data is verified.
