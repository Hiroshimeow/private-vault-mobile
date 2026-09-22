import 'dart:io';

import 'package:flutter/services.dart';

class PlatformMediaSourceBridge {
  const PlatformMediaSourceBridge({
    this.channel = const MethodChannel('private_vault/platform'),
  });

  final MethodChannel channel;

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
