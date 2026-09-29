import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed Work Profile production surface is removed', () async {
    final main = await File('lib/main.dart').readAsString();
    final app = await File('lib/app/private_vault_app.dart').readAsString();
    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/MainActivity.kt',
    ).readAsString();
    final client = await File('lib/features/apps/work_profile_client.dart')
        .readAsString();
    final shuttle = await File('lib/features/apps/vault_shuttle_service.dart')
        .readAsString();

    expect(main, isNot(contains('PigeonWorkProfileClient')));
    expect(main, isNot(contains('VaultShuttleService(')));
    expect(main, isNot(contains('PigeonVaultShuttleBridge')));
    expect(app, isNot(contains('workProfileClient: widget.workProfileClient')));
    expect(app, isNot(contains('final WorkProfileClient? workProfileClient;')));
    expect(app, isNot(contains('vaultShuttle: widget.vaultShuttle')));
    expect(client, isNot(contains('generated/work_profile_api.g.dart')));
    expect(client, isNot(contains('class PigeonWorkProfileClient')));
    expect(shuttle, isNot(contains('generated/work_profile_api.g.dart')));
    expect(shuttle, isNot(contains('class PigeonVaultShuttleBridge')));
    expect(shuttle, isNot(contains('class VaultShuttleService')));

    expect(manifest, isNot(contains('PrivateVaultDeviceAdminReceiver')));
    expect(manifest, isNot(contains('WorkProfile')));
    expect(manifest, isNot(contains('VaultShuttleProvider')));
    expect(activity, isNot(contains('WorkProfileHostApi')));
    expect(activity, isNot(contains('workProfileApiAdapter')));

    for (final path in <String>[
      'lib/features/apps/work_profile_home.dart',
      'lib/platform/generated/work_profile_api.g.dart',
      'pigeons/work_profile_api.dart',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileApi.g.kt',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileBridgeActivity.kt',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileHostApiAdapter.kt',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileNativePolicy.kt',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileProvisioningActivities.kt',
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/VaultShuttleProvider.kt',
      'android/app/src/debug/kotlin/io/hiroshimeow/private_vault_mobile/WorkProfileDebugBootstrapReceiver.kt',
      'android/app/src/main/res/xml/device_admin_receiver.xml',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }

    expect(manifest, contains('.CloneTransferProvider'));
    expect(activity, contains('CloneProfileBridge'));
  });
}
