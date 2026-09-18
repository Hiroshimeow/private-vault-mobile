import 'package:flutter/services.dart';

enum DisguiseChoice { calculator, notes }

class DisguiseCapabilities {
  const DisguiseCapabilities({
    this.androidLauncherAliases = false,
    this.iosAlternateIcons = false,
  });

  final bool androidLauncherAliases;
  final bool iosAlternateIcons;

  bool get isSupported => androidLauncherAliases || iosAlternateIcons;

  @override
  bool operator ==(Object other) =>
      other is DisguiseCapabilities &&
      other.androidLauncherAliases == androidLauncherAliases &&
      other.iosAlternateIcons == iosAlternateIcons;

  @override
  int get hashCode => Object.hash(androidLauncherAliases, iosAlternateIcons);
}

class PlatformDisguiseBridge {
  factory PlatformDisguiseBridge({
    MethodChannel channel = const MethodChannel('private_vault/platform'),
  }) => PlatformDisguiseBridge._(channel);

  PlatformDisguiseBridge._(this._channel);

  final MethodChannel _channel;

  Future<DisguiseCapabilities> capabilities() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getDisguiseCapabilities',
      );
      return DisguiseCapabilities(
        androidLauncherAliases: raw?['androidLauncherAliases'] == true,
        iosAlternateIcons: raw?['iosAlternateIcons'] == true,
      );
    } on PlatformException {
      return const DisguiseCapabilities();
    } on MissingPluginException {
      return const DisguiseCapabilities();
    }
  }

  Future<bool> apply(DisguiseChoice choice) async {
    try {
      return await _channel.invokeMethod<bool>('setDisguise', choice.name) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
