import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/auth/biometric_unlock.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/media/media_vault_service.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class FakeBiometricUnlock implements BiometricUnlock {
  FakeBiometricUnlock({this.available = true, this.accepted = true});

  final bool available;
  final bool accepted;

  @override
  Future<bool> authenticate() async => accepted;

  @override
  Future<bool> isAvailable() async => available;
}

class BoundaryVaultRepository implements VaultRepository {
  BoundaryVaultRepository() {
    final note = VaultItem(
      id: 'note-fixture',
      kind: VaultItemKind.note,
      createdAt: DateTime.utc(2026, 9, 18),
    );
    final document = VaultItem(
      id: 'document-fixture',
      kind: VaultItemKind.document,
      createdAt: DateTime.utc(2026, 9, 18, 1),
    );
    items.addAll([note, document]);
    bytesById[note.id] = Uint8List.fromList('Secret preview text'.codeUnits);
    bytesById[document.id] = Uint8List.fromList([1, 2, 3]);
  }

  final items = <VaultItem>[];
  final bytesById = <String, Uint8List>{};

  @override
  Future<VaultItem> addBytes(
    Uint8List bytes, {
    required VaultItemKind kind,
  }) async {
    final item = VaultItem(
      id: 'added-${items.length}',
      kind: kind,
      createdAt: DateTime.utc(2026, 9, 18, 2),
    );
    items.add(item);
    bytesById[item.id] = Uint8List.fromList(bytes);
    return item;
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
    bytesById.remove(id);
  }

  @override
  Future<List<VaultItem>> list() async => List.unmodifiable(items);

  @override
  Future<Uint8List> readBytes(String id) async => bytesById[id]!;
}

MediaVaultService boundaryMedia(BoundaryVaultRepository repository) {
  return MediaVaultService(
    repository: repository,
    pickImport: () async => null,
    capturePhoto: () async => null,
    saveExport: (_, _) async => true,
  );
}

class FakeUnlockService implements UnlockService {
  FakeUnlockService({this.pin = '482951'});

  final String pin;

  @override
  Future<bool> verify(String candidate) async => candidate == pin;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<void> configure(String pin) async {}
}

void main() {
  testWidgets(
    'locked launch renders calculator cover and no secret workspace text',
    (tester) async {
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: LockController(),
          unlockService: FakeUnlockService(),
        ),
      );

      expect(find.text('Calculator'), findsOneWidget);
      expect(find.byTooltip('Lock now'), findsNothing);
      expect(find.text('Browser'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    },
  );

  testWidgets('calculator cover performs addition while locked', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '2'));
    await tester.tap(find.widgetWithText(FilledButton, '+'));
    await tester.tap(find.widgetWithText(FilledButton, '3'));
    await tester.tap(find.widgetWithText(FilledButton, '='));
    await tester.pump();

    final display = tester.widget<Text>(
      find.byKey(const Key('calculator-display')),
    );
    expect(display.data, '5');
  });

  testWidgets('valid PIN unlocks and panic returns to cover', (tester) async {
    final lock = LockController();
    await tester.pumpWidget(
      PrivateVaultApp(lockController: lock, unlockService: FakeUnlockService()),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('unlock-pin')), '482951');
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Lock now'), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('enabled biometric unlock can open secret workspace', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
        biometricUnlock: FakeBiometricUnlock(),
        initialSettings: const AppSettings.defaults().copyWith(
          biometricsEnabled: true,
        ),
      ),
    );

    await tester.longPress(find.byKey(const Key('cover-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use biometrics'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Lock now'), findsOneWidget);
  });

  testWidgets(
    'manual lock purges decrypted preview and it does not resurrect after unlock',
    (tester) async {
      final lock = LockController();
      final repository = BoundaryVaultRepository();
      await tester.pumpWidget(
        PrivateVaultApp(
          lockController: lock,
          unlockService: FakeUnlockService(),
          vaultRepository: repository,
          mediaService: boundaryMedia(repository),
        ),
      );

      lock.unlock();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protected note'));
      await tester.pumpAndSettle();
      expect(find.text('Secret preview text'), findsOneWidget);

      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('Calculator'), findsOneWidget);
      expect(find.text('Secret preview text'), findsNothing);

      lock.unlock();
      await tester.pumpAndSettle();
      expect(find.text('Protected note'), findsOneWidget);
      expect(find.text('Secret preview text'), findsNothing);
    },
  );

  testWidgets('panic lock purges new-note text entry dialog', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vault-new-note')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vault-note-input')), findsOneWidget);

    lock.panic();
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.byKey(const Key('vault-note-input')), findsNothing);
  });

  testWidgets('background lock purges export confirmation', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
        initialSettings: const AppSettings.defaults().copyWith(
          autoLockSeconds: 0,
        ),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();
    expect(find.text('Export this item?'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(lock.isLocked, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Export this item?'), findsNothing);
  });

  testWidgets('manual lock purges delete confirmation', (tester) async {
    final lock = LockController();
    final repository = BoundaryVaultRepository();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: FakeUnlockService(),
        vaultRepository: repository,
        mediaService: boundaryMedia(repository),
      ),
    );

    lock.unlock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protected document'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from vault?'), findsOneWidget);

    lock.lock();
    await tester.pumpAndSettle();
    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Delete from vault?'), findsNothing);
  });

  testWidgets('notes cover is functional without exposing secret routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: FakeUnlockService(),
        initialCover: CoverKind.notes,
      ),
    );

    await tester.enterText(find.byKey(const Key('todo-input')), 'Buy milk');
    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pump();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });
}
