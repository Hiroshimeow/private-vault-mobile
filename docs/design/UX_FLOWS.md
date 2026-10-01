# UX Flows

## Locked launch
Launch -> selected cover -> functional Calculator or Notes/Todo. No vault labels, counts, thumbnails, or secret navigation are rendered while locked.

## Unlock
User invokes the local unlock affordance -> local verification -> secret workspace. Failed verification returns a generic error without revealing vault contents or counts.

## Vault
Secret home -> create note/import/capture -> encrypt -> item list. Protected notes are encoded and encrypted like other payloads. Opening an item decrypts only for the active view. Background, timeout, or panic clears transient secret state according to policy.

## Export
Item -> Export -> explicit confirmation by default -> platform save. The warning states that exported files leave protected app storage and may become visible to other apps. A user may explicitly disable the confirmation in Settings; export itself is always an explicit item action.

## Android isolated apps
Secret home -> Apps -> clone capability check. If Shizuku is unavailable or not authorized, the screen shows `Authorize Shizuku`. Authorization is requested once per action and successful authorization refreshes capability state.

Ready state with no owned clone -> choose a personal app -> Private Vault creates `android.os.usertype.profile.CLONE` for the current Android parent user -> re-queries Android users -> persists ownership only if the created id is the single unambiguous CLONE id -> starts that user -> installs the selected package with `--user <cloneId>`.

Ready state with an owned clone -> personal app inventory shows whether each package already exists in the proven clone user. Uncloned apps expose `Clone`; cloned apps expose Open and Remove clone instance. Start/install/resolve/launch/uninstall failures are surfaced as operation failures and never silently fall back to a managed Work Profile.

An existing unowned or ambiguous CLONE profile shows `Existing clone profile detected`. Private Vault does not adopt, modify, remove, or reuse that profile. An explicit OEM rejection/absence of the CLONE user type shows `Clone profiles unsupported`; policy/capacity/ambiguous create failures remain backend failures.

Locking Private Vault does not stop an already-running cloned app outside it. On iOS or unsupported environments, the Apps surface exposes no fake clone operation.

## Browser
Secret home -> Browser -> choose/create ephemeral logical profile -> browse. Browser is a separate user-selected surface, not an automatic fallback from Clone/Shizuku failure. Switching profiles first clears the shared WebView cookies/cache/local storage, then resets the page. A direct HTTPS response can be downloaded into the encrypted vault; authenticated WebView-cookie downloads are not supported in V1. Clear-on-close removes supported browser data. These profiles are sequential, not simultaneously retained identities.

## Panic
Configured shake or sustained face-down signal -> debounce -> immediate lock -> cover. Cooldown suppresses repeated triggers.

## Disguise
Android shows only installed predeclared launcher aliases. iOS shows only predeclared alternate icons. Unsupported runtime app-name changes are not presented as available.

## Background
When secret UI becomes inactive, a privacy cover appears immediately. Lock follows the configured lifecycle policy; panic always locks immediately.
