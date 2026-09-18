import 'dart:async';

import 'package:flutter/foundation.dart';

class LockController extends ChangeNotifier {
  LockController({this.backgroundLock = true});

  final bool backgroundLock;
  bool _isLocked = true;
  Timer? _backgroundTimer;

  bool get isLocked => _isLocked;

  void unlock() {
    _backgroundTimer?.cancel();
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }

  void lock() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  void panic() => lock();

  void onBackground({Duration delay = Duration.zero}) {
    if (!backgroundLock || _isLocked) return;
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
