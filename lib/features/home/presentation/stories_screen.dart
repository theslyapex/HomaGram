import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../data/story_service.dart';
import 'story_image.dart';
import '../../../core/cache/story_video_cache.dart';

class StoriesStrip extends StatefulWidget {
  const StoriesStrip({super.key});

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = StoryService.loadActiveStories();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final next = StoryService.loadActiveStories();
    setState(() => _future = next);
    await next;
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStoryScreen()),
    );
    if (created == true && mounted) await _refresh();
  }

  Future<void> _archive() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StoryArchiveScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      final stories = snapshot.data ?? [];
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final story in stories) {
        (groups[story['author_id'] as String] ??= []).add(story);
      }
      // Keep each user's stories in chronological order (oldest first),
      // so the viewer advances through that user's story sequence naturally.
      for (final items in groups.values) {
        items.sort((a, b) {
          final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return aTime.compareTo(bTime);
        });
      }

      final uid = AuthService.client.auth.currentUser?.id;
      final own = uid == null ? null : groups.remove(uid);

      // Unseen story groups appear first; within each group, the newest
      // activity determines its position. Viewed groups follow afterward.
      final ordered = groups.entries.toList()
        ..sort((a, b) {
          final aViewed = a.value.every((story) => story['is_viewed'] == true);
          final bViewed = b.value.every((story) => story['is_viewed'] == true);
          if (aViewed != bViewed) return aViewed ? 1 : -1;

          final aLatest = DateTime.tryParse(
                a.value.last['created_at']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bLatest = DateTime.tryParse(
                b.value.last['created_at']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return bLatest.compareTo(aLatest);
        });
      return Container(
        height: 132,
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(
                children: [
                  const Text('استوری‌ها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const Spacer(),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  TextButton(
                    onPressed: _archive,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('آرشیو', style: TextStyle(fontSize: 11)),
                  ),
                  IconButton(
                    tooltip: 'تازه‌سازی استوری‌ها',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                children: [
                  _StoryAvatar(
                    title: own == null ? 'استوری شما' : 'استوری من',
                    imageUrl: own?.last['avatar_url'] as String?,
                    imageCacheKey: own?.last['avatar_path'] as String?,
                    hasStory: own != null,
                    viewed: own != null && own.every((s) => s['is_viewed'] == true),
                    add: own == null,
                    onTap: own == null ? _create : () => _open(own),
                  ),
                  ...ordered.map((entry) => _StoryAvatar(
                    title: entry.value.first['display_name'] as String,
                    imageUrl: entry.value.first['avatar_url'] as String?,
                    imageCacheKey: entry.value.first['avatar_path'] as String?,
                    hasStory: true,
                    viewed: entry.value.every((s) => s['is_viewed'] == true),
                    onTap: () => _open(entry.value),
                  )),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  void _open(List<Map<String, dynamic>> items) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(stories: items),
    )).then((_) => _refresh());
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.title,
    required this.imageUrl,
    this.imageCacheKey,
    required this.hasStory,
    required this.viewed,
    required this.onTap,
    this.add = false,
  });

  final String title;
  final String? imageUrl;
  final String? imageCacheKey;
  final bool hasStory;
  final bool viewed;
  final bool add;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasStory && !viewed
                  ? const LinearGradient(colors: [Color(0xFF20B8B0), Color(0xFF7356C8), Color(0xFFE35D9A)])
                  : null,
              border: hasStory && viewed ? Border.all(color: Colors.grey, width: 2) : null,
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .14),
              backgroundImage: imageUrl == null ? null : StoryImageProvider(imageUrl!, cacheKey: 'avatar:${imageCacheKey ?? imageUrl!}'),
              child: imageUrl == null
                  ? const Icon(Icons.person_outline_rounded, color: HomaGramTheme.turquoise)
                  : null,
            ),
          ),
          const SizedBox(height: 5),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          if (add)
            const Text('افزودن', style: TextStyle(fontSize: 9, color: HomaGramTheme.turquoise)),
        ],
      ),
    ),
  );
}

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  XFile? _file;
  String? _type;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(bool video) async {
    try {
      final picked = video
          ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60))
          : await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
      if (picked == null || !mounted) return;
      final name = picked.name.toLowerCase();
      final mime = picked.mimeType ?? '';
      final valid = video
          ? mime == 'video/mp4' || mime == 'video/quicktime' || name.endsWith('.mp4') || name.endsWith('.mov')
          : mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp' ||
              RegExp(r'\.(jpe?g|png|webp)$').hasMatch(name);
      if (!valid) {
        _notice('فرمت این رسانه پشتیبانی نمی‌شود.', true);
        return;
      }
      final size = await picked.length();
      if (size == 0 || size > 50 * 1024 * 1024) {
        _notice('حجم رسانه باید حداکثر ۵۰ مگابایت باشد.', true);
        return;
      }
      setState(() { _file = picked; _type = video ? 'video' : 'image'; });
    } catch (_) {
      _notice('انتخاب رسانه انجام نشد.', true);
    }
  }

  void _notice(String message, [bool error = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _publish() async {
    final file = _file;
    final type = _type;
    if (file == null || type == null || _busy) {
      _notice('ابتدا تصویر یا ویدئو انتخاب کنید.', true);
      return;
    }
    if (_caption.text.trim().length > 500) {
      _notice('متن استوری حداکثر ۵۰۰ نویسه است.', true);
      return;
    }
    setState(() => _busy = true);
    try {
      final mime = file.mimeType ?? (type == 'video'
          ? (file.name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
          : _imageMime(file.name));
      await StoryService.publish(
        file: File(file.path),
        mediaType: type,
        fileName: file.name,
        mimeType: mime,
        caption: _caption.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _notice('انتشار استوری انجام نشد. اتصال یا فرمت رسانه را بررسی کنید.', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _imageMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ساخت استوری')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_file == null)
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2)),
            ),
            child: const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 58, color: HomaGramTheme.turquoise)),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 300,
              child: _type == 'image'
                  ? Image.file(File(_file!.path), fit: BoxFit.contain)
                  : Container(
                      color: Colors.black87,
                      child: const Center(child: Icon(Icons.play_circle_outline, size: 70, color: Colors.white)),
                    ),
            ),
          ),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(false),
          icon: const Icon(Icons.image_outlined), label: const Text('انتخاب تصویر')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _busy ? null : () => _pick(true),
          icon: const Icon(Icons.video_library_outlined), label: const Text('انتخاب ویدئو (حداکثر ۶۰ ثانیه)')),
        const SizedBox(height: 14),
        TextField(
          controller: _caption, maxLength: 500, maxLines: 3,
          decoration: const InputDecoration(labelText: 'متن استوری (اختیاری)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        const Text('استوری پس از ۲۴ ساعت از نمایش عمومی خارج می‌شود و در آرشیو شخصی شما باقی می‌ماند.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.8, color: Color(0xFF8490A4))),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(_busy ? 'در حال انتشار...' : 'انتشار استوری'),
        ),
      ],
    ),
  );
}

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({required this.stories, super.key});
  final List<Map<String, dynamic>> stories;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _progress;
  int _index = 0;
  int _replayNonce = 0;
  bool _busy = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _lifecyclePaused = false;
  bool _advancing = false;
  bool _routeVisible = true;
  double _horizontalDragDistance = 0;

  Map<String, dynamic> get _story => widget.stories[_index];
  bool get _isMine => _story['author_id'] == AuthService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener(_onProgressStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markViewed();
      if (_story['media_type'] == 'image') _startProgress();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _routeVisible = active;
    _lifecyclePaused = !active;
    _syncPauseState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _nextStory();
  }

  void _startProgress({Duration? duration}) {
    if (!mounted) return;
    _progress.stop();
    _progress.duration = duration ?? const Duration(seconds: 5);
    _progress.value = 0;
    if (!_paused) _progress.forward();
  }

  void _onVideoReady(String storyId, Duration duration) {
    if (!mounted || _story['id'] != storyId || _story['media_type'] != 'video') return;
    _progress.stop();
    _progress.value = 0;
  }

  void _onVideoProgress(String storyId, Duration position, Duration duration, bool completed) {
    if (!mounted || _story['id'] != storyId || _story['media_type'] != 'video') return;
    if (duration > Duration.zero) {
      final value = (position.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0).toDouble();
      // Keep the animation controller as a display value only for video.
      _progress.value = completed ? .999 : value.clamp(0.0, .999).toDouble();
    }
    if (completed && !_advancing) _nextStory();
  }

  void _nextStory() {
    if (!mounted || _advancing) return;
    _advancing = true;
    if (_index < widget.stories.length - 1) {
      _progress.stop();
      setState(() {
        _index++;
        _paused = _userPaused || _lifecyclePaused || !_routeVisible;
      });
      _markViewed();
      if (_story['media_type'] == 'image') _startProgress();
    } else {
      Navigator.of(context).pop();
    }
    _advancing = false;
  }

  void _previousStory() {
    if (!mounted) return;
    if (_index > 0) {
      _progress.stop();
      setState(() {
        _index--;
        _paused = _userPaused || _lifecyclePaused || !_routeVisible;
      });
      _markViewed();
      if (_story['media_type'] == 'image') _startProgress();
    } else {
      _startProgress();
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _horizontalDragDistance = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDistance += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final distance = _horizontalDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _horizontalDragDistance = 0;

    // A deliberate swipe needs either a clear horizontal travel distance
    // or a sufficiently strong horizontal fling.
    if (distance <= -70 || velocity <= -500) {
      _nextStory();
    } else if (distance >= 70 || velocity >= 500) {
      _previousStory();
    }
  }

  void _setUserPaused(bool pause) {
    _userPaused = pause;
    _syncPauseState();
  }

  void _syncPauseState() {
    if (!mounted) return;
    final shouldPause = _userPaused || _lifecyclePaused || !_routeVisible;
    if (_paused == shouldPause) return;
    setState(() => _paused = shouldPause);
    if (shouldPause) {
      _progress.stop();
    } else if (_story['media_type'] == 'image') {
      _progress.forward();
    }
  }

  Future<void> _markViewed() async {
    if (_isMine) return;
    try { await StoryService.recordView(_story['id'] as String); } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    if (_busy || _isMine) return;
    setState(() => _busy = true);
    try {
      await StoryService.react(_story['id'] as String, emoji);
      if (mounted) _notice('واکنش شما ثبت شد.');
    } catch (_) {
      if (mounted) _notice('ثبت واکنش انجام نشد.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پاسخ به استوری'),
      content: TextField(controller: controller, autofocus: true, maxLength: 1000,
        minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'پیام شما')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ارسال')),
      ],
    ));
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await StoryService.replyToStory(_story['author_id'] as String, 'پاسخ به استوری: $text');
      if (mounted) _notice('پاسخ از طریق پیام خصوصی ارسال شد.');
    } catch (_) {
      if (mounted) _notice('ارسال پاسخ انجام نشد.', error: true);
    }
  }

  Future<void> _showViewers() async {
    try {
      final viewers = await StoryService.loadViewers(_story['id'] as String);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context, showDragHandle: true, isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(16),
                child: Text('بازدیدکنندگان • ${viewers.length}', style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(child: viewers.isEmpty
                  ? const Center(child: Text('هنوز بازدیدی ثبت نشده است.'))
                  : ListView.builder(itemCount: viewers.length, itemBuilder: (_, i) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(viewers[i]['display_name'] as String),
                      subtitle: Text('@${viewers[i]['username']}${viewers[i]['reaction'] == null ? '' : ' • واکنش ${viewers[i]['reaction']}'}'),
                    ))),
            ]),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _notice('فهرست بازدیدکنندگان بارگذاری نشد.', error: true);
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف استوری'),
      content: const Text('این استوری حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    ));
    if (yes != true) return;
    try {
      final mediaPath = _story['media_path'] as String;
      final mediaUrl = _story['media_url'] as String?;
      if (mediaUrl != null) {
        await imageCache.evict(StoryImageProvider(mediaUrl, cacheKey: 'story-media:$mediaPath'));
      }
      await StoryService.deleteStory(_story);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _notice('حذف استوری انجام نشد.', error: true);
    }
  }

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: error ? Colors.red : null,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onHorizontalDragCancel: () => _horizontalDragDistance = 0,
        child: Stack(children: [
        _StoryMedia(
          key: ValueKey('${_story['id']}-$_replayNonce'),
          story: _story,
          paused: _paused,
          onVideoReady: _onVideoReady,
          onVideoProgress: _onVideoProgress,
        ),
        Positioned.fill(
          child: Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _previousStory,
              onLongPressStart: (_) => _setUserPaused(true),
              onLongPressEnd: (_) => _setUserPaused(false),
            )),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _nextStory,
              onLongPressStart: (_) => _setUserPaused(true),
              onLongPressEnd: (_) => _setUserPaused(false),
            )),
          ]),
        ),
        Positioned(
          top: 10, left: 12, right: 12,
          child: Column(children: [
            Row(children: List.generate(widget.stories.length, (i) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 3,
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (_, __) => LinearProgressIndicator(
                        value: i < _index ? 1 : i > _index ? 0 : _progress.value,
                        backgroundColor: Colors.white38,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ))),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: _story['avatar_url'] == null ? null : StoryImageProvider(
                  _story['avatar_url'] as String,
                  cacheKey: 'avatar:${(_story['avatar_path'] as String?) ?? (_story['avatar_url'] as String)}',
                ),
                child: _story['avatar_url'] == null ? const Icon(Icons.person_outline) : null,
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(_story['display_name'] as String,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              if (_isMine)
                IconButton(onPressed: _showViewers, icon: const Icon(Icons.visibility_outlined, color: Colors.white)),
              if (_isMine)
                IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: Colors.white)),
              IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ]),
        ),
        if ((_story['caption'] as String).isNotEmpty)
          Positioned(left: 22, right: 22, bottom: 94,
            child: IgnorePointer(child: Text(_story['caption'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 8, color: Colors.black)])))),
        Positioned(
          left: 12, right: 12, bottom: 12,
          child: _isMine
              ? Align(alignment: Alignment.center, child: OutlinedButton.icon(
                  onPressed: _showViewers,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  icon: const Icon(Icons.visibility_outlined), label: const Text('مشاهده بازدیدکنندگان')))
              : Row(children: [
                  ...['❤️','🔥','👏','😂','😮'].map((e) => IconButton(
                    onPressed: _busy ? null : () => _react(e),
                    icon: Text(e, style: const TextStyle(fontSize: 23)),
                  )),
                  const Spacer(),
                  IconButton(onPressed: _reply, icon: const Icon(Icons.send_rounded, color: Colors.white)),
                ]),
        ),
        ]),
      ),
    ),
  );
}

