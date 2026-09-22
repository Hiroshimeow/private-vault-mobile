import 'package:private_vault_mobile/features/vault/vault_repository.dart';

class LegacyVaultMigrationPreview {
  const LegacyVaultMigrationPreview({
    required this.itemCount,
    this.keyUnavailable = false,
    this.readFailure = false,
  });

  final int itemCount;
  final bool keyUnavailable;
  final bool readFailure;

  bool get canMigrate => itemCount > 0 && !keyUnavailable && !readFailure;
}

class LegacyVaultMigrationFailure {
  const LegacyVaultMigrationFailure({required this.sourceId});

  final String sourceId;
}

class LegacyVaultMigrationResult {
  const LegacyVaultMigrationResult({
    required this.importedCount,
    required this.failures,
  });

  final int importedCount;
  final List<LegacyVaultMigrationFailure> failures;

  int get failedCount => failures.length;
}

class LegacyVaultMigrationService {
  const LegacyVaultMigrationService({
    required this.source,
    required this.target,
  });

  final VaultRepository source;
  final VaultRepository target;

  Future<LegacyVaultMigrationPreview> inspect() async {
    try {
      final items = await source.list();
      return LegacyVaultMigrationPreview(itemCount: items.length);
    } on MissingVaultKeyException {
      return const LegacyVaultMigrationPreview(
        itemCount: 0,
        keyUnavailable: true,
      );
    } on Object {
      return const LegacyVaultMigrationPreview(itemCount: 0, readFailure: true);
    }
  }

  Future<LegacyVaultMigrationResult> copyAll() async {
    final sourceItems = await source.list();
    var importedCount = 0;
    final failures = <LegacyVaultMigrationFailure>[];

    for (final original in sourceItems) {
      try {
        final bytes = await source.readBytes(original.id);
        var kind = original.kind;
        if (kind == VaultItemKind.unknown) {
          final refreshed = await source.list();
          final resolved = refreshed
              .where((item) => item.id == original.id)
              .firstOrNull;
          if (resolved == null || resolved.kind == VaultItemKind.unknown) {
            throw const VaultFormatException();
          }
          kind = resolved.kind;
        }

        await target.addBytes(bytes, kind: kind);
        importedCount += 1;
      } on Object {
        failures.add(LegacyVaultMigrationFailure(sourceId: original.id));
      }
    }

    return LegacyVaultMigrationResult(
      importedCount: importedCount,
      failures: List.unmodifiable(failures),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
