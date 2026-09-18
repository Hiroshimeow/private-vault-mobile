import 'package:flutter/foundation.dart';

class LockController extends ChangeNotifier {
  LockController({this.backgroundLock = true});

  final bool backgroundLock;
  bool _isLocked = true;

  bool get isLocked => _isLocked;

  void unlock() {
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }

  void lock() {
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  void panic() => lock();

  void onBackground() {
    if (backgroundLock) lock();
  }
}