class _StoryMedia extends StatefulWidget {
  const _StoryMedia({
    required this.story,
    required this.paused,
    required this.onVideoReady,
    required this.onVideoProgress,
    super.key,
  });
  final Map<String, dynamic> story;
  final bool paused;
  final void Function(String storyId, Duration duration) onVideoReady;
  final void Function(String storyId, Duration position, Duration duration, bool completed) onVideoProgress;

  @override
  State<_StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends State<_StoryMedia> {
  VideoPlayerController? _video;
  bool _loading = true;
  bool _hasError = false;
  bool _completionReported = false;
  bool _playbackErrorReported = false;

  @override
  void initState() {
    super.initState();
    if (widget.story['media_type'] == 'video' && widget.story['media_url'] != null) {
      _loadVideo();
    } else {
      _loading = false;
    }
  }

  Future<void> _loadVideo() async {
    final url = widget.story['media_url'] as String?;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
      return;
    }

    final previous = _video;
    if (previous != null) {
      previous.removeListener(_handleVideoUpdate);
      _video = null;
      await previous.dispose();
    }
    if (!mounted) return;

    setState(() {
      _loading = true;
      _hasError = false;
      _completionReported = false;
      _playbackErrorReported = false;
    });

    VideoPlayerController? controller;
    try {
      // Cache private media briefly in this account's app-private temp area.
      // Keep network playback as a fallback if the download/cache is unavailable.
      final userId = AuthService.client.auth.currentUser?.id;
      File? cachedFile;
      if (userId != null) {
        try {
          cachedFile = await StoryVideoCache.getOrDownload(
            url: url,
            storagePath: widget.story['media_path'] as String? ?? widget.story['id'].toString(),
            userId: userId,
          ).timeout(const Duration(seconds: 45));
        } catch (_) {
          cachedFile = null;
        }
      }

      controller = cachedFile != null
          ? VideoPlayerController.file(cachedFile)
          : VideoPlayerController.networkUrl(Uri.parse(url));
      _video = controller;
      await controller.initialize().timeout(const Duration(seconds: 30));

      if (!mounted || !identical(_video, controller)) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(false);
      controller.addListener(_handleVideoUpdate);
      setState(() => _loading = false);
      widget.onVideoReady(widget.story['id'] as String, controller.value.duration);
      if (!widget.paused) await controller.play();
    } catch (_) {
      if (controller != null) {
        controller.removeListener(_handleVideoUpdate);
        if (identical(_video, controller)) _video = null;
        await controller.dispose();
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  void _handleVideoUpdate() {
    final video = _video;
    if (!mounted || video == null || !video.value.isInitialized) return;
    final value = video.value;

    if (value.hasError) {
      if (!_playbackErrorReported) {
        _playbackErrorReported = true;
        setState(() => _hasError = true);
      }
      return;
    }

    final duration = value.duration;
    final completed = duration > Duration.zero && value.position >= duration;
    widget.onVideoProgress(
      widget.story['id'] as String,
      value.position,
      duration,
      completed && !_completionReported,
    );
    if (completed) _completionReported = true;
  }

  @override
  void didUpdateWidget(covariant _StoryMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _video?.pause();
      } else if (_video?.value.isInitialized == true && !_hasError) {
        _video?.play();
      }
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_handleVideoUpdate);
    _video?.dispose();
    super.dispose();
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 42),
          const SizedBox(height: 12),
          const Text(
            'پخش ویدئو انجام نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, height: 1.7),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _loadVideo,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تلاش دوباره'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final url = widget.story['media_url'] as String?;
    if (url == null || url.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
      );
    }

    if (widget.story['media_type'] == 'video') {
      if (_hasError) return _errorView();
      if (_loading || _video?.value.isInitialized != true) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text('در حال بارگذاری ویدئو…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      }
      final video = _video!;
      return Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio > 0 ? video.value.aspectRatio : 9 / 16,
          child: VideoPlayer(video),
        ),
      );
    }

