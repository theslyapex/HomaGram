import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../data/story_service.dart';

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
      final uid = AuthService.client.auth.currentUser?.id;
      final own = uid == null ? null : groups.remove(uid);
      final ordered = groups.entries.toList()
        ..sort((a, b) => (b.value.last['created_at'] as String)
            .compareTo(a.value.last['created_at'] as String));
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
                    hasStory: own != null,
                    viewed: own != null && own.every((s) => s['is_viewed'] == true),
                    add: own == null,
                    onTap: own == null ? _create : () => _open(own),
                  ),
                  ...ordered.map((entry) => _StoryAvatar(
                    title: entry.value.first['display_name'] as String,
                    imageUrl: entry.value.first['avatar_url'] as String?,
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
    required this.hasStory,
    required this.viewed,
    required this.onTap,
    this.add = false,
  });

  final String title;
  final String? imageUrl;
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
              backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
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
      final mime = file.mimeType ?? (type == 'video' ? 'video/mp4' : _imageMime(file.name));
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

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _busy = false;

  Map<String, dynamic> get _story => widget.stories[_index];
  bool get _isMine => _story['author_id'] == AuthService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markViewed());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
                      subtitle: Text('@${viewers[i]['username']}'),
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
      child: Stack(children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.stories.length,
          onPageChanged: (value) {
            setState(() => _index = value);
            _markViewed();
          },
          itemBuilder: (_, i) => _StoryMedia(story: widget.stories[i]),
        ),
        Positioned(
          top: 10, left: 12, right: 12,
          child: Column(children: [
            Row(children: List.generate(widget.stories.length, (i) => Expanded(
              child: Container(
                height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i <= _index ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ))),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: _story['avatar_url'] == null ? null : NetworkImage(_story['avatar_url'] as String),
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
            child: Text(_story['caption'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(blurRadius: 8, color: Colors.black)]))),
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
  );
}

class _StoryMedia extends StatefulWidget {
  const _StoryMedia({required this.story});
  final Map<String, dynamic> story;

  @override
  State<_StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends State<_StoryMedia> {
  VideoPlayerController? _video;
  Future<void>? _initializing;

  @override
  void initState() {
    super.initState();
    if (widget.story['media_type'] == 'video' && widget.story['media_url'] != null) {
      _video = VideoPlayerController.networkUrl(Uri.parse(widget.story['media_url'] as String));
      _initializing = _video!.initialize().then((_) {
        _video!.setLooping(true);
        _video!.play();
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.story['media_url'] as String?;
    if (url == null) return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48));
    if (widget.story['media_type'] == 'video') {
      return FutureBuilder<void>(
        future: _initializing,
        builder: (_, snapshot) {
          if (snapshot.hasError) return const Center(child: Icon(Icons.error_outline, color: Colors.white));
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          return Center(child: AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)));
        },
      );
    }
    return Center(child: Image.network(url, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white, size: 48)));
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
                    ? Image.network(items[i]['media_url'] as String, fit: BoxFit.cover)
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
