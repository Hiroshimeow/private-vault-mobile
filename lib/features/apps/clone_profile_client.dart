import 'package:flutter/services.dart';

enum CloneProfileCapabilityState {
  ready,
  privilegeRequired,
  cloneProfileUnsupportedByOem,
  conflictingExternalCloneProfile,
  operationFailed,
}

class CloneProfileCapability {
  const CloneProfileCapability({
    required this.state,
    this.userId,
    this.message,
  });

  final CloneProfileCapabilityState state;
  final int? userId;
  final String? message;

  bool get ready => state == CloneProfileCapabilityState.ready;
}

class CloneProfileApp {
  const CloneProfileApp({
    required this.packageName,
    required this.label,
    required this.cloned,
    this.iconBytes,
  });

  final String packageName;
  final String label;
  final bool cloned;
  final Uint8List? iconBytes;
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
  });

  final CloneProfileCapability capability;
  final bool ok;
}

abstract interface class CloneProfileClient {
  Future<CloneProfileCapability> getCapability();
  Future<bool> requestPrivilege();
  Future<CloneProfileAppList> listApps();
  Future<CloneProfileOperationResult> clone(String packageName);
  Future<CloneProfileOperationResult> launch(String packageName);
  Future<CloneProfileOperationResult> uninstall(String packageName);
}

class PlatformCloneProfileClient implements CloneProfileClient {
  PlatformCloneProfileClient({
    this.channel = const MethodChannel('private_vault/clone_profile'),
  });

  final MethodChannel channel;

  @override
  Future<CloneProfileCapability> getCapability() async {
    try {
      return _capability(
        await channel.invokeMapMethod<String, Object?>('getCapability'),
      );
    } on PlatformException catch (error) {
      return _platformFailure(error);
    } on MissingPluginException catch (error) {
      return _platformFailure(error);
    }
  }

  @override
  Future<bool> requestPrivilege() async {
    try {
      return await channel.invokeMethod<bool>('requestPrivilege') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<CloneProfileAppList> listApps() async {
    Map<String, Object?>? value;
    try {
      value = await channel.invokeMapMethod<String, Object?>('listApps');
    } on PlatformException catch (error) {
      return CloneProfileAppList(
        capability: _platformFailure(error),
        apps: const [],
      );
    } on MissingPluginException catch (error) {
      return CloneProfileAppList(
        capability: _platformFailure(error),
        apps: const [],
      );
    }
    final capability = _capability(value);
    if (!capability.ready) {
      return CloneProfileAppList(capability: capability, apps: const []);
    }
    final rawApps = value?['apps'];
    final apps = rawApps is List
        ? rawApps
              .map((value) {
                final map = Map<Object?, Object?>.from(value! as Map);
                return CloneProfileApp(
                  packageName: map['packageName']! as String,
                  label: map['label']! as String,
                  cloned: map['cloned'] == true,
                  iconBytes: map['iconBytes'] as Uint8List?,
                );
              })
              .toList(growable: false)
        : const <CloneProfileApp>[];
    return CloneProfileAppList(capability: capability, apps: apps);
  }

  @override
  Future<CloneProfileOperationResult> clone(String packageName) =>
      _operation('clone', packageName);

  @override
  Future<CloneProfileOperationResult> launch(String packageName) =>
      _operation('launch', packageName);

  @override
  Future<CloneProfileOperationResult> uninstall(String packageName) =>
      _operation('uninstall', packageName);

  Future<CloneProfileOperationResult> _operation(
    String method,
    String packageName,
  ) async {
    try {
      final value = await channel.invokeMapMethod<String, Object?>(method, {
        'packageName': packageName,
      });
      return CloneProfileOperationResult(
        capability: _capability(value),
        ok: value?['ok'] == true,
      );
    } on PlatformException catch (error) {
      return CloneProfileOperationResult(
        capability: _platformFailure(error),
        ok: false,
      );
    } on MissingPluginException catch (error) {
      return CloneProfileOperationResult(
        capability: _platformFailure(error),
        ok: false,
      );
    }
  }

  CloneProfileCapability _platformFailure(Object error) =>
      CloneProfileCapability(
        state: CloneProfileCapabilityState.operationFailed,
        message: error is PlatformException
            ? error.message ?? 'Clone platform operation failed.'
            : 'Clone platform operation is unavailable.',
      );

  CloneProfileCapability _capability(Map<String, Object?>? value) {
    final raw = value?['state'];
    final state = switch (raw) {
      'ready' => CloneProfileCapabilityState.ready,
      'privilege_required' => CloneProfileCapabilityState.privilegeRequired,
      'clone_profile_unsupported_by_oem' =>
        CloneProfileCapabilityState.cloneProfileUnsupportedByOem,
      'conflicting_external_clone_profile' =>
        CloneProfileCapabilityState.conflictingExternalCloneProfile,
      _ => CloneProfileCapabilityState.operationFailed,
    };
    return CloneProfileCapability(
      state: state,
      userId: (value?['userId'] as num?)?.toInt(),
      message: value?['message'] as String?,
    );
  }
}

class UnavailableCloneProfileClient implements CloneProfileClient {
  const UnavailableCloneProfileClient();

  CloneProfileCapability get _unsupported => const CloneProfileCapability(
    state: CloneProfileCapabilityState.cloneProfileUnsupportedByOem,
    message: 'Real Android clone profiles are unavailable on this platform.',
  );

  @override
  Future<CloneProfileCapability> getCapability() async => _unsupported;

  @override
  Future<bool> requestPrivilege() async => false;

  @override
  Future<CloneProfileAppList> listApps() async =>
      CloneProfileAppList(capability: _unsupported, apps: const []);

  @override
  Future<CloneProfileOperationResult> clone(String packageName) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);

  @override
  Future<CloneProfileOperationResult> launch(String packageName) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);

  @override
  Future<CloneProfileOperationResult> uninstall(String packageName) async =>
      CloneProfileOperationResult(capability: _unsupported, ok: false);
}
