import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android portable vault uses SAF without broad storage permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final bridge = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/'
      'PortableVaultTreeBridge.kt',
    ).readAsStringSync();

    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(bridge, contains('Intent.ACTION_OPEN_DOCUMENT_TREE'));
    expect(bridge, contains('takePersistableUriPermission'));
    expect(bridge, contains('FLAG_GRANT_PERSISTABLE_URI_PERMISSION'));
  });

  test('Android SAF bridge exposes transactional streaming writes', () {
    final bridge = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/'
      'PortableVaultTreeBridge.kt',
    ).readAsStringSync();

    for (final method in [
      '"beginWrite"',
      '"appendWrite"',
      '"patchWrite"',
      '"commitWrite"',
      '"abortWrite"',
    ]) {
      expect(bridge, contains(method));
    }
    expect(bridge, contains('.partial-'));
    expect(bridge, contains('pending.stream.fd.sync()'));
    expect(bridge, contains('pending.temporary.renameTo(pending.targetName)'));
  });

  test('Android SAF bridge rejects traversal-like path segments', () {
    final bridge = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/'
      'PortableVaultTreeBridge.kt',
    ).readAsStringSync();

    expect(bridge, contains('it == "." || it == ".."'));
    expect(bridge, contains("it.contains('\\\\')"));
  });

  test('Move to Vault deletes original through granted document URI', () {
    final activity = File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/'
      'MainActivity.kt',
    ).readAsStringSync();
    final media = File('lib/features/media/media_vault_service.dart')
        .readAsStringSync();

    expect(activity, contains('"deleteDocumentUri"'));
    expect(activity, contains('DocumentsContract.deleteDocument'));
    expect(media, contains('accessMode: AndroidSAFAccessMode.readWrite'));
    expect(media, contains('file.safHandle?.uri'));
  });
}
