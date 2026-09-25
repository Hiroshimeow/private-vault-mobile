import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Apps surface uses real clone-profile backend, not managed provisioning',
    () async {
      final app = await File('lib/app/private_vault_app.dart').readAsString();
      final main = await File('lib/main.dart').readAsString();
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/CloneProfileBridge.kt',
      ).readAsString();
      final service = await File(
        'android/app/src/main/java/io/hiroshimeow/private_vault_mobile/CloneProfileUserService.java',
      ).readAsString();

      expect(app, contains('CloneProfileHome('));
      expect(app, contains('widget.cloneProfileClient'));
      expect(main, contains('PlatformCloneProfileClient()'));

      final cloneImplementation = '$bridge\n$service';
      expect(
        cloneImplementation,
        contains('android.os.usertype.profile.CLONE'),
      );
      expect(cloneImplementation, contains('"current-user"'));
      expect(cloneImplementation, contains('"get-current-user"'));
      expect(cloneImplementation, contains('"create-clone"'));
      expect(cloneImplementation, contains('"install-existing"'));
      expect(cloneImplementation, contains('"--user"'));
      expect(
        cloneImplementation,
        isNot(contains('ACTION_PROVISION_MANAGED_PROFILE')),
      );
      expect(
        cloneImplementation,
        isNot(contains('ACTION_PROVISION_MANAGED_DEVICE')),
      );
    },
  );

  test(
    'clone privilege bridge is fixed-operation and fail-closed on ownership',
    () async {
      final bridge = await File(
        'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/CloneProfileBridge.kt',
      ).readAsString();
      final service = await File(
        'android/app/src/main/java/io/hiroshimeow/private_vault_mobile/CloneProfileUserService.java',
      ).readAsString();
      final gradle = await File('android/app/build.gradle.kts').readAsString();

      expect(gradle, contains('dev.rikka.shizuku:api:13.1.5'));
      expect(gradle, contains('dev.rikka.shizuku:provider:13.1.5'));
      expect(bridge, contains('Shizuku.UserServiceArgs'));
      expect(bridge, contains('conflicting_external_clone_profile'));
      expect(bridge, contains('KEY_OWNED_CLONE_USER'));
      expect(service, contains('unsupported clone operation'));
      expect(bridge, isNot(contains('UserHandle.myUserId')));
      expect(bridge, isNot(contains('myUserHandle().identifier')));
      expect(service, isNot(contains('new String[]{"sh", "-c"')));
      expect(service, isNot(contains('new String[]{"bash", "-c"')));
    },
  );
}
