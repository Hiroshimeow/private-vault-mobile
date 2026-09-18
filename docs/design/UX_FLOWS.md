# UX Flows

## Locked launch
Launch -> selected cover -> functional Calculator or Notes/Todo. No vault labels, counts, thumbnails, or secret navigation are rendered while locked.

## Unlock
User invokes the local unlock affordance -> local verification -> secret workspace. Failed verification returns a generic error without revealing vault contents or counts.

## Vault
Secret home -> add/import/capture -> encrypt -> item list. Opening an item decrypts only for the active view. Background, timeout, or panic clears transient secret state according to policy.

## Export
Item -> Export -> explicit confirmation -> platform share/save. The confirmation states that exported files leave protected app storage and may become visible to other apps.

## Browser
Secret home -> Browser -> choose/create profile -> browse. Download -> Save to Vault stores through the encrypted-vault boundary. Clear-on-close removes browser data supported by the engine.

## Panic
Configured shake or sustained face-down signal -> debounce -> immediate lock -> cover. Cooldown suppresses repeated triggers.

## Disguise
Android shows only installed predeclared launcher aliases. iOS shows only predeclared alternate icons. Unsupported runtime app-name changes are not presented as available.

## Background
When secret UI becomes inactive, a privacy cover appears immediately. Lock follows the configured lifecycle policy; panic always locks immediately.
