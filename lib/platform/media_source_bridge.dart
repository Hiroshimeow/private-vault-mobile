import 'dart:io';

import 'package:flutter/services.dart';

class PlatformMediaSourceBridge {
  const PlatformMediaSourceBridge({
    this.channel = const MethodChannel('private_vault/platform'),
  });

  final MethodChannel channel;

  Stream<List<int>> openRead(Uri uri) async* {
    if (!Platform.isAndroid || uri.scheme != 'content') {
      throw UnsupportedError('Source URI cannot be streamed on this platform');
    }
    final token = await channel.invokeMethod<String>('openDocumentStream', {
      'uri': uri.toString(),
    });
    if (token == null || token.isEmpty) {
      throw StateError('Android did not open the selected source');
    }
    try {
      while (true) {
        final chunk = await channel.invokeMethod<Uint8List>(
          'readDocumentStream',
          {'token': token, 'maxBytes': 64 * 1024},
        );
        if (chunk == null) break;
        if (chunk.isNotEmpty) yield chunk;
      }
    } finally {
      try {
        await channel.invokeMethod<void>('closeDocumentStream', {
          'token': token,
        });
      } on PlatformException {
        // Best effort: the native side also closes streams at EOF/engine cleanup.
      }
    }
  }

  Future<Uint8List?> videoThumbnail(Uri uri) async {
    if (!Platform.isAndroid) return null;
    if (uri.scheme != 'content' && uri.scheme != 'file') return null;
    try {
      return await channel.invokeMethod<Uint8List>('videoThumbnail', {
        'uri': uri.toString(),
      });
    } on PlatformException {
      return null;
    }
  }

  Future<void> delete(Uri uri) async {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    if (Platform.isAndroid && uri.scheme == 'content') {
      final deleted =
          await channel.invokeMethod<bool>('deleteDocumentUri', {
            'uri': uri.toString(),
          }) ??
          false;
      if (!deleted) {
        throw const MediaSourceDeleteException();
      }
      return;
    }

    throw UnsupportedError('Source URI cannot be deleted on this platform');
  }
}

class MediaSourceDeleteException implements Exception {
  const MediaSourceDeleteException();
}
