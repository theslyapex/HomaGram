import 'package:flutter_test/flutter_test.dart';
import 'package:homagram/features/home/data/story_service.dart';

void main() {
  group('Story media validation', () {
    test('accepts supported image MIME types', () {
      for (final mime in ['image/jpeg', 'image/png', 'image/webp']) {
        expect(
          isSupportedStoryMedia(mediaType: 'image', mimeType: mime),
          isTrue,
        );
      }
    });

    test('accepts supported video MIME types', () {
      for (final mime in ['video/mp4', 'video/quicktime']) {
        expect(
          isSupportedStoryMedia(mediaType: 'video', mimeType: mime),
          isTrue,
        );
      }
    });

    test('rejects mismatched and unsupported media types', () {
      expect(
        isSupportedStoryMedia(mediaType: 'image', mimeType: 'video/mp4'),
        isFalse,
      );
      expect(
        isSupportedStoryMedia(mediaType: 'video', mimeType: 'image/png'),
        isFalse,
      );
      expect(
        isSupportedStoryMedia(mediaType: 'audio', mimeType: 'audio/mpeg'),
        isFalse,
      );
      expect(
        isSupportedStoryMedia(mediaType: 'image', mimeType: 'image/svg+xml'),
        isFalse,
      );
    });
  });
}
