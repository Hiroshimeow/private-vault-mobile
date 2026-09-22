import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';

class PortableVaultSession {
  PortableVaultSession({this.keyDeriver = const PortableVaultKeyDeriver()});

  final PortableVaultKeyDeriver keyDeriver;
  PortableVaultKeyMaterial? _material;
  int _generation = 0;

  bool get isOpen => _material != null;
  int get generation => _generation;

  Future<PortableVaultKeyMaterial> prepare(String pin) =>
      keyDeriver.derive(pin);

  Future<void> open(String pin) async {
    activate(await prepare(pin));
  }

  void activate(PortableVaultKeyMaterial material) {
    final previous = _material;
    _material = material;
    _generation += 1;
    if (previous != null && !identical(previous, material)) {
      previous.destroy();
    }
  }

  PortableVaultKeyMaterial requireMaterial() {
    final material = _material;
    if (material == null) throw const PortableVaultSessionClosedException();
    return material;
  }

  void clear() {
    final material = _material;
    if (material == null) return;
    _material = null;
    _generation += 1;
    material.destroy();
  }
}

class PortableVaultSessionClosedException implements Exception {
  const PortableVaultSessionClosedException();
}
