import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('private_vault/clone_profile');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('listApps preserves two helper-slot instance assignments', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listApps');
      return <String, Object?>{
        'state': 'ready',
        'slots': <Object?>[
          <String, Object?>{'slot': 0, 'occupied': true, 'packageName': 'io.example.app'},
          <String, Object?>{'slot': 1, 'occupied': false},
        ],
        'apps': <Object?>[
          <String, Object?>{
            'packageName': 'io.example.app',
            'label': 'Example',
            'slots': <Object?>[0],
          },
        ],
      };
    });

    final result = await PlatformCloneProfileClient(channel: channel).listApps();
    expect(result.capability.ready, isTrue);
    expect(result.capability.slots, hasLength(2));
    expect(result.capability.slots.first.packageName, 'io.example.app');
    expect(result.apps.single.slots, <int>[0]);
  });

  test('clone sends explicit slot and preserves typed transform failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'clone');
      expect(call.arguments, <String, Object?>{'packageName': 'io.example.app', 'slot': 1});
      return <String, Object?>{
        'state': 'unsupported_provider',
        'ok': false,
        'message': 'providers are not supported by this prototype',
      };
    });

    final result = await PlatformCloneProfileClient(channel: channel).clone('io.example.app', 1);
    expect(result.ok, isFalse);
    expect(result.capability.state, CloneProfileCapabilityState.unsupportedProvider);
  });
}
