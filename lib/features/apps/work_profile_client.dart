import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

/// Legacy compatibility seam for tests and split-lane review only.
///
/// Production navigation uses [CloneProfileClient]; there is intentionally no
/// managed Work Profile implementation behind this interface.
abstract interface class WorkProfileClient {
  Future<WorkProfileCapability> getCapability();
  Future<List<ManagedAppState>> listApps();
  Future<WorkProfileOperationResult> startProvisioning();
  Future<WorkProfileOperationResult> requestQuietModeDisabled();
  Future<PickedWorkDocument?> pickWorkDocument();
  Future<WorkProfileOperationResult> openStore(String packageName);
  Future<WorkProfileOperationResult> clone(String packageName);
  Future<WorkProfileOperationResult> launch(String packageName);
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  );
  Future<WorkProfileOperationResult> setHidden(String packageName, bool hidden);
  Future<WorkProfileOperationResult> uninstall(String packageName);
  Future<WorkProfileOperationResult> destroyProfile();
}
