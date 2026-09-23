import 'package:flutter/services.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';
import 'package:private_vault_mobile/platform/generated/work_profile_api.g.dart'
    as native;

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

class PigeonWorkProfileClient implements WorkProfileClient {
  PigeonWorkProfileClient({native.WorkProfileHostApi? api})
    : _api = api ?? native.WorkProfileHostApi();

  final native.WorkProfileHostApi _api;

  @override
  Future<WorkProfileCapability> getCapability() async {
    final value = await _api.getCapability();
    return WorkProfileCapability(
      supported: value.supported,
      provisioningAllowed: value.provisioningAllowed,
      profileState: _profileState(value.profileState),
    );
  }

  @override
  Future<List<ManagedAppState>> listApps() async {
    final personal = await _api.listPersonalApps();
    final work = await _api.listWorkApps();
    final byPackage = <String, ManagedAppState>{};

    for (final value in personal) {
      byPackage[value.packageName] = _appState(value);
    }
    for (final value in work) {
      final current = byPackage[value.packageName];
      final mapped = _appState(value);
      byPackage[value.packageName] = current == null
          ? mapped
          : ManagedAppState(
              packageName: current.packageName,
              label: current.label,
              presentPersonal: current.presentPersonal,
              presentWork: mapped.presentWork,
              launchableWork: mapped.launchableWork,
              systemApp: current.systemApp || mapped.systemApp,
              suspended: mapped.suspended,
              hidden: mapped.hidden,
              cloneEligibility: mapped.cloneEligibility,
              installerActionRequired: mapped.installerActionRequired,
              iconBytes: mapped.iconBytes ?? current.iconBytes,
            );
    }

    final result = byPackage.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return result;
  }

  @override
  Future<WorkProfileOperationResult> startProvisioning() async =>
      _operation(await _api.startProvisioning());

  @override
  Future<WorkProfileOperationResult> requestQuietModeDisabled() async =>
      _operation(await _api.requestQuietModeDisabled());

  @override
  Future<PickedWorkDocument?> pickWorkDocument() async {
    try {
      final value = await _api.pickWorkDocument();
      if (value == null) return null;
      return PickedWorkDocument(
        uri: Uri.parse(value.uri),
        displayName: value.displayName,
        mimeType: value.mimeType,
        canDelete: value.canDelete,
        sizeBytes: value.sizeBytes?.toInt(),
      );
    } on PlatformException catch (error) {
      throw WorkProfileOperationException(
        _errorCodeFromPlatform(error.code),
        message: error.message,
      );
    }
  }

  @override
  Future<WorkProfileOperationResult> openStore(String packageName) async =>
      _operation(await _api.openWorkStore(packageName));

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async =>
      _operation(await _api.cloneToWorkProfile(packageName));

  @override
  Future<WorkProfileOperationResult> launch(String packageName) async =>
      _operation(await _api.launchWorkApp(packageName));

