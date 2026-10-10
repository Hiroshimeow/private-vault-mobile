# Release process for the current React application

The repository switched from Flutter to React/Vite before commit 46c5a4f. Historical Flutter RC instructions and agent-program design drafts are not evidence that their files or native features still exist.

## GitHub-only build

CI runs npm ci using package-lock.json, TypeScript checks, packaging contract tests, a production dependency audit, pinned Semgrep, Vite production build, Capacitor Android sync and Gradle debug compilation. Hosted Android instrumentation tests must pass. No local compilation is required.

## Authorized test release

An explicitly authorized android-web-vVERSION-test.N tag invokes .github/workflows/release-rc.yml. That workflow calls the same CI gates and publishes a GitHub prerelease only after all gates pass. Existing releases/tags are never overwritten.

The prerelease contains a DEBUG-TEST-ONLY APK, exact source/run identity, lockfile, SAST report, emulator report, limitations and SHA-256 checksums. This is not Play/App Store publication.

## Signing and updates

Debug builds use a runner-generated Android debug key; signatures may differ across independent runs. Do not uninstall an app containing real vault data merely to install a differently signed test build.

Production release tasks fail closed without all four VAULT_RELEASE_* signing environment inputs. Keys/passwords are never committed or attached to a release. Provisioning a stable production signing key and validating actual devices are separate tasks.

The active Android project is android-capacitor/. The former android/ and ios/ residual local files are not used or deleted by this pipeline.
