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

  test('maps two-slot virtual clone capability and instances', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listApps':
          return <String, Object?>{
            'state': 'ready',
            'slotsAvailable': 1,
            'slotsTotal': 2,
            'apps': <Object?>[
              <String, Object?>{
                'packageName': 'example.fixture',
                'label': 'Fixture',
                'instances': <Object?>[
                  <String, Object?>{
                    'instanceId': 'slot0:example.fixture',
                    'slot': 0,
                    'state': 'ready',
                  },
                ],
              },
            ],
          };
        case 'clone':
          expect(call.arguments, <String, Object?>{'packageName': 'example.fixture'});
          return <String, Object?>{
            'ok': true,
            'state': 'ready',
            'slotsAvailable': 0,
            'slotsTotal': 2,
            'instanceId': 'slot1:example.fixture',
            'slot': 1,
          };
        case 'launch':
        case 'stop':
        case 'uninstall':
          expect(
            call.arguments,
            <String, Object?>{'instanceId': 'slot0:example.fixture'},
          );
          return <String, Object?>{
            'ok': true,
            'state': 'ready',
            'slotsAvailable': 1,
            'slotsTotal': 2,
          };
      }
      return null;
    });

    final client = PlatformCloneProfileClient(channel: channel);
    final appList = await client.listApps();
    expect(appList.capability.state, CloneProfileCapabilityState.ready);
    expect(appList.capability.slotsAvailable, 1);
    expect(appList.capability.slotsTotal, 2);
    expect(appList.apps.single.instances.single.instanceId, 'slot0:example.fixture');
    expect(appList.apps.single.instances.single.slot, 0);
    expect(appList.apps.single.canClone, isTrue);

    final cloned = await client.clone('example.fixture');
    expect(cloned.ok, isTrue);
    expect(cloned.instanceId, 'slot1:example.fixture');
    expect(cloned.slot, 1);

    expect((await client.launch('slot0:example.fixture')).ok, isTrue);
    expect((await client.stop('slot0:example.fixture')).ok, isTrue);
    expect((await client.uninstall('slot0:example.fixture')).ok, isTrue);
  });

  test('maps typed virtual runner failures', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => <String, Object?>{
      'state': 'runner_missing',
      'slotsAvailable': 0,
      'slotsTotal': 2,
      'message': 'slot helpers are not installed',
    });

    final capability = await PlatformCloneProfileClient(channel: channel).getCapability();
    expect(capability.state, CloneProfileCapabilityState.runnerMissing);
    expect(capability.ready, isFalse);
    expect(capability.message, contains('not installed'));
  });
}
