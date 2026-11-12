import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Map<String, dynamic>>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = _loadPosts();
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    final rows = await AuthService.client
        .from('posts')
        .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,created_at')
        .order('created_at', ascending: false)
        .limit(50);
    final result = <Map<String, dynamic>>[];
    for (final item in rows) {
      final post = Map<String, dynamic>.from(item);
      final path = post['media_path'] as String?;
      if (path != null) {
        try {
          post['media_url'] = await AuthService.client.storage
              .from('post-media')
              .createSignedUrl(path, 3600);
        } catch (_) {
          post['media_unavailable'] = true;
        }
      }
      result.add(post);
    }
    return result;
  }

  Future<void> _refresh() async {
    final next = _loadPosts();
    setState(() => _posts = next);
    await next;
  }

  Future<void> _createPost() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreatePostScreen()),
    );
    if (published == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: InkWell(
          onTap: _createPost,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0x223FD6D0),
                  child: Icon(Icons.person_outline, color: HomaGramTheme.turquoise),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('چیزی برای گفتن دارید؟', style: TextStyle(color: Color(0xFF8490A4))),
                ),
                IconButton(
                  tooltip: 'ایجاد پست',
                  onPressed: _createPost,
                  icon: const Icon(Icons.add_circle_rounded, color: HomaGramTheme.turquoise, size: 29),
                ),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _posts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _stateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'فید بارگذاری نشد',
                message: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
                action: TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
              );
            }
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 60, 28, 30),
                  children: [
                    const Icon(Icons.dynamic_feed_outlined, size: 62, color: HomaGramTheme.turquoise),
                    const SizedBox(height: 18),
                    const Text('هنوز پستی منتشر نشده', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('اولین پست HomaGram را منتشر کنید و فید را شکل دهید.',
                        textAlign: TextAlign.center, style: TextStyle(height: 1.8, color: Color(0xFF7A879B))),
                    const SizedBox(height: 14),
                    Center(child: FilledButton.icon(onPressed: _createPost,
                        icon: const Icon(Icons.add), label: const Text('ایجاد اولین پست'))),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _PostCard(post: posts[index]),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _stateMessage({required IconData icon, required String title, required String message, Widget? action}) =>
      Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: HomaGramTheme.turquoise),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.8, color: Color(0xFF7A879B))),
          if (action != null) action,
        ]),
      ));
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final caption = (post['caption'] as String? ?? '').trim();
    final mediaUrl = post['media_url'] as String?;
    final mediaType = post['media_type'] as String?;
    final date = DateTime.tryParse(post['created_at'] as String? ?? '')?.toLocal();
    final dateText = date == null ? '' : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
            child: Row(children: [
              const CircleAvatar(
                radius: 21,
                backgroundColor: Color(0x223FD6D0),
                child: Icon(Icons.person_outline_rounded, color: HomaGramTheme.turquoise),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post['author_display_name'] as String? ?? 'کاربر HomaGram',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text('@${post['author_username'] ?? 'user'} • $dateText',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
              ])),
              const Icon(Icons.more_horiz_rounded, color: Color(0xFF8490A4)),
            ]),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(caption, style: const TextStyle(height: 1.85, fontSize: 13)),
            ),
          if (mediaUrl != null)
            if (mediaType == 'video')
              _FeedVideo(url: mediaUrl)
            else
              Image.network(mediaUrl, fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (_, __, ___) => const _MediaError()),
          if (post['media_unavailable'] == true) const _MediaError(),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 12),
            child: Row(children: [
              const Icon(Icons.favorite_border_rounded, size: 21, color: Color(0xFF8792A5)),
              const SizedBox(width: 6),
              const Text('پسندیدن', style: TextStyle(fontSize: 11, color: Color(0xFF8792A5))),
              const Spacer(),
              const Icon(Icons.chat_bubble_outline_rounded, size: 19, color: Color(0xFF8792A5)),
              const SizedBox(width: 6),
              const Text('گفت‌وگو', style: TextStyle(fontSize: 11, color: Color(0xFF8792A5))),
            ]),
          ),
        ],
      ),
    );
  }
}

class _FeedVideo extends StatefulWidget {
  const _FeedVideo({required this.url});
  final String url;

  @override
  State<_FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<_FeedVideo> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialized;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialized = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _initialized,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const _MediaError();
      if (snapshot.connectionState != ConnectionState.done) {
        return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator()));
      }
      return GestureDetector(
        onTap: () => setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
        }),
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Color(0x88000000), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, size: 38, color: Colors.white),
              ),
            Positioned(
              left: 8, right: 8, bottom: 8,
              child: VideoProgressIndicator(_controller, allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: HomaGramTheme.turquoise)),
            ),
          ]),
        ),
      );
    },
  );
}

class _MediaError extends StatelessWidget {
  const _MediaError();
  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Icon(Icons.broken_image_outlined, size: 38, color: Color(0xFF8490A4))),
  );
}
