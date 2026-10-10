import 'package:flutter/services.dart';

class StandaloneCloneEnvironment {
  const StandaloneCloneEnvironment({
    required this.route,
    required this.sdkInt,
    required this.canRequestPackageInstalls,
    required this.maxSourceBytes,
  });

  final String route;
  final int sdkInt;
  final bool canRequestPackageInstalls;
  final int maxSourceBytes;
}

class StandaloneCloneRecord {
  const StandaloneCloneRecord({
    required this.cloneId,
    required this.sourcePackage,
    required this.clonePackage,
    required this.versionCode,
    required this.versionName,
    required this.installStatus,
    this.compatibilityWarnings = const <String>[],
  });

  final String cloneId;
  final String sourcePackage;
  final String clonePackage;
  final int? versionCode;
  final String? versionName;
  final String installStatus;
  final List<String> compatibilityWarnings;
}

class StandaloneCloneBuildResult {
  const StandaloneCloneBuildResult({
    required this.status,
    required this.supported,
    required this.blockers,
    required this.warnings,
    this.clone,
    this.errorCode,
    this.error,
  });

  final String status;
  final bool supported;
  final List<String> blockers;
  final List<String> warnings;
  final StandaloneCloneRecord? clone;
  final String? errorCode;
  final String? error;
}

abstract interface class StandaloneCloneClient {
  Future<StandaloneCloneEnvironment> getEnvironment();
  Future<StandaloneCloneBuildResult> pickAndBuildClone();
  Future<List<StandaloneCloneRecord>> listClones();
  Future<String> installClone(String cloneId);
  Future<String> launchClone(String cloneId);
  Future<String> removeClone(String cloneId);
}

class PlatformStandaloneCloneClient implements StandaloneCloneClient {
  PlatformStandaloneCloneClient({
    this.channel = const MethodChannel('private_vault/standalone_clone'),
  });

  final MethodChannel channel;

  @override
  Future<StandaloneCloneEnvironment> getEnvironment() async {
    final value = await channel.invokeMapMethod<String, Object?>(
      'getEnvironment',
    );
    return StandaloneCloneEnvironment(
      route: value?['route'] as String? ?? 'standalone_repackage',
      sdkInt: (value?['sdkInt'] as num?)?.toInt() ?? 0,
      canRequestPackageInstalls: value?['canRequestPackageInstalls'] == true,
      maxSourceBytes: (value?['maxSourceBytes'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<StandaloneCloneBuildResult> pickAndBuildClone() async {
    final value = await channel.invokeMapMethod<String, Object?>(
      'pickAndBuildClone',
    );
    return _buildResult(value);
  }

  @override
  Future<List<StandaloneCloneRecord>> listClones() async {
    final raw = await channel.invokeListMethod<Object?>('listClones');
    return (raw ?? const <Object?>[])
        .whereType<Map>()
        .map((value) => _record(Map<Object?, Object?>.from(value)))
        .toList(growable: false);
  }

  @override
  Future<String> installClone(String cloneId) =>
      _operation('installClone', cloneId);

  @override
  Future<String> launchClone(String cloneId) =>
      _operation('launchClone', cloneId);

  @override
  Future<String> removeClone(String cloneId) =>
      _operation('removeClone', cloneId);

  Future<String> _operation(String method, String cloneId) async {
    final value = await channel.invokeMapMethod<String, Object?>(method, {
      'cloneId': cloneId,
    });
    return value?['status'] as String? ?? 'failed';
  }

  StandaloneCloneBuildResult _buildResult(Map<String, Object?>? value) {
    final rawClone = value?['clone'];
    return StandaloneCloneBuildResult(
      status: value?['status'] as String? ?? 'failed',
      supported: value?['supported'] == true,
      blockers: _stringList(value?['blockers']),
      warnings: _stringList(value?['warnings']),
      clone: rawClone is Map
          ? _record(Map<Object?, Object?>.from(rawClone))
          : null,
      errorCode: value?['errorCode'] as String?,
      error: value?['error'] as String?,
    );
  }

  StandaloneCloneRecord _record(Map<Object?, Object?> value) =>
      StandaloneCloneRecord(
        cloneId: value['cloneId']! as String,
        sourcePackage: value['sourcePackage']! as String,
        clonePackage: value['clonePackage']! as String,
        versionCode: (value['versionCode'] as num?)?.toInt(),
        versionName: value['versionName'] as String?,
        installStatus: value['installStatus'] as String? ?? 'unknown',
        compatibilityWarnings: _stringList(value['compatibilityWarnings']),
      );

  List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];
}

class UnavailableStandaloneCloneClient implements StandaloneCloneClient {
  const UnavailableStandaloneCloneClient();

  @override
  Future<StandaloneCloneEnvironment> getEnvironment() async =>
      const StandaloneCloneEnvironment(
        route: 'unavailable',
        sdkInt: 0,
        canRequestPackageInstalls: false,
        maxSourceBytes: 0,
      );

  @override
  Future<StandaloneCloneBuildResult> pickAndBuildClone() async =>
      const StandaloneCloneBuildResult(
        status: 'unsupported_platform',
        supported: false,
        blockers: <String>['android_only'],
        warnings: <String>[],
      );

  @override
  Future<List<StandaloneCloneRecord>> listClones() async => const [];

  @override
  Future<String> installClone(String cloneId) async => 'unsupported_platform';

  @override
  Future<String> launchClone(String cloneId) async => 'unsupported_platform';

  @override
  Future<String> removeClone(String cloneId) async => 'unsupported_platform';
}
