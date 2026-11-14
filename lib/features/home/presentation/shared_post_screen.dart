import 'package:flutter/material.dart';
import '../../auth/data/auth_service.dart';
import 'feed_screen.dart';

class SharedPostScreen extends StatefulWidget {
  const SharedPostScreen({required this.postId, super.key});
  final String postId;
  @override
  State<SharedPostScreen> createState() => _SharedPostScreenState();
}

class _SharedPostScreenState extends State<SharedPostScreen> {
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
    appBar: AppBar(title: const Text('پست در HomaGram')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _post,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('این پست در دسترس نیست؛ ممکن است حذف شده باشد یا حساب منتشرکننده خصوصی باشد.',
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
