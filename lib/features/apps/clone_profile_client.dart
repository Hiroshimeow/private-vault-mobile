import 'package:flutter/services.dart';

enum CloneProfileCapabilityState {
  ready,
  helperMissing,
  noFreeSlot,
  transformUnsupported,
  transformFailed,
  packageUnreadable,
  missingSplit,
  unsupportedSplitCode,
  unsupportedProvider,
  unsupportedService,
  unsupportedReceiver,
  unsupportedMultiprocess,
  unsupportedAbi,
  unsupportedNativePathBehavior,
  sourceSignerChanged,
  launchFailed,
  operationFailed,
}

class CloneProfileSlot {
  const CloneProfileSlot({required this.slot, required this.occupied, this.packageName});
  final int slot;
  final bool occupied;
  final String? packageName;
}

class CloneProfileCapability {
  const CloneProfileCapability({required this.state, this.message, this.slots = const []});
  final CloneProfileCapabilityState state;
  final String? message;
  final List<CloneProfileSlot> slots;
  bool get ready => state == CloneProfileCapabilityState.ready;
}

class CloneProfileApp {
  const CloneProfileApp({required this.packageName, required this.label, required this.slots});
  final String packageName;
  final String label;
  final List<int> slots;
}

class CloneProfileAppList {
  const CloneProfileAppList({required this.capability, required this.apps});
  final CloneProfileCapability capability;
  final List<CloneProfileApp> apps;
}

class CloneProfileOperationResult {
  const CloneProfileOperationResult({required this.capability, required this.ok});
  final CloneProfileCapability capability;
  final bool ok;
}

abstract interface class CloneProfileClient {
  Future<CloneProfileCapability> getCapability();
  Future<CloneProfileAppList> listApps();
  Future<CloneProfileOperationResult> clone(String packageName, int slot);
  Future<CloneProfileOperationResult> launch(String packageName, int slot);
  Future<CloneProfileOperationResult> uninstall(int slot);
}

class PlatformCloneProfileClient implements CloneProfileClient {
  PlatformCloneProfileClient({this.channel = const MethodChannel('private_vault/clone_profile')});
  final MethodChannel channel;

  @override
  Future<CloneProfileCapability> getCapability() async =>
      _capability(await channel.invokeMapMethod<String, Object?>('getCapability'));

  @override
  Future<CloneProfileAppList> listApps() async {
    final value = await channel.invokeMapMethod<String, Object?>('listApps');
    final capability = _capability(value);
    final rawApps = value?['apps'];
    final apps = capability.ready && rawApps is List
        ? rawApps.map((value) {
            final map = Map<Object?, Object?>.from(value! as Map);
            return CloneProfileApp(
              packageName: map['packageName']! as String,
              label: map['label']! as String,
              slots: (map['slots'] as List? ?? const [])
                  .map((value) => (value as num).toInt())
                  .toList(growable: false),
            );
          }).toList(growable: false)
        : const <CloneProfileApp>[];
    return CloneProfileAppList(capability: capability, apps: apps);
  }

  @override
  Future<CloneProfileOperationResult> clone(String packageName, int slot) =>
      _operation('clone', {'packageName': packageName, 'slot': slot});

  @override
  Future<CloneProfileOperationResult> launch(String packageName, int slot) =>
      _operation('launch', {'packageName': packageName, 'slot': slot});

  @override
  Future<CloneProfileOperationResult> uninstall(int slot) =>
      _operation('uninstall', {'slot': slot});

  Future<CloneProfileOperationResult> _operation(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final value = await channel.invokeMapMethod<String, Object?>(method, arguments);
    return CloneProfileOperationResult(
      capability: _capability(value),
      ok: value?['ok'] == true,
    );
  }

  CloneProfileCapability _capability(Map<String, Object?>? value) {
    final state = switch (value?['state']) {
      'ready' => CloneProfileCapabilityState.ready,
      'helper_missing' => CloneProfileCapabilityState.helperMissing,
      'no_free_slot' => CloneProfileCapabilityState.noFreeSlot,
      'transform_unsupported' => CloneProfileCapabilityState.transformUnsupported,
      'transform_failed' => CloneProfileCapabilityState.transformFailed,
      'package_unreadable' => CloneProfileCapabilityState.packageUnreadable,
      'missing_split' => CloneProfileCapabilityState.missingSplit,
      'unsupported_split_code' => CloneProfileCapabilityState.unsupportedSplitCode,
      'unsupported_provider' => CloneProfileCapabilityState.unsupportedProvider,
      'unsupported_service' => CloneProfileCapabilityState.unsupportedService,
      'unsupported_receiver' => CloneProfileCapabilityState.unsupportedReceiver,
      'unsupported_multiprocess' => CloneProfileCapabilityState.unsupportedMultiprocess,
      'unsupported_abi' => CloneProfileCapabilityState.unsupportedAbi,
      'unsupported_native_path_behavior' => CloneProfileCapabilityState.unsupportedNativePathBehavior,
      'source_signer_changed' => CloneProfileCapabilityState.sourceSignerChanged,
      'launch_failed' => CloneProfileCapabilityState.launchFailed,
      _ => CloneProfileCapabilityState.operationFailed,
    };
    final rawSlots = value?['slots'];
    final slots = rawSlots is List
        ? rawSlots.map((value) {
            final map = Map<Object?, Object?>.from(value! as Map);
            return CloneProfileSlot(
              slot: (map['slot'] as num).toInt(),
              occupied: map['occupied'] == true,
              packageName: map['packageName'] as String?,
            );
          }).toList(growable: false)
        : const <CloneProfileSlot>[];
    return CloneProfileCapability(
      state: state,
      message: value?['message'] as String?,
      slots: slots,
    );
  }
}

class UnavailableCloneProfileClient implements CloneProfileClient {
  const UnavailableCloneProfileClient();
  CloneProfileCapability get _unsupported => const CloneProfileCapability(
        state: CloneProfileCapabilityState.helperMissing,
        message: 'Plugin clone helpers are unavailable on this platform.',
      );

  @override
  Future<CloneProfileCapability> getCapability() async => _unsupported;
  @override
  Future<CloneProfileAppList> listApps() async =>
      CloneProfileAppList(capability: _unsupported, apps: const []);
  @override
  Future<CloneProfileOperationResult> clone(String packageName, int slot) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);
  @override
  Future<CloneProfileOperationResult> launch(String packageName, int slot) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);
  @override
  Future<CloneProfileOperationResult> uninstall(int slot) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);
}
