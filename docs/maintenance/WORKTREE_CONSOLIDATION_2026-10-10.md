# Git worktree consolidation — 2026-10-10

Canonical working tree: E:\git-project\private-vault-mobile (branch main).
Previous main: 4be30c5; fully integrated v1.2 baseline: 50857b5.

## Consolidation decisions

- Fast-forwarded main to integration/v12-parallel-acceptance, preserving all 52
  commits and ancestry. Existing v1.2 gallery, storage, security lifecycle, UI
  security, Shizuku and Work Profile cleanup branch commits were already contained.
- Backported compatible RC CI behavior from build/v12-acceptance-20260923
  (machine-output preamble tolerance, emulator pipefail, golden-tag handling
  and dynamic RC version contracts). Did not cherry-pick the obsolete RC build
  and its legacy managed Work Profile runtime into the v1.2 integration.
- Preserved root test.md build/testing guide as a tracked document instead of
  silently deleting the previously untracked user file.
- Archive-preserved uncommitted worktree source in the original Git branch refs:
  * feature/v12-clone-shizuku: checkpoint 3566e9e
  * experiment/clone-plugin-transform-20260928: dde32f1
  * experiment/clone-repackage-20260928: 7d2d0c0
  * experiment/clone-virtual-20260928: 1ab7a8f
- Those three clone experiment implementations are mutually exclusive
  architectures. They are preserved for reuse/evaluation, but intentionally
  not force-merged into the production main branch. The archive branches are
  not production releases.
- Kept the other release/feature branch refs and associated history in this
  SAME Git repository. Removing a worktree does not delete its branch.

## Data preservation

Local-only, out-of-Git backup:
E:\git-project\.private-vault-consolidation-20261010

- BACKUP_MANIFEST.json: all 15 original worktrees, verified SHA256 copies of
  284 non-ignored modified/untracked files and original Git binary patches.
- IGNORED_CONFIG_BACKUP.json: 11 local toolchain/config files copied and hashed.
- APK_ARCHIVE_MANIFEST.json: 10 pre-existing debug APKs, around 1.89 GB,
  moved and SHA256-verified; not added to Git or remote.
- Generated Flutter/Gradle/Kotlin caches are rebuildable and were deleted
  separately from source/archives. Review logs/patches were locally backed up
  rather than published to GitHub.
- The main working tree now owns an intact Flutter Git SDK checkout and Android
  SDK / JDK17 under .tooling. These locally ignored dependencies are NOT part
  of Git history.

## Safety and verification

- Before removal: confirmed the branch tip and clean tracked state, every
  remaining untracked file's hash in the external backup, and ignored local
  config backups. No blanket git clean of unknown files.
- Used Git metadata pruning only after relocating already-archived worktree
  folders away from their original paths; none of the feature/experiment branch
  refs were deleted.
- The canonical Git state is expected to list exactly one active worktree:
  git worktree list
- The archive refs are available for future focused review; do not automatically
  merge competing clone implementations. Use a regular branch or a temporary
  worktree only after choosing the intended clone architecture.
- Local verification evidence is retained outside Git in
  MAIN_VERIFICATION.json and verify-*.log. A failed or skipped check must be
  reported and not silently counted as passed.

## Recovery

The original branch heads, SHA-verified snapshots, local-only build artifacts,
and patch files can be recovered from the backup above. Do not upload
android/local.properties, signing credentials, logs or generated APKs to GitHub
by default.

No Git force-push, history rewrite, secret rotation, production deploy, or
release-version bump was performed during consolidation.
