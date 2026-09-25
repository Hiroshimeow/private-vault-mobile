import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SAF enumeration is batched and off the Android UI thread', () async {
    final native = await File(
      'android/app/src/main/kotlin/io/hiroshimeow/private_vault_mobile/PortableVaultTreeBridge.kt',
    ).readAsString();
    final dartBridge = await File(
      'lib/platform/portable_vault_tree_bridge.dart',
    ).readAsString();
    final repository = await File(
      'lib/features/vault/portable_storage/portable_vault_repository.dart',
    ).readAsString();

    expect(native, contains('Executors.newSingleThreadExecutor()'));
    expect(native, contains('ioExecutor.execute'));
    expect(
      native,
      contains('DocumentsContract.buildChildDocumentsUriUsingTree'),
    );
    expect(native, contains('DocumentsContract.Document.COLUMN_DOCUMENT_ID'));
    expect(native, contains('DocumentsContract.Document.COLUMN_DISPLAY_NAME'));
    expect(native, contains('DocumentsContract.Document.COLUMN_SIZE'));
    expect(native, contains('DocumentsContract.Document.COLUMN_LAST_MODIFIED'));
    expect(native, isNot(contains('DocumentFile')));
    expect(native, isNot(contains('.findFile(')));
    expect(native, isNot(contains('dir.listFiles()')));
    expect(native, isNot(contains('file.length()')));
    expect(native, isNot(contains('file.lastModified()')));
    expect(native, contains('DocumentsContract.createDocument'));
    expect(native, contains('DocumentsContract.renameDocument'));
    expect(native, contains('DocumentsContract.deleteDocument'));
    expect(native, contains('findChild(parentUri: Uri, displayName: String)'));

    expect(dartBridge, contains("invokeListMethod<String>('list'"));
    expect(dartBridge, contains('invokeMapMethod<Object?, Object?>('));
    expect(dartBridge, contains("'metadata'"));
    expect(repository, contains('PortableVaultEntryMetadataStorage'));
    expect(repository, contains('.metadata(_objectPath(namespaceId, id))'));
    expect(
      repository,
      isNot(contains(r".listMetadata('$namespaceId/objects')")),
    );
  });
}