  @override
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  ) async => _operation(await _api.setSuspended(packageName, suspended));

  @override
  Future<WorkProfileOperationResult> setHidden(
    String packageName,
    bool hidden,
  ) async => _operation(await _api.setHidden(packageName, hidden));

  @override
  Future<WorkProfileOperationResult> uninstall(String packageName) async =>
      _operation(await _api.uninstallWorkApp(packageName));

  @override
  Future<WorkProfileOperationResult> destroyProfile() async =>
      _operation(await _api.destroyWorkProfile());

  WorkProfileOperationResult _operation(native.NativeOperationResult value) {
    if (value.ok) return const WorkProfileOperationResult.success();
    return WorkProfileOperationResult.failure(
      _errorCode(value.errorCode),
      message: value.message,
    );
  }

  WorkProfileState _profileState(
    native.NativeWorkProfileState value,
  ) => switch (value) {
    native.NativeWorkProfileState.unsupported => WorkProfileState.unsupported,
    native.NativeWorkProfileState.absent => WorkProfileState.absent,
    native.NativeWorkProfileState.provisioning => WorkProfileState.provisioning,
    native.NativeWorkProfileState.ready => WorkProfileState.ready,
    native.NativeWorkProfileState.quiet => WorkProfileState.quiet,
    native.NativeWorkProfileState.conflictingProfile =>
      WorkProfileState.conflictingProfile,
    native.NativeWorkProfileState.policyDenied => WorkProfileState.policyDenied,
  };

  CloneEligibility _cloneEligibility(native.NativeCloneEligibility value) =>
      switch (value) {
        native.NativeCloneEligibility.eligible => CloneEligibility.eligible,
        native.NativeCloneEligibility.alreadyInstalled =>
          CloneEligibility.alreadyInstalled,
        native.NativeCloneEligibility.systemApp => CloneEligibility.systemApp,
        native.NativeCloneEligibility.packageIneligible =>
          CloneEligibility.packageIneligible,
        native.NativeCloneEligibility.storeFallbackRequired =>
          CloneEligibility.storeFallbackRequired,
        native.NativeCloneEligibility.unsupported =>
          CloneEligibility.unsupported,
      };

  ManagedAppState _appState(native.NativeManagedAppState value) =>
      ManagedAppState(
        packageName: value.packageName,
        label: value.label,
        presentPersonal: value.presentPersonal,
        presentWork: value.presentWork,
        launchableWork: value.launchableWork,
        systemApp: value.systemApp,
        suspended: value.suspended,
        hidden: value.hidden,
        cloneEligibility: _cloneEligibility(value.cloneEligibility),
        installerActionRequired: value.installerActionRequired,
        iconBytes: value.iconBytes,
      );

  WorkProfileErrorCode _errorCodeFromPlatform(String value) => switch (value) {
    'UNSUPPORTED' => WorkProfileErrorCode.unsupported,
    'POLICY_DENIED' => WorkProfileErrorCode.policyDenied,
    'PROFILE_ABSENT' => WorkProfileErrorCode.profileAbsent,
    'CONFLICTING_PROFILE' => WorkProfileErrorCode.conflictingProfile,
    'USER_ACTION_REQUIRED' => WorkProfileErrorCode.userActionRequired,
    'PACKAGE_INELIGIBLE' => WorkProfileErrorCode.packageIneligible,
    'INSTALLER_FAILURE' => WorkProfileErrorCode.installerFailure,
    'STORE_FALLBACK_REQUIRED' => WorkProfileErrorCode.storeFallbackRequired,
    'BRIDGE_TIMEOUT' => WorkProfileErrorCode.bridgeTimeout,
    'OEM_UNSUPPORTED' => WorkProfileErrorCode.oemUnsupported,
    'UNAUTHORIZED' => WorkProfileErrorCode.unauthorized,
    _ => WorkProfileErrorCode.oemUnsupported,
  };

  WorkProfileErrorCode _errorCode(native.NativeWorkProfileErrorCode? value) =>
      switch (value) {
        native.NativeWorkProfileErrorCode.unsupported =>
          WorkProfileErrorCode.unsupported,
        native.NativeWorkProfileErrorCode.policyDenied =>
          WorkProfileErrorCode.policyDenied,
        native.NativeWorkProfileErrorCode.profileAbsent =>
          WorkProfileErrorCode.profileAbsent,
        native.NativeWorkProfileErrorCode.conflictingProfile =>
          WorkProfileErrorCode.conflictingProfile,
        native.NativeWorkProfileErrorCode.userActionRequired =>
          WorkProfileErrorCode.userActionRequired,
        native.NativeWorkProfileErrorCode.packageIneligible =>
          WorkProfileErrorCode.packageIneligible,
        native.NativeWorkProfileErrorCode.installerFailure =>
          WorkProfileErrorCode.installerFailure,
        native.NativeWorkProfileErrorCode.storeFallbackRequired =>
          WorkProfileErrorCode.storeFallbackRequired,
        native.NativeWorkProfileErrorCode.bridgeTimeout =>
          WorkProfileErrorCode.bridgeTimeout,
        native.NativeWorkProfileErrorCode.oemUnsupported =>
          WorkProfileErrorCode.oemUnsupported,
        native.NativeWorkProfileErrorCode.unauthorized =>
          WorkProfileErrorCode.unauthorized,
        null => WorkProfileErrorCode.installerFailure,
      };
}

class UnavailableWorkProfileClient implements WorkProfileClient {
  const UnavailableWorkProfileClient();

  @override
  Future<WorkProfileCapability> getCapability() async =>
      const WorkProfileCapability(
        supported: false,
        provisioningAllowed: false,
        profileState: WorkProfileState.unsupported,
      );

  @override
  Future<List<ManagedAppState>> listApps() async => const [];

  @override
  Future<WorkProfileOperationResult> startProvisioning() async =>
      _unsupported();

  @override
  Future<WorkProfileOperationResult> requestQuietModeDisabled() async =>
      _unsupported();

  @override
  Future<PickedWorkDocument?> pickWorkDocument() async => null;

  @override
  Future<WorkProfileOperationResult> openStore(String packageName) async =>
      _unsupported();

  @override
  Future<WorkProfileOperationResult> clone(String packageName) async =>
      _unsupported();

  @override
  Future<WorkProfileOperationResult> launch(String packageName) async =>
      _unsupported();

  @override
  Future<WorkProfileOperationResult> setSuspended(
    String packageName,
    bool suspended,
  ) async => _unsupported();

  @override
  Future<WorkProfileOperationResult> setHidden(
    String packageName,
    bool hidden,
  ) async => _unsupported();

  @override
  Future<WorkProfileOperationResult> uninstall(String packageName) async =>
      _unsupported();

  @override
  Future<WorkProfileOperationResult> destroyProfile() async => _unsupported();

  WorkProfileOperationResult _unsupported() =>
      const WorkProfileOperationResult.failure(
        WorkProfileErrorCode.unsupported,
        message:
            'Android managed work profiles are not available on this platform.',
      );
}
