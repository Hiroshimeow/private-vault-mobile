import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/settings/app_settings.dart';

class MemorySettingsStorage implements SettingsStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String encoded) async {
    value = encoded;
  }
}

void main() {
  test('defaults are privacy-preserving and usable', () {
    const settings = AppSettings.defaults();

    expect(settings.cover, CoverPreference.calculator);
    expect(settings.panicShakeEnabled, isTrue);
    expect(settings.panicFaceDownEnabled, isFalse);
    expect(settings.autoLockSeconds, 0);
    expect(settings.biometricsEnabled, isFalse);
    expect(settings.browserClearOnClose, isTrue);
    expect(settings.confirmExport, isTrue);
  });

  test('settings round trip through storage', () async {
    final storage = MemorySettingsStorage();
    final store = AppSettingsStore(storage);
    const expected = AppSettings(
      cover: CoverPreference.notes,
      panicShakeEnabled: false,
      panicFaceDownEnabled: true,
      shakeThresholdG: 3.2,
      faceDownDelayMs: 1600,
      autoLockSeconds: 30,
      biometricsEnabled: true,
      browserClearOnClose: false,
      confirmExport: true,
      darkMode: true,
    );

    await store.save(expected);
    expect(await store.load(), expected);
  });

  test('invalid persisted values fall back to safe defaults', () async {
    final storage = MemorySettingsStorage()..value = '{"autoLockSeconds":-100}';
    final store = AppSettingsStore(storage);

    expect(await store.load(), const AppSettings.defaults());
  });
}
