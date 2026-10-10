import 'package:flutter/services.dart';

enum CloneProfileCapabilityState {
  ready,
  runnerMissing,
  engineUnsupported,
  unsupportedAbi,
  operationFailed,
}

class CloneProfileCapability {
  const CloneProfileCapability({
    required this.state,
    required this.slotsAvailable,
    required this.slotsTotal,
    this.message,
  });

  final CloneProfileCapabilityState state;
  final int slotsAvailable;
  final int slotsTotal;
  final String? message;

  bool get ready => state == CloneProfileCapabilityState.ready;
}

class CloneInstance {
  const CloneInstance({
    required this.instanceId,
    required this.slot,
    required this.state,
  });

  final String instanceId;
  final int slot;
  final String state;
}

class CloneProfileApp {
  const CloneProfileApp({
    required this.packageName,
    required this.label,
    required this.instances,
    this.iconBytes,
  });

  final String packageName;
  final String label;
  final List<CloneInstance> instances;
  final Uint8List? iconBytes;

  bool get canClone => instances.length < 2;
}

class CloneProfileAppList {
  const CloneProfileAppList({required this.capability, required this.apps});

  final CloneProfileCapability capability;
  final List<CloneProfileApp> apps;
}

class CloneProfileOperationResult {
  const CloneProfileOperationResult({
    required this.capability,
    required this.ok,
    this.instanceId,
    this.slot,
    this.errorCode,
    this.message,
  });

  final CloneProfileCapability capability;
  final bool ok;
  final String? instanceId;
  final int? slot;
  final String? errorCode;
  final String? message;
}

abstract interface class CloneProfileClient {
  Future<CloneProfileCapability> getCapability();
  Future<CloneProfileAppList> listApps();
  Future<CloneProfileOperationResult> clone(String packageName);
  Future<CloneProfileOperationResult> launch(String instanceId);
  Future<CloneProfileOperationResult> stop(String instanceId);
  Future<CloneProfileOperationResult> uninstall(String instanceId);
}

class PlatformCloneProfileClient implements CloneProfileClient {
  PlatformCloneProfileClient({
    this.channel = const MethodChannel('private_vault/clone_profile'),
  });

  final MethodChannel channel;

  @override
  Future<CloneProfileCapability> getCapability() async => _capability(
    await channel.invokeMapMethod<String, Object?>('getCapability'),
  );

  @override
  Future<CloneProfileAppList> listApps() async {
    final value = await channel.invokeMapMethod<String, Object?>('listApps');
    final capability = _capability(value);
    if (!capability.ready) {
      return CloneProfileAppList(capability: capability, apps: const []);
    }
    final rawApps = value?['apps'];
    final apps = rawApps is List
        ? rawApps.map((raw) {
            final map = Map<Object?, Object?>.from(raw! as Map);
            final rawInstances = map['instances'];
            final instances = rawInstances is List
                ? rawInstances.map((rawInstance) {
                    final instance = Map<Object?, Object?>.from(rawInstance! as Map);
                    return CloneInstance(
                      instanceId: instance['instanceId']! as String,
                      slot: (instance['slot']! as num).toInt(),
                      state: (instance['state'] as String?) ?? 'unknown',
                    );
                  }).toList(growable: false)
                : const <CloneInstance>[];
            return CloneProfileApp(
              packageName: map['packageName']! as String,
              label: map['label']! as String,
              instances: instances,
              iconBytes: map['iconBytes'] as Uint8List?,
            );
          }).toList(growable: false)
        : const <CloneProfileApp>[];
    return CloneProfileAppList(capability: capability, apps: apps);
  }

  @override
  Future<CloneProfileOperationResult> clone(String packageName) =>
      _operation('clone', <String, Object?>{'packageName': packageName});

  @override
  Future<CloneProfileOperationResult> launch(String instanceId) =>
      _operation('launch', <String, Object?>{'instanceId': instanceId});

  @override
  Future<CloneProfileOperationResult> stop(String instanceId) =>
      _operation('stop', <String, Object?>{'instanceId': instanceId});

  @override
  Future<CloneProfileOperationResult> uninstall(String instanceId) =>
      _operation('uninstall', <String, Object?>{'instanceId': instanceId});

  Future<CloneProfileOperationResult> _operation(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final value = await channel.invokeMapMethod<String, Object?>(method, arguments);
    return CloneProfileOperationResult(
      capability: _capability(value),
      ok: value?['ok'] == true,
      instanceId: value?['instanceId'] as String?,
      slot: (value?['slot'] as num?)?.toInt(),
      errorCode: value?['errorCode'] as String?,
      message: value?['message'] as String?,
    );
  }

  CloneProfileCapability _capability(Map<String, Object?>? value) {
    final state = switch (value?['state']) {
      'ready' => CloneProfileCapabilityState.ready,
      'runner_missing' => CloneProfileCapabilityState.runnerMissing,
      'engine_unsupported' => CloneProfileCapabilityState.engineUnsupported,
      'unsupported_abi' => CloneProfileCapabilityState.unsupportedAbi,
      _ => CloneProfileCapabilityState.operationFailed,
    };
    return CloneProfileCapability(
      state: state,
      slotsAvailable: (value?['slotsAvailable'] as num?)?.toInt() ?? 0,
      slotsTotal: (value?['slotsTotal'] as num?)?.toInt() ?? 2,
      message: value?['message'] as String?,
    );
  }
}

class UnavailableCloneProfileClient implements CloneProfileClient {
  const UnavailableCloneProfileClient();

  CloneProfileCapability get _unsupported => const CloneProfileCapability(
    state: CloneProfileCapabilityState.engineUnsupported,
    slotsAvailable: 0,
    slotsTotal: 2,
    message: 'Virtual clone runners are unavailable on this platform.',
  );

  CloneProfileOperationResult get _failed =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);

  @override
  Future<CloneProfileCapability> getCapability() async => _unsupported;

  @override
  Future<CloneProfileAppList> listApps() async =>
      CloneProfileAppList(capability: _unsupported, apps: const []);

  @override
  Future<CloneProfileOperationResult> clone(String packageName) async => _failed;

  @override
  Future<CloneProfileOperationResult> launch(String instanceId) async => _failed;

  @override
  Future<CloneProfileOperationResult> stop(String instanceId) async => _failed;

  @override
  Future<CloneProfileOperationResult> uninstall(String instanceId) async => _failed;
}
