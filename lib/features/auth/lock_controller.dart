import 'dart:async';

import 'package:flutter/foundation.dart';

class LockController extends ChangeNotifier {
  LockController({this.backgroundLock = true});

  final bool backgroundLock;
  bool _isLocked = true;
  int _unlockGeneration = 0;
  Timer? _backgroundTimer;
  VoidCallback? _confidentialityBoundary;

  bool get isLocked => _isLocked;
  int get unlockGeneration => _unlockGeneration;

  void attachConfidentialityBoundary(VoidCallback callback) {
    if (_confidentialityBoundary != null &&
        !identical(_confidentialityBoundary, callback)) {
      throw StateError('A confidentiality boundary is already attached.');
    }
    _confidentialityBoundary = callback;
  }

  void detachConfidentialityBoundary(VoidCallback callback) {
    if (identical(_confidentialityBoundary, callback)) {
      _confidentialityBoundary = null;
    }
  }

  void unlock() {
    _backgroundTimer?.cancel();
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }

  void lock() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _unlockGeneration += 1;
    if (_isLocked) return;
    _confidentialityBoundary?.call();
    _isLocked = true;
    notifyListeners();
  }

  void panic() => lock();

  void onBackground({Duration delay = Duration.zero}) {
    if (!backgroundLock) {
      _unlockGeneration += 1;
      return;
    }
    if (_isLocked) {
      _unlockGeneration += 1;
      return;
    }
    _backgroundTimer?.cancel();
    if (delay <= Duration.zero) {
      lock();
      return;
    }
    _backgroundTimer = Timer(delay, lock);
  }

  void onForeground() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  @override
  void dispose() {
    _backgroundTimer?.cancel();
    super.dispose();
  }
}
