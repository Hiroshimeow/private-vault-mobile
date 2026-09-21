import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum CoverPreference { calculator, notes }

class AppSettings {
  const AppSettings({
    required this.cover,
    required this.panicShakeEnabled,
    required this.panicFaceDownEnabled,
    required this.shakeThresholdG,
    required this.faceDownDelayMs,
    required this.autoLockSeconds,
    required this.biometricsEnabled,
    this.unlockHoldMs = 2000,
    required this.browserClearOnClose,
    required this.confirmExport,
    required this.darkMode,
  });

  const AppSettings.defaults()
    : cover = CoverPreference.calculator,
      panicShakeEnabled = true,
      panicFaceDownEnabled = false,
      shakeThresholdG = 2.5,
      faceDownDelayMs = 1200,
      autoLockSeconds = 0,
      biometricsEnabled = false,
      unlockHoldMs = 2000,
      browserClearOnClose = true,
      confirmExport = true,
      darkMode = false;

  final CoverPreference cover;
  final bool panicShakeEnabled;
  final bool panicFaceDownEnabled;
  final double shakeThresholdG;
  final int faceDownDelayMs;
  final int autoLockSeconds;
  final bool biometricsEnabled;
  final int unlockHoldMs;
  final bool browserClearOnClose;
  final bool confirmExport;
  final bool darkMode;

  AppSettings copyWith({
    CoverPreference? cover,
    bool? panicShakeEnabled,
    bool? panicFaceDownEnabled,
    double? shakeThresholdG,
    int? faceDownDelayMs,
    int? autoLockSeconds,
    bool? biometricsEnabled,
    int? unlockHoldMs,
    bool? browserClearOnClose,
    bool? confirmExport,
    bool? darkMode,
  }) {
    return AppSettings(
      cover: cover ?? this.cover,
      panicShakeEnabled: panicShakeEnabled ?? this.panicShakeEnabled,
      panicFaceDownEnabled: panicFaceDownEnabled ?? this.panicFaceDownEnabled,
      shakeThresholdG: shakeThresholdG ?? this.shakeThresholdG,
      faceDownDelayMs: faceDownDelayMs ?? this.faceDownDelayMs,
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      unlockHoldMs: unlockHoldMs ?? this.unlockHoldMs,
      browserClearOnClose: browserClearOnClose ?? this.browserClearOnClose,
      confirmExport: confirmExport ?? this.confirmExport,
      darkMode: darkMode ?? this.darkMode,
    );
  }

  Map<String, Object> toJson() => {
    'cover': cover.name,
    'panicShakeEnabled': panicShakeEnabled,
    'panicFaceDownEnabled': panicFaceDownEnabled,
    'shakeThresholdG': shakeThresholdG,
    'faceDownDelayMs': faceDownDelayMs,
    'autoLockSeconds': autoLockSeconds,
    'biometricsEnabled': biometricsEnabled,
    'unlockHoldMs': unlockHoldMs,
    'browserClearOnClose': browserClearOnClose,
    'confirmExport': confirmExport,
    'darkMode': darkMode,
  };

  static AppSettings? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final coverRaw = raw['cover'];
    final panicShake = raw['panicShakeEnabled'];
    final panicFaceDown = raw['panicFaceDownEnabled'];
    final shake = raw['shakeThresholdG'];
    final faceDown = raw['faceDownDelayMs'];
    final autoLock = raw['autoLockSeconds'];
    final biometrics = raw['biometricsEnabled'];
    final unlockHold = raw['unlockHoldMs'] ?? 2000;
    final clearOnClose = raw['browserClearOnClose'];
    final confirmExport = raw['confirmExport'];
    final darkMode = raw['darkMode'];

    if (coverRaw is! String ||
        panicShake is! bool ||
        panicFaceDown is! bool ||
        shake is! num ||
        faceDown is! int ||
        autoLock is! int ||
        biometrics is! bool ||
        unlockHold is! int ||
        clearOnClose is! bool ||
        confirmExport is! bool ||
        darkMode is! bool) {
      return null;
    }

    final cover = CoverPreference.values
        .where((value) => value.name == coverRaw)
        .firstOrNull;
    if (cover == null ||
        shake < 1.3 ||
        shake > 6 ||
        faceDown < 300 ||
        faceDown > 5000 ||
        autoLock < 0 ||
        autoLock > 3600 ||
        unlockHold < 700 ||
        unlockHold > 3000) {
      return null;
    }

    return AppSettings(
      cover: cover,
      panicShakeEnabled: panicShake,
      panicFaceDownEnabled: panicFaceDown,
      shakeThresholdG: shake.toDouble(),
      faceDownDelayMs: faceDown,
      autoLockSeconds: autoLock,
      biometricsEnabled: biometrics,
      unlockHoldMs: unlockHold,
      browserClearOnClose: clearOnClose,
      confirmExport: confirmExport,
      darkMode: darkMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.cover == cover &&
      other.panicShakeEnabled == panicShakeEnabled &&
      other.panicFaceDownEnabled == panicFaceDownEnabled &&
      other.shakeThresholdG == shakeThresholdG &&
      other.faceDownDelayMs == faceDownDelayMs &&
      other.autoLockSeconds == autoLockSeconds &&
      other.biometricsEnabled == biometricsEnabled &&
      other.unlockHoldMs == unlockHoldMs &&
      other.browserClearOnClose == browserClearOnClose &&
      other.confirmExport == confirmExport &&
      other.darkMode == darkMode;

  @override
  int get hashCode => Object.hash(
    cover,
    panicShakeEnabled,
    panicFaceDownEnabled,
    shakeThresholdG,
    faceDownDelayMs,
    autoLockSeconds,
    biometricsEnabled,
    unlockHoldMs,
    browserClearOnClose,
    confirmExport,
    darkMode,
  );
}

abstract interface class SettingsStorage {
  Future<String?> read();
  Future<void> write(String encoded);
}

class SharedPreferencesSettingsStorage implements SettingsStorage {
  SharedPreferencesSettingsStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'app_settings_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String encoded) => _preferences.setString(_key, encoded);
}

class AppSettingsStore {
  AppSettingsStore(this._storage);

  final SettingsStorage _storage;

  Future<AppSettings> load() async {
    final encoded = await _storage.read();
    if (encoded == null) return const AppSettings.defaults();
    try {
      final parsed = AppSettings.fromJson(jsonDecode(encoded));
      return parsed ?? const AppSettings.defaults();
    } on FormatException {
      return const AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) =>
      _storage.write(jsonEncode(settings.toJson()));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
