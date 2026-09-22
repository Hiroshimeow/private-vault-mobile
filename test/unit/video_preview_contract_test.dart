import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protected video preview uses app-private temp and purges on lock', () {
    final media = File('lib/features/media/media_vault_service.dart')
        .readAsStringSync();
    final vault = File('lib/features/vault/vault_home.dart').readAsStringSync();
    final app = File('lib/app/private_vault_app.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('video_player:'));
    expect(media, contains("getTemporaryDirectory()"));
    expect(media, contains("private-vault-preview"));
    expect(media, contains('purgePreviewPlaintext'));
    expect(vault, contains('VideoPlayerController.file'));
    expect(vault, contains("Key('vault-video-play-pause')"));
    expect(app, contains('unawaited(media.purgePreviewPlaintext())'));
    expect(main, contains('await media.purgePreviewPlaintext()'));
  });
}
