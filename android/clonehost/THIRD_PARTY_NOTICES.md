# Clone-host provenance

This experiment was designed after inspecting public userspace Android virtualization projects, but the source in `android/clonehost` is an independent narrow implementation. No third-party source file is copied or vendored here.

## NEXTVM — architectural reference only

- Repository: `TanvirHossain2/NEXTVM`
- Inspected commit: `f581a6642596db396a6fe606addd735979403b6b`
- License verified at that commit: Apache License 2.0 (`LICENSE` at repository root).
- Files inspected for architectural context include:
  - `core/virtualization/src/main/java/com/nextvm/core/virtualization/engine/ActivityThreadHook.kt`
  - `core/virtualization/src/main/java/com/nextvm/core/virtualization/engine/StubRegistry.kt`
  - `core/virtualization/src/main/java/com/nextvm/core/virtualization/engine/VirtualClassLoaderInjector.kt`
- Copy/adaptation status: **none**. The experiment deliberately does not import NEXTVM's broad hook, GMS, identity, anti-detection, or native-hook subsystems.

## Renjana — reference only

- Repository: `josskixg/renjana`
- Inspected commit: `14302a57cd66114c6979acf7ca56c97f845a6841`
- Repository license: Apache License 2.0.
- Pine-dependent runtime code is excluded because Pine uses the Anti-996 License 1.0 and is outside this experiment's allowed dependency set.
- Copy/adaptation status: **none**.

## NewBlackbox / VirtualApp lineage — reference only

- Local NewBlackbox reference inspected by PLAN: `89b59836c66f173756a4ae258cf379a957649820`.
- Copy/adaptation status: **none** because file-level provenance/current VirtualApp authorization terms were not cleared.

The clone-host implementation uses only Android SDK/Java APIs plus code written specifically for this experiment. If a future change copies or adapts a third-party file, that file must be reviewed and attributed here before it enters the module.
