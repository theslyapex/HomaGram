import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Uses a stable private-storage path as the in-memory cache key instead of
/// the short-lived signed URL returned by Supabase.
class StoryImageProvider extends ImageProvider<StoryImageProvider> {
  StoryImageProvider(
    this.url, {
    required this.cacheKey,
    this.scale = 1.0,
    this.headers,
  });

  final String url;
  final String cacheKey;
  final double scale;
  final Map<String, String>? headers;

  @override
  Future<StoryImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StoryImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    StoryImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final networkImage = NetworkImage(
      url,
      scale: scale,
      headers: headers,
    );
    return networkImage.loadImage(networkImage, decode);
  }

  @override
  bool operator ==(Object other) =>
      other is StoryImageProvider &&
      other.cacheKey == cacheKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(cacheKey, scale);
}
