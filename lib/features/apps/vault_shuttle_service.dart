import 'package:private_vault_mobile/features/vault/vault_repository.dart';

/// Legacy lifecycle seam retained for confidentiality-boundary tests.
///
/// The managed Work Profile transport was removed; production does not
/// construct an implementation.
abstract interface class VaultShuttle {
  Future<List<VaultItem>> listVaultItems();

  Future<void> shareToIsolatedApp({
    required VaultItem item,
    required String packageName,
  });

  Future<void> purgeStagedPlaintext();
}
