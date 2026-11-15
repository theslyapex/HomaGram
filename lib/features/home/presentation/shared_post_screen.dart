import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_service.dart';
import 'feed_screen.dart';

class SharedPostScreen extends StatefulWidget {
  const SharedPostScreen({required this.postId, super.key});
  final String postId;
  @override
  State<SharedPostScreen> createState() => _SharedPostScreenState();
}

class _SharedPostScreenState extends State<SharedPostScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  late Future<Map<String, dynamic>> _post;
  @override
  void initState() { super.initState(); _post = _load(); }

  Future<Map<String, dynamic>> _load() async {
    final client = AuthService.client;
    final row = await client.from('posts')
      .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at')
      .eq('id', widget.postId).single();
    final post = Map<String, dynamic>.from(row);
    final profile = await client.from('profiles').select('avatar_path')
      .eq('id', post['author_id']).maybeSingle();
    final avatar = profile?['avatar_path'] as String?;
    if (avatar != null) {
      try { post['author_avatar_url'] = await client.storage.from('avatars').createSignedUrl(avatar, 3600); } catch (_) {}
    }
    final path = post['media_path'] as String?;
    if (path != null) {
      post['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600);
    }
    final coverPath = post['cover_path'] as String?;
    if (coverPath != null) {
      try { post['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600); } catch (_) {}
    }
    return post;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t.sharedPostTitle)),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _post,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(_t.sharedPostUnavailable,
              textAlign: TextAlign.center),
          ));
        }
        return ListView(padding: const EdgeInsets.all(14), children: [
          PostCard(post: snapshot.data!),
        ]);
      },
    ),
  );
}


class SharedPostMessagePreview extends StatelessWidget {
  const SharedPostMessagePreview({required this.postId, super.key});
  final String postId;

  Future<Map<String,dynamic>> _load() async {
    final client = AuthService.client;
    final row = await client.from('posts')
      .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path')
      .eq('id', postId).single();
    final post = Map<String,dynamic>.from(row);
    final path = (post['media_type'] == 'video' ? post['cover_path'] : post['media_path']) as String?
      ?? post['media_path'] as String?;
    if (path != null && path.isNotEmpty) {
      try { post['preview_url'] = await client.storage.from('post-media').createSignedUrl(path, 1800); } catch (_) {}
    }
    return post;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String,dynamic>>(
    future: _load(),
    builder: (context, snapshot) {
      final colors = Theme.of(context).colorScheme;
      if (snapshot.connectionState != ConnectionState.done) {
        return Container(width: 250, height: 84, alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Container(width: 250, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: const Text('پست اشتراک‌گذاری‌شده در دسترس نیست'));
      }
      final post = snapshot.data!;
      final url = post['preview_url'] as String?;
      final caption = (post['caption'] as String? ?? '').trim();
      final author = (post['author_display_name'] as String? ?? post['author_username'] as String? ?? 'HomaGram').trim();
      return Container(width: 260, clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (url != null) AspectRatio(aspectRatio: 1.35,
            child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: colors.surfaceContainer, child: const Icon(Icons.image_not_supported_outlined)))),
          Padding(padding: const EdgeInsets.fromLTRB(11, 9, 11, 11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(post['media_type'] == 'video' ? Icons.play_circle_outline : Icons.article_outlined,
              size: 16, color: colors.primary), const SizedBox(width: 5),
              Expanded(child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))]),
            if (caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
              child: Text(caption, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.35))),
            const SizedBox(height: 5),
            Text('مشاهدهٔ پست در هماگرام', style: TextStyle(color: colors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
        ]));
    },
  );
}

class SharedProfileMessagePreview extends StatelessWidget {
  const SharedProfileMessagePreview({required this.userId, super.key});
  final String userId;

  Future<Map<String,dynamic>> _load() async {
    final client = AuthService.client;
    final profile = await client.from('profiles')
      .select('id,username,display_name,bio,avatar_path').eq('id', userId).single();
    final result = Map<String,dynamic>.from(profile);
    final path = result['avatar_path'] as String?;
    if (path != null && path.isNotEmpty) {
      try { result['avatar_url'] = await client.storage.from('avatars').createSignedUrl(path, 1800); } catch (_) {}
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String,dynamic>>(
    future: _load(),
    builder: (context, snapshot) {
      final colors = Theme.of(context).colorScheme;
      if (snapshot.connectionState != ConnectionState.done) {
        return Container(width: 250, height: 76, alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Container(width: 250, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
          child: const Text('پروفایل اشتراک‌گذاری‌شده در دسترس نیست'));
      }
      final p = snapshot.data!;
      final url = p['avatar_url'] as String?;
      final username = p['username'] as String? ?? '';
      final name = (p['display_name'] as String? ?? '').trim();
      return Container(width: 250, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          CircleAvatar(radius: 27, backgroundImage: url == null ? null : NetworkImage(url),
            child: url == null ? const Icon(Icons.person_outline_rounded) : null),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name.isEmpty ? '@$username' : name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('@$username', textDirection: TextDirection.ltr,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
            const SizedBox(height: 4),
            Text('مشاهدهٔ پروفایل', style: TextStyle(color: colors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
        ]));
    },
  );
}
