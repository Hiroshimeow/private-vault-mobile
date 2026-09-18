import 'dart:math';

class BrowserProfile {
  const BrowserProfile({required this.id, required this.label});

  final String id;
  final String label;
}

typedef ClearWebData = Future<void> Function();

class EphemeralBrowserProfiles {
  factory EphemeralBrowserProfiles({
    required ClearWebData clearCookies,
    required ClearWebData clearCache,
    required bool clearOnClose,
  }) => EphemeralBrowserProfiles._(clearCookies, clearCache, clearOnClose, [
    BrowserProfile(id: _newId(), label: 'Profile 1'),
  ]);

  EphemeralBrowserProfiles._(
    this._clearCookies,
    this._clearCache,
    this.clearOnClose,
    this._items,
  );

  final ClearWebData _clearCookies;
  final ClearWebData _clearCache;
  final List<BrowserProfile> _items;
  bool clearOnClose;
  late BrowserProfile _active = _items.first;

  List<BrowserProfile> get items => List.unmodifiable(_items);
  BrowserProfile get active => _active;

  BrowserProfile addProfile() {
    final profile = BrowserProfile(
      id: _newId(),
      label: 'Profile ${_items.length + 1}',
    );
    _items.add(profile);
    return profile;
  }

  Future<void> switchTo(String id) async {
    final target = _items.where((profile) => profile.id == id).firstOrNull;
    if (target == null) throw ArgumentError.value(id, 'id');
    if (target.id == _active.id) return;

    await _clearSharedWebData();
    _active = target;
  }

  Future<void> close() async {
    if (clearOnClose) {
      await _clearSharedWebData();
    }
  }

  Future<void> _clearSharedWebData() async {
    await _clearCookies();
    await _clearCache();
  }

  static String _newId() {
    final random = Random.secure();
    return List<int>.generate(
      10,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final value in this) {
      return value;
    }
    return null;
  }
}
