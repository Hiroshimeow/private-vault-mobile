import 'package:pigeon/pigeon.dart';

enum NativeWorkProfileState {
  unsupported,
  absent,
  provisioning,
  ready,
  conflictingProfile,
  policyDenied,
}

enum NativeCloneEligibility {
  eligible,
  alreadyInstalled,
  systemApp,
  packageIneligible,
  storeFallbackRequired,
  unsupported,
}

enum NativeWorkProfileErrorCode {
  unsupported,
  policyDenied,
  profileAbsent,
  conflictingProfile,
  userActionRequired,
  packageIneligible,
  installerFailure,
  storeFallbackRequired,
  oemUnsupported,
  unauthorized,
}

class NativeWorkProfileCapability {
  NativeWorkProfileCapability({
    required this.supported,
    required this.provisioningAllowed,
    required this.profileState,
  });

  bool supported;
  bool provisioningAllowed;
  NativeWorkProfileState profileState;
}

class NativeManagedAppState {
  NativeManagedAppState({
    required this.packageName,
    required this.label,
    required this.presentPersonal,
    required this.presentWork,
    required this.launchableWork,
    required this.systemApp,
    required this.suspended,
    required this.hidden,
    required this.cloneEligibility,
    required this.installerActionRequired,
  });

  String packageName;
  String label;
  bool presentPersonal;
  bool presentWork;
  bool launchableWork;
  bool systemApp;
  bool suspended;
  bool hidden;
  NativeCloneEligibility cloneEligibility;
  bool installerActionRequired;
}

class NativeOperationResult {
  NativeOperationResult({required this.ok, this.errorCode, this.message});

  bool ok;
  NativeWorkProfileErrorCode? errorCode;
  String? message;
}

@HostApi()
abstract class WorkProfileHostApi {
  NativeWorkProfileCapability getCapability();
  NativeWorkProfileState getProfileState();
  @asyncCallback
  NativeOperationResult startProvisioning();
  List<NativeManagedAppState> listPersonalApps();
  @asyncCallback
  List<NativeManagedAppState> listWorkApps();
  @asyncCallback
  NativeManagedAppState? getAppState(String packageName);
  @asyncCallback
  NativeOperationResult cloneToWorkProfile(String packageName);
  @asyncCallback
  NativeOperationResult launchWorkApp(String packageName);
  @asyncCallback
  NativeOperationResult setSuspended(String packageName, bool suspended);
  @asyncCallback
  NativeOperationResult setHidden(String packageName, bool hidden);
  @asyncCallback
  NativeOperationResult uninstallWorkApp(String packageName);
  @asyncCallback
  NativeOperationResult destroyWorkProfile();
}
