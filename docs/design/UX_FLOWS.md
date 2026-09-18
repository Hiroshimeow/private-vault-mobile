# UX Flows

## Locked launch
Launch -> selected cover -> functional Calculator or Notes/Todo. No vault labels, counts, thumbnails, or secret navigation are rendered while locked.

## Unlock
User invokes the local unlock affordance -> local verification -> secret workspace. Failed verification returns a generic error without revealing vault contents or counts.

## Vault
Secret home -> create note/import/capture -> encrypt -> item list. Protected notes are encoded and encrypted like other payloads. Opening an item decrypts only for the active view. Background, timeout, or panic clears transient secret state according to policy.

## Export
Item -> Export -> explicit confirmation by default -> platform save. The warning states that exported files leave protected app storage and may become visible to other apps. A user may explicitly disable the confirmation in Settings; export itself is always an explicit item action.

## Browser
Secret home -> Browser -> choose/create ephemeral logical profile -> browse. Switching profiles first clears the shared WebView cookies/cache/local storage, then resets the page. A direct HTTPS response can be downloaded into the encrypted vault; authenticated WebView-cookie downloads are not supported in V1. Clear-on-close removes supported browser data. These profiles are sequential, not simultaneously retained identities.

## Panic
Configured shake or sustained face-down signal -> debounce -> immediate lock -> cover. Cooldown suppresses repeated triggers.

## Disguise
Android shows only installed predeclared launcher aliases. iOS shows only predeclared alternate icons. Unsupported runtime app-name changes are not presented as available.

## Background
When secret UI becomes inactive, a privacy cover appears immediately. Lock follows the configured lifecycle policy; panic always locks immediately.
