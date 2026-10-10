import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/apps/clone_profile_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('private_vault/clone_profile_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  final expectedStates = <String, CloneProfileCapabilityState>{
    'ready': CloneProfileCapabilityState.ready,
    'privilege_required': CloneProfileCapabilityState.privilegeRequired,
    'clone_profile_unsupported_by_oem':
        CloneProfileCapabilityState.cloneProfileUnsupportedByOem,
    'conflicting_external_clone_profile':
        CloneProfileCapabilityState.conflictingExternalCloneProfile,
    'operation_failed': CloneProfileCapabilityState.operationFailed,
  };

  for (final entry in expectedStates.entries) {
    test('maps native capability state ${entry.key}', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getCapability');
        return <String, Object?>{
          'state': entry.key,
          'userId': 12,
          'message': 'detail',
        };
      });

      final capability = await PlatformCloneProfileClient(channel: channel)
          .getCapability();

      expect(capability.state, entry.value);
      expect(capability.userId, 12);
      expect(capability.message, 'detail');
    });
  }

  test('unknown and null native states fail closed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => <String, Object?>{'state': 'unexpected_state'},
    );

    final client = PlatformCloneProfileClient(channel: channel);
    expect(
      (await client.getCapability()).state,
      CloneProfileCapabilityState.operationFailed,
    );

    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      (await client.getCapability()).state,
      CloneProfileCapabilityState.operationFailed,
    );
  });

  test('ready app list preserves clone state and icon bytes', () async {
    final icon = Uint8List.fromList(<int>[1, 2, 3]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listApps');
      return <String, Object?>{
        'state': 'ready',
        'userId': 10,
        'apps': <Object?>[
          <String, Object?>{
            'packageName': 'com.example.alpha',
            'label': 'Alpha',
            'cloned': true,
            'iconBytes': icon,
          },
        ],
      };
    });

    final result = await PlatformCloneProfileClient(channel: channel)
        .listApps();

    expect(result.capability.state, CloneProfileCapabilityState.ready);
    expect(result.capability.userId, 10);
    expect(result.apps, hasLength(1));
    expect(result.apps.single.packageName, 'com.example.alpha');
    expect(result.apps.single.label, 'Alpha');
    expect(result.apps.single.cloned, isTrue);
    expect(result.apps.single.iconBytes, icon);
  });

  test('platform channel failures become typed operation failures', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'native_failure', message: 'boom');
    });

    final client = PlatformCloneProfileClient(channel: channel);

    expect(
      (await client.getCapability()).state,
      CloneProfileCapabilityState.operationFailed,
    );
    expect(
      (await client.listApps()).capability.state,
      CloneProfileCapabilityState.operationFailed,
    );
    expect(
      (await client.clone('com.example.alpha')).capability.state,
      CloneProfileCapabilityState.operationFailed,
    );
    expect(
      (await client.launch('com.example.alpha')).capability.state,
      CloneProfileCapabilityState.operationFailed,
    );
    expect(
      (await client.uninstall('com.example.alpha')).capability.state,
      CloneProfileCapabilityState.operationFailed,
    );
    expect(await client.requestPrivilege(), isFalse);
  });

  test('operation forwards the exact package once and maps ok', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls += 1;
      expect(call.method, 'clone');
      expect(call.arguments, <String, Object?>{
        'packageName': 'com.example.alpha',
      });
      return <String, Object?>{'state': 'ready', 'userId': 10, 'ok': true};
    });

    final result = await PlatformCloneProfileClient(channel: channel)
        .clone('com.example.alpha');

    expect(calls, 1);
    expect(result.ok, isTrue);
    expect(result.capability.state, CloneProfileCapabilityState.ready);
    expect(result.capability.userId, 10);
  });
}