    return Center(
      child: Image(
        image: StoryImageProvider(
          url,
          cacheKey: 'story-media:${widget.story['media_path']}',
        ),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }
}

class StoryArchiveScreen extends StatefulWidget {
  const StoryArchiveScreen({super.key});

  @override
  State<StoryArchiveScreen> createState() => _StoryArchiveScreenState();
}

class _StoryArchiveScreenState extends State<StoryArchiveScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = StoryService.loadArchive();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('آرشیو استوری‌ها')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return const Center(child: Text('آرشیو بارگذاری نشد.'));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('هنوز استوری منقضی‌شده‌ای ندارید.'));
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: .68,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => StoryViewerScreen(stories: [items[i]]),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                items[i]['media_type'] == 'image' && items[i]['media_url'] != null
                    ? Image(
                        image: StoryImageProvider(
                          items[i]['media_url'] as String,
                          cacheKey: 'story-media:${items[i]['media_path']}',
                        ),
                        fit: BoxFit.cover,
                      )
                    : Container(color: Colors.black87, child: const Icon(Icons.play_circle_outline, color: Colors.white)),
                Positioned(bottom: 5, left: 5, right: 5,
                  child: Text(items[i]['created_at'].toString().substring(0, 10),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, shadows: [Shadow(blurRadius: 5, color: Colors.black)]))),
              ]),
            ),
          ),
        );
      },
    ),
  );
}
