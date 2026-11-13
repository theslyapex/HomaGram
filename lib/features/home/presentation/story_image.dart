import 'package:flutter/painting.dart';

/// Uses a stable private-storage path as the in-memory cache key instead of
/// the short-lived signed URL returned by Supabase.
class StoryImageProvider extends NetworkImage {
  StoryImageProvider(
    super.url, {
    required this.cacheKey,
  });

  final String cacheKey;

  @override
  bool operator ==(Object other) =>
      other is StoryImageProvider &&
      other.cacheKey == cacheKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(cacheKey, scale);
}
