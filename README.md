# Private Vault (React Web SPA)

A local-first privacy utility rewritten in React, TypeScript, and Tailwind CSS with Vite. Inspired by public behavior descriptions of privacy-vault products, it provides benign cover tools while keeping a separate authenticated encrypted workspace locked by default.

## Features

- **Functional Covers**:
  - **Calculator Cover**: Fully functional calculator with arithmetic operations, error states, and hold-to-unlock title interaction.
  - **Notes / Todo Cover**: Interactive daily checklist with task completion, deletion, count summary, and hold-to-unlock title interaction.
- **PIN Unlock & Biometrics**:
  - PIN setup and verification using PBKDF2 with SHA-256 (100,000 iterations) and cryptographically secure random salt.
  - Optional biometric unlock via WebAuthn platform authenticators.
- **AES-256-GCM Encrypted Vault**:
  - Authenticated encryption using Web Crypto API (`AES-GCM-256`) with unique 12-byte nonces and integrity verification.
  - Encrypted storage for notes, photos, media, and documents backed by IndexedDB.
  - Camera capture and file import capabilities.
  - In-memory ephemeral viewing, deletion confirmation, and explicit export to local device.
- **Private Browser**:
  - Sequential ephemeral profiles (clears shared session cookies, cache, and storage upon switching).
  - Direct HTTPS navigation and sandboxed web viewing.
  - Direct HTTPS download-to-vault preserving encryption at rest.
- **Panic Conceal & Auto-lock**:
  - Shake conceal (`devicemotion`) and face-down conceal (`deviceorientation`) with sensitivity and delay sliders.
  - Instant panic triggers (Escape key shortcut and in-app quick test button).
  - Background auto-lock on window blur / tab invisibility (`visibilitychange`).
- **Customizable Settings**:
  - Default cover selection (Calculator vs. Notes).
  - Sensitivity and debounce thresholds.
  - Dark mode and light mode theme toggles.
  - Export confirmation guardrail.

## Tech Stack

- **Framework**: React 19, TypeScript
- **Bundler**: Vite 6
- **Styling**: Tailwind CSS v4
- **Cryptography**: Web Crypto API (SubtleCrypto `AES-GCM`, `PBKDF2`)
- **Icons**: Lucide React

## Getting Started

```bash
# Install dependencies
npm install

# Run development server (runs on port 3000)
npm run dev

# Build for production
npm run build
```

## Android APK built on GitHub

The current React app is packaged using Capacitor in android-capacitor/. GitHub Actions compiles the web bundle and APK; local compilation is not required. CI installs dependencies from package-lock.json and checks TypeScript, packaging/auth regressions, production dependency audit, source security, Android compilation, production signing rejection and hosted emulator instrumentation.

Download the explicitly labeled DEBUG-TEST-ONLY APK from a GitHub prerelease. See [Android test release and limitations](docs/release/ANDROID_TEST_RELEASE.md) and [release process](docs/release/RELEASE_PROCESS.md). This web shell does not run real cloned Android apps or ReVanced, and does not restore the previous Flutter native feature set.

Authorized maintainers publish a test prerelease by pushing a new immutable android-web-vVERSION-test.N tag. Production signing has no debug-key fallback. Existing Flutter residue at android/ and ios/ is not used by the web packaging pipeline.
