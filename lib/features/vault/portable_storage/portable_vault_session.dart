import 'package:private_vault_mobile/features/vault/crypto_v2/portable_vault_key_deriver.dart';

class PortableVaultSession {
  PortableVaultSession({this.keyDeriver = const PortableVaultKeyDeriver()});

  final PortableVaultKeyDeriver keyDeriver;
  PortableVaultKeyMaterial? _material;
  int _generation = 0;

  bool get isOpen => _material != null;
  int get generation => _generation;

  Future<void> open(String pin) async {
    final next = await keyDeriver.derive(pin);
    _material = next;
    _generation += 1;
  }

  PortableVaultKeyMaterial requireMaterial() {
    final material = _material;
    if (material == null) throw const PortableVaultSessionClosedException();
    return material;
  }

  void clear() {
    if (_material == null) return;
    _material = null;
    _generation += 1;
  }
}

class PortableVaultSessionClosedException implements Exception {
  const PortableVaultSessionClosedException();
}
