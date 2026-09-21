enum WorkProfileState {
  unsupported,
  absent,
  provisioning,
  ready,
  conflictingProfile,
  policyDenied,
}

enum CloneEligibility {
  eligible,
  alreadyInstalled,
  systemApp,
  packageIneligible,
  storeFallbackRequired,
  unsupported,
}

enum WorkProfileErrorCode {
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

class WorkProfileCapability {
  const WorkProfileCapability({
    required this.supported,
    required this.provisioningAllowed,
    required this.profileState,
  });

  final bool supported;
  final bool provisioningAllowed;
  final WorkProfileState profileState;

  bool get canProvision =>
      supported &&
      provisioningAllowed &&
      profileState == WorkProfileState.absent;
}

class ManagedAppState {
  const ManagedAppState({
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

  final String packageName;
  final String label;
  final bool presentPersonal;
  final bool presentWork;
  final bool launchableWork;
  final bool systemApp;
  final bool suspended;
  final bool hidden;
  final CloneEligibility cloneEligibility;
  final bool installerActionRequired;

  bool get canLaunch => presentWork && launchableWork && !suspended && !hidden;

  bool get canClone =>
      presentPersonal &&
      !presentWork &&
      (cloneEligibility == CloneEligibility.eligible ||
          cloneEligibility == CloneEligibility.systemApp);
}

class WorkProfileOperationResult {
  const WorkProfileOperationResult.success()
    : ok = true,
      errorCode = null,
      message = null;

  const WorkProfileOperationResult.failure(this.errorCode, {this.message})
    : ok = false;

  final bool ok;
  final WorkProfileErrorCode? errorCode;
  final String? message;
}
