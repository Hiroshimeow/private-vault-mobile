# Security Policy

Private Vault Mobile is designed for casual-inspection privacy, not high-assurance forensic resistance.

## Reporting
Use synthetic reproduction data only. Do not include real vault contents, unlock codes, browser cookies, personal media, or other private material in reports.

## Security properties
- Authenticated encryption for vault payloads.
- Local key material protected through platform secure storage.
- Locked-by-default secret workspace.
- No analytics, ads, or remote backend by default.
- No intentional plaintext persistence of vault payloads.

## Explicit limits
The app does not claim protection against root/jailbreak, a malicious OS, privileged forensic tooling, coercion, or compromise while secrets are legitimately displayed. App-level deletion is not guaranteed physical secure erase on flash storage.
