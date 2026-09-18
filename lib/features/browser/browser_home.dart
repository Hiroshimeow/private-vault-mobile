import 'dart:async';

import 'package:flutter/material.dart';
import 'package:private_vault_mobile/features/browser/browser_download_service.dart';
import 'package:private_vault_mobile/features/browser/browser_profiles.dart';
import 'package:private_vault_mobile/features/vault/vault_repository.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrowserHome extends StatefulWidget {
  const BrowserHome({super.key, required this.clearOnClose, this.repository});

  final bool clearOnClose;
  final VaultRepository? repository;

  @override
  State<BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends State<BrowserHome> {
  late final WebViewController _controller;
  late final WebViewCookieManager _cookieManager;
  late final EphemeralBrowserProfiles _profiles;
  late final BrowserDownloadService? _downloads;
  final _address = TextEditingController();
  String? _message;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _cookieManager = WebViewCookieManager();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              if (url.startsWith('https://')) _address.text = url;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              if (url.startsWith('https://')) _address.text = url;
            });
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _message = 'Page could not be loaded.';
            });
          },
        ),
      )
      ..loadHtmlString(_startPage);

    _profiles = EphemeralBrowserProfiles(
      clearCookies: _cookieManager.clearCookies,
      clearCache: () async {
        await _controller.clearCache();
        await _controller.clearLocalStorage();
      },
      clearOnClose: widget.clearOnClose,
    );
    _downloads = widget.repository == null
        ? null
        : BrowserDownloadService(
            repository: widget.repository!,
            fetch: BrowserDownloadService.fetchDirectHttps,
          );
  }

  @override
  void didUpdateWidget(covariant BrowserHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _profiles.clearOnClose = widget.clearOnClose;
  }

  @override
  void dispose() {
    unawaited(_profiles.close());
    _address.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    final uri = _normalizedAddress(_address.text);
    if (uri == null) {
      setState(() => _message = 'Enter a valid HTTPS address.');
      return;
    }
    setState(() => _message = null);
    await _controller.loadRequest(uri);
  }

  Future<void> _switchProfile(String id) async {
    setState(() => _loading = true);
    try {
      await _profiles.switchTo(id);
      await _controller.loadHtmlString(_startPage);
      _address.clear();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Profile switched. Shared WebView cookies, cache, and local storage were cleared.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Profile switch failed.';
      });
    }
  }

  Future<void> _downloadCurrentAddress() async {
    final downloads = _downloads;
    if (downloads == null) {
      setState(() => _message = 'Protected storage is unavailable.');
      return;
    }

    final current = await _controller.currentUrl();
    final uri = _normalizedAddress(
      current != null && current.startsWith('https://')
          ? current
          : _address.text,
    );
    if (uri == null) {
      setState(() => _message = 'Only direct HTTPS downloads are supported.');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await downloads.downloadToVault(uri);
      if (!mounted) return;
      setState(
        () => _message = 'Downloaded response saved to the encrypted vault.',
      );
    } on BrowserDownloadException {
      if (!mounted) return;
      setState(
        () => _message = 'Download failed. Authenticated WebView downloads are not supported in V1.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Uri? _normalizedAddress(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    final items = _profiles.items;
    final active = _profiles.active;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    DropdownButton<String>(
                      value: active.id,
                      items: [
                        for (final profile in items)
                          DropdownMenuItem(
                            value: profile.id,
                            child: Text(profile.label),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) unawaited(_switchProfile(id));
                      },
                    ),
                    IconButton(
                      tooltip: 'New ephemeral profile',
                      onPressed: () {
                        final profile = _profiles.addProfile();
                        setState(() {});
                        unawaited(_switchProfile(profile.id));
                      },
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Download current HTTPS response to vault',
                      onPressed: _loading ? null : _downloadCurrentAddress,
                      icon: const Icon(Icons.download_outlined),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('browser-address'),
                        controller: _address,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _navigate(),
                        decoration: const InputDecoration(
                          hintText: 'https://example.com',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Go',
                      onPressed: _loading ? null : _navigate,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _message!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _controller)),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Text(
            'Ephemeral profiles are sequential: switching clears the shared platform WebView store. '
            'They are not simultaneous retained identities and do not provide anonymity.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  static const _startPage = '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 2.5rem; color: #d8dde8; background:#111722; }
h2 { font-weight: 600; }
p { line-height: 1.45; color:#aeb8c9; }
</style>
</head>
<body>
<h2>Private browser</h2>
<p>Enter an HTTPS address above. Profiles are ephemeral and cleared when switched.</p>
</body>
</html>
''';
}
