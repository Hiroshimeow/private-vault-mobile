import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apps surface routes to standalone repackage clone backend', () async {
    final app = await File('lib/app/private_vault_app.dart').readAsString();
    final main = await File('lib/main.dart').readAsString();
    final activity = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/MainActivity.kt',
    ).readAsString();
    final bridge = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneCloneBridge.kt',
    ).readAsString();

    expect(app, contains('StandaloneCloneHome('));
    expect(app, contains('widget.standaloneCloneClient'));
    expect(main, contains('PlatformStandaloneCloneClient()'));
    expect(main, isNot(contains('PlatformCloneProfileClient()')));
    expect(activity, contains('StandaloneCloneBridge('));
    expect(activity, isNot(contains('CloneProfileBridge(')));
    expect(bridge, contains('private_vault/standalone_clone'));
    expect(bridge, isNot(contains('Shizuku')));
    expect(bridge, isNot(contains('profile.CLONE')));
  });

  test('standalone clone backend is fail-closed and vault-isolated', () async {
    final policy = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneClonePolicy.kt',
    ).readAsString();
    final engine = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneCloneEngine.kt',
    ).readAsString();
    final signing = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneCloneSigningStore.kt',
    ).readAsString();
    final store = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneCloneStore.kt',
    ).readAsString();
    final bridge = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/StandaloneCloneBridge.kt',
    ).readAsString();
    final gradle = await File('android/app/build.gradle.kts').readAsString();

    expect(gradle, contains('io.github.reandroid:ARSCLib:1.4.0'));
    expect(gradle, contains('com.github.MuntashirAkon:apksig-android:4.4.0'));
    expect(engine, contains('DEX payloads'));
    expect(engine, contains('source_signature_invalid'));
    expect(policy, contains('native_libs_unsupported'));
    expect(policy, contains('split_apk_unsupported'));
    expect(policy, contains('verified_app_link_unsupported'));
    expect(policy, contains('google_identity_bound_unsupported'));
    expect(policy, contains('hardcoded_application_id_unsupported'));
    expect(bridge, contains('clone_downgrade_unsupported'));
    expect(bridge, contains('clone_signature_invalid'));
    expect(bridge, contains('GET_SIGNING_CERTIFICATES'));
    expect(bridge, contains('cloneSignerSha256'));
    expect(bridge, contains('hasMultipleSigners()'));
    expect(bridge, contains('clone_signer_mismatch'));
    expect(engine, contains('validateTransformedApk(unsignedOutput'));
    expect(engine, contains('source_multi_signer_unsupported'));
    expect(policy, contains('deep_link_degraded'));
    expect(store, contains('compatibilityWarnings'));
    expect(store, contains('stale.deleteRecursively()'));
    expect(signing, contains('AndroidKeyStore'));
    expect(signing, contains('3072'));
    expect(store, contains('clone-lab'));
    expect(bridge, contains('ACTION_OPEN_DOCUMENT'));
    expect(bridge, contains('ACTION_INSTALL_PACKAGE'));
    expect(bridge, contains('ACTION_UNINSTALL_PACKAGE'));
    expect(bridge, contains('putExtra(Intent.EXTRA_RETURN_RESULT, true)'));
    expect(bridge, contains('startActivityForResult(intent, REQUEST_UNINSTALL_CLONE)'));
    expect(bridge, contains('resultCode == Activity.RESULT_OK'));
    expect(bridge, contains('store.removeRecordAndArtifact(pending.record.cloneId)'));
    expect(bridge, contains('pending.record.matchesOwnershipIdentity(current)'));
    expect(bridge, contains('store.updateInstallStatus(pending.record.cloneId, pending.record.installStatus)'));
    expect(bridge, contains('"uninstall_cancelled"'));
    expect(bridge, contains('"uninstall_failed"'));
    expect(bridge, isNot(contains('call.argument<String>("package")')));
    expect(bridge, isNot(contains('QUERY_ALL_PACKAGES')));

    final standaloneImplementation =
        '$policy\n$engine\n$signing\n$store\n$bridge';
    for (final forbidden in <String>[
      'VaultRepository',
      'VaultShuttle',
      'VaultKey',
      'masterKey',
      'decryptedMedia',
      'Shizuku',
      'profile.CLONE',
      'ACTION_PROVISION_MANAGED_PROFILE',
    ]) {
      expect(
        standaloneImplementation,
        isNot(contains(forbidden)),
        reason: 'standalone clone path must not depend on $forbidden',
      );
    }
  });
}
