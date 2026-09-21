import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/work_profile_models.dart';

void main() {
  test(
    'capability distinguishes provisionable from unsupported and conflicts',
    () {
      const supported = WorkProfileCapability(
        supported: true,
        provisioningAllowed: true,
        profileState: WorkProfileState.absent,
      );
      expect(supported.canProvision, isTrue);

      const unsupported = WorkProfileCapability(
        supported: false,
        provisioningAllowed: false,
        profileState: WorkProfileState.unsupported,
      );
      expect(unsupported.canProvision, isFalse);

      const conflict = WorkProfileCapability(
        supported: true,
        provisioningAllowed: false,
        profileState: WorkProfileState.conflictingProfile,
      );
      expect(conflict.canProvision, isFalse);
    },
  );

  test('store fallback is a distinct clone/install failure', () {
    const result = WorkProfileOperationResult.failure(
      WorkProfileErrorCode.storeFallbackRequired,
      message: 'Use the work-profile store.',
    );

    expect(result.ok, isFalse);
    expect(result.errorCode, WorkProfileErrorCode.storeFallbackRequired);
  });

  test('managed app state keeps personal and work presence separate', () {
    const app = ManagedAppState(
      packageName: 'example.app',
      label: 'Example',
      presentPersonal: true,
      presentWork: false,
      launchableWork: false,
      systemApp: false,
      suspended: false,
      hidden: false,
      cloneEligibility: CloneEligibility.eligible,
      installerActionRequired: false,
    );

    expect(app.presentPersonal, isTrue);
    expect(app.presentWork, isFalse);
    expect(app.canLaunch, isFalse);
    expect(app.canClone, isTrue);
  });
}
