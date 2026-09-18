import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/platform/disguise_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('private_vault/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('maps native capabilities and disguise choice', () async {
    String? requested;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDisguiseCapabilities') {
        return <String, Object>{
          'androidLauncherAliases': true,
          'iosAlternateIcons': false,
        };
      }
      if (call.method == 'setDisguise') {
        requested = call.arguments as String;
        return true;
      }
      return null;
    });

    final bridge = PlatformDisguiseBridge(channel: channel);
    final capabilities = await bridge.capabilities();
    expect(capabilities.androidLauncherAliases, isTrue);
    expect(capabilities.iosAlternateIcons, isFalse);

    expect(await bridge.apply(DisguiseChoice.notes), isTrue);
    expect(requested, 'notes');
  });

  test('native channel failure is reported as unsupported/false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unsupported');
    });

    final bridge = PlatformDisguiseBridge(channel: channel);
    expect(await bridge.capabilities(), const DisguiseCapabilities());
    expect(await bridge.apply(DisguiseChoice.calculator), isFalse);
  });
}
