import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';

class _UnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => true;
}

class _ConflictingCloneClient implements CloneProfileClient {
  @override
  Future<CloneProfileCapability> getCapability() async =>
      const CloneProfileCapability(
        state: CloneProfileCapabilityState.conflictingExternalCloneProfile,
      );

  @override
  Future<CloneProfileAppList> listApps() async => const CloneProfileAppList(
    capability: CloneProfileCapability(
      state: CloneProfileCapabilityState.conflictingExternalCloneProfile,
      message: 'external clone',
    ),
    apps: [],
  );

  @override
  Future<bool> requestPrivilege() async => false;

  @override
  Future<CloneProfileOperationResult> clone(String packageName) =>
      throw StateError('clone must not be called');

  @override
  Future<CloneProfileOperationResult> launch(String packageName) =>
      throw StateError('launch must not be called');

  @override
  Future<CloneProfileOperationResult> uninstall(String packageName) =>
      throw StateError('uninstall must not be called');
}

void main() {
  testWidgets('Android workspace promotes Apps before Browser after unlock', (
    tester,
  ) async {
    final lock = LockController()..unlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _UnlockService(),
        cloneProfileClient: const UnavailableCloneProfileClient(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsWidgets);
    expect(find.text('Apps'), findsWidgets);
    expect(find.text('Browser'), findsWidgets);
    final apps = tester.getCenter(find.text('Apps').last).dx;
    final browser = tester.getCenter(find.text('Browser').last).dx;
    expect(apps, lessThan(browser));
  });

  testWidgets('Clone conflict stays fail-closed without a fallback path', (
    tester,
  ) async {
    final lock = LockController()..unlock();

    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _UnlockService(),
        cloneProfileClient: _ConflictingCloneClient(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apps').last);
    await tester.pumpAndSettle();

    expect(find.text('Existing clone profile detected'), findsOneWidget);
  });

  testWidgets('locked cover exposes no Apps or package inventory UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: LockController(),
        unlockService: _UnlockService(),
        cloneProfileClient: const UnavailableCloneProfileClient(),
      ),
    );

    expect(find.text('Apps'), findsNothing);
    expect(find.textContaining('clone profile'), findsNothing);
    expect(find.byIcon(Icons.apps), findsNothing);
  });
}
