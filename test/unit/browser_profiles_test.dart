import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/features/browser/browser_profiles.dart';

void main() {
  test('switching ephemeral profiles clears shared web data first', () async {
    var cookiesCleared = 0;
    var cacheCleared = 0;
    final profiles = EphemeralBrowserProfiles(
      clearCookies: () async => cookiesCleared++,
      clearCache: () async => cacheCleared++,
      clearOnClose: true,
    );

    final second = profiles.addProfile();
    await profiles.switchTo(second.id);

    expect(profiles.active.id, second.id);
    expect(cookiesCleared, 1);
    expect(cacheCleared, 1);
  });

  test('clear on close is configurable', () async {
    var clears = 0;
    final profiles = EphemeralBrowserProfiles(
      clearCookies: () async => clears++,
      clearCache: () async => clears++,
      clearOnClose: false,
    );

    await profiles.close();
    expect(clears, 0);

    profiles.clearOnClose = true;
    await profiles.close();
    expect(clears, 2);
  });

  test('logical profiles have distinct opaque ids', () {
    final profiles = EphemeralBrowserProfiles(
      clearCookies: () async {},
      clearCache: () async {},
      clearOnClose: true,
    );

    final a = profiles.active;
    final b = profiles.addProfile();

    expect(a.id, isNot(b.id));
    expect(profiles.items, hasLength(2));
  });
}
