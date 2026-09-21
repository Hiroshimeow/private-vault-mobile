import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_vault_mobile/app/private_vault_app.dart';
import 'package:private_vault_mobile/app/private_vault_theme.dart';
import 'package:private_vault_mobile/features/auth/lock_controller.dart';
import 'package:private_vault_mobile/features/browser/browser_home.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _FakeWebViewPlatform extends WebViewPlatform {
  int controllerCreations = 0;
  final loadedHtml = <String>[];

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => _FakeCookieManager(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controllerCreations += 1;
    return _FakeController(params, loadedHtml);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeCookieManager extends PlatformWebViewCookieManager {
  _FakeCookieManager(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async => false;
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params, this.loadedHtml) : super.implementation();

  final List<String> loadedHtml;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml.add(html);
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearLocalStorage() async {}

  @override
  Future<String?> currentUrl() async => null;
}

class _FakeUnlockService implements UnlockService {
  @override
  Future<void> configure(String pin) async {}

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> verify(String candidate) async => true;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(key: Key('fake-webview'));
  }
}

void main() {
  late _FakeWebViewPlatform platform;

  setUp(() {
    platform = _FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('browser chrome exposes deterministic controls and status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivateVaultTheme.light(),
        home: const Scaffold(body: BrowserHome(clearOnClose: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Browser profile')), findsOneWidget);
    expect(find.byKey(const Key('browser-address')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('New ephemeral profile')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Download current HTTPS response to vault')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Go')), findsOneWidget);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('browser-address')),
      'http://insecure.example',
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Go')));
    await tester.pump();

    expect(find.text('Enter a valid HTTPS address.'), findsOneWidget);
  });

  testWidgets('app-owned start page follows light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivateVaultTheme.light(),
        home: const Scaffold(body: BrowserHome(clearOnClose: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.loadedHtml, hasLength(1));
    expect(platform.loadedHtml.single, contains('background:#f4f7f6'));
    expect(platform.loadedHtml.single, contains('color:#1a1c1c'));
  });

  testWidgets('app-owned start page follows dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PrivateVaultTheme.dark(),
        home: const Scaffold(body: BrowserHome(clearOnClose: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.loadedHtml, hasLength(1));
    expect(platform.loadedHtml.single, contains('background:#101718'));
    expect(platform.loadedHtml.single, contains('color:#e1e3e3'));

    await tester.tap(find.bySemanticsLabel(RegExp('New ephemeral profile')));
    await tester.pumpAndSettle();

    expect(platform.loadedHtml, hasLength(2));
    expect(platform.loadedHtml.last, contains('background:#101718'));
  });

  testWidgets('theme change does not reload an external page', (tester) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<Brightness>(
        valueListenable: brightness,
        builder: (context, value, child) => MaterialApp(
          theme: value == Brightness.light
              ? PrivateVaultTheme.light()
              : PrivateVaultTheme.dark(),
          home: const Scaffold(body: BrowserHome(clearOnClose: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.loadedHtml, hasLength(1));

    await tester.enterText(
      find.byKey(const Key('browser-address')),
      'https://example.com/retained',
    );
    await tester.tap(find.bySemanticsLabel(RegExp('Go')));
    await tester.pumpAndSettle();

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();

    expect(platform.controllerCreations, 1);
    expect(platform.loadedHtml, hasLength(1));
  });

  testWidgets('browser state and controller survive workspace tab switches', (
    tester,
  ) async {
    final lock = LockController()..unlock();
    await tester.pumpWidget(
      PrivateVaultApp(
        lockController: lock,
        unlockService: _FakeUnlockService(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Browser').last);
    await tester.pumpAndSettle();
    expect(platform.controllerCreations, 1);

    const address = 'https://example.com/retained';
    await tester.enterText(find.byKey(const Key('browser-address')), address);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser').last);
    await tester.pumpAndSettle();

    expect(platform.controllerCreations, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browser-address')))
          .controller
          ?.text,
      address,
    );
  });
}
