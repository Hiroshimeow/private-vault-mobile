import 'dart:io';
import 'dart:typed_data';

import 'package:private_vault_mobile/features/vault/vault_repository.dart';

typedef BrowserFetch = Future<Uint8List> Function(Uri uri);

class BrowserDownloadException implements Exception {
  const BrowserDownloadException(this.reason);

  final String reason;

  @override
  String toString() => 'BrowserDownloadException($reason)';
}

class BrowserDownloadService {
  factory BrowserDownloadService({
    required VaultRepository repository,
    required BrowserFetch fetch,
  }) => BrowserDownloadService._(repository, fetch);

  BrowserDownloadService._(this.repository, this._fetch);

  final VaultRepository repository;
  final BrowserFetch _fetch;

  Future<VaultItem> downloadToVault(Uri uri) async {
    if (uri.scheme.toLowerCase() != 'https') {
      throw const BrowserDownloadException(
        'Only HTTPS downloads are supported',
      );
    }
    final bytes = await _fetch(uri);
    return repository.addBytes(bytes, kind: VaultItemKind.document);
  }

  static Future<Uint8List> fetchDirectHttps(
    Uri uri, {
    int maxBytes = 25 * 1024 * 1024,
  }) async {
    if (uri.scheme.toLowerCase() != 'https') {
      throw const BrowserDownloadException(
        'Only HTTPS downloads are supported',
      );
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BrowserDownloadException(
          'Download failed with HTTP ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const BrowserDownloadException('Download exceeds size limit');
      }

      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response) {
        total += chunk.length;
        if (total > maxBytes) {
          throw const BrowserDownloadException('Download exceeds size limit');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on BrowserDownloadException {
      rethrow;
    } on Object {
      throw const BrowserDownloadException('Download failed');
    } finally {
      client.close(force: true);
    }
  }
}
