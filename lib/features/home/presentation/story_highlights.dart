import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../data/story_service.dart';
import 'stories_screen.dart';
import 'story_image.dart';

class StoryHighlightService {
  StoryHighlightService._();

  static final _client = AuthService.client;

  static Future<List<Map<String, dynamic>>> loadHighlights(String ownerId) async {
    final highlights = await _client
        .from('story_highlights')
        .select('id,title,created_at')
        .eq('owner_id', ownerId)
        .order('created_at')
        .limit(30);
    if (highlights.isEmpty) return [];

    final ids = highlights.map((h) => h['id'] as String).toList();
    final itemRows = await _client
        .from('story_highlight_items')
        .select('highlight_id,story_id,position')
        .inFilter('highlight_id', ids)
        .order('position');
    final storyIds = itemRows.map((r) => r['story_id'] as String).toSet().toList();
    if (storyIds.isEmpty) {
      return highlights.map((h) => {
        ...Map<String, dynamic>.from(h),
        'stories': <Map<String, dynamic>>[],
      }).toList();
    }

    final storyRows = await _client
        .from('stories')
        .select('id,author_id,media_path,media_type,caption,created_at,expires_at')
        .inFilter('id', storyIds)
        .order('created_at');
    final profile = await _client
        .from('profiles')
        .select('id,username,display_name,avatar_path')
        .eq('id', ownerId)
        .maybeSingle();
    final avatarPath = profile?['avatar_path'] as String?;
    String? avatarUrl;
    if (avatarPath != null) {
      try {
        avatarUrl = await _client.storage.from('avatars').createSignedUrl(avatarPath, 3600);
      } catch (_) {}
    }

    final paths = storyRows
        .map((s) => s['media_path'] as String)
        .toSet()
        .toList();
    final mediaUrls = <String, String>{};
    const batchSize = 8;
    for (var i = 0; i < paths.length; i += batchSize) {
      final batch = paths.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((path) async {
        try {
          return MapEntry(path, await _client.storage.from('story-media').createSignedUrl(path, 3600));
        } catch (_) {
          return null;
        }
      }));
      for (final result in results) {
        if (result != null) mediaUrls[result.key] = result.value;
      }
    }

    final storiesById = <String, Map<String, dynamic>>{};
    for (final row in storyRows) {
      final story = Map<String, dynamic>.from(row);
      story['display_name'] = profile?['display_name'] ?? 'کاربر HomaGram';
      story['username'] = profile?['username'] ?? 'user';
      story['avatar_path'] = avatarPath;
      story['avatar_url'] = avatarUrl;
      story['media_url'] = mediaUrls[story['media_path']];
      story['is_viewed'] = false;
      storiesById[story['id'] as String] = story;
    }

    final itemsByHighlight = <String, List<Map<String, dynamic>>>{};
    for (final item in itemRows) {
      final story = storiesById[item['story_id'] as String];
      if (story != null) {
        (itemsByHighlight[item['highlight_id'] as String] ??= []).add(story);
      }
    }

    return highlights.map((h) => {
      ...Map<String, dynamic>.from(h),
      'stories': itemsByHighlight[h['id'] as String] ?? <Map<String, dynamic>>[],
    }).where((h) => (h['stories'] as List).isNotEmpty).toList();
  }

  static Future<void> createHighlight(String title, List<String> storyIds) async {
    final cleanTitle = title.trim();
    final uniqueIds = storyIds.toSet().toList();
    if (cleanTitle.isEmpty || cleanTitle.length > 30 || uniqueIds.isEmpty || uniqueIds.length > 100) {
      throw ArgumentError('عنوان باید ۱ تا ۳۰ نویسه و تعداد استوری‌ها ۱ تا ۱۰۰ باشد.');
    }
    final ownerId = _client.auth.currentUser!.id;
    final created = await _client
        .from('story_highlights')
        .insert({'owner_id': ownerId, 'title': cleanTitle})
        .select('id')
        .single();
    final highlightId = created['id'] as String;
    try {
      await _client.from('story_highlight_items').insert([
        for (var i = 0; i < uniqueIds.length; i++)
          {'highlight_id': highlightId, 'story_id': uniqueIds[i], 'position': i}
      ]);
    } catch (_) {
      try {
        await _client.from('story_highlights').delete().eq('id', highlightId);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> updateHighlight({
    required String highlightId,
    required String oldTitle,
    required String title,
    required List<String> storyIds,
  }) async {
    final cleanTitle = title.trim();
    final uniqueIds = storyIds.toSet().toList();
    if (cleanTitle.isEmpty || cleanTitle.length > 30 ||
        uniqueIds.isEmpty || uniqueIds.length > 100) {
      throw ArgumentError('عنوان باید ۱ تا ۳۰ نویسه و تعداد استوری‌ها ۱ تا ۱۰۰ باشد.');
    }

    final ownerId = _client.auth.currentUser!.id;
    final currentRows = await _client
        .from('story_highlight_items')
        .select('story_id,position')
        .eq('highlight_id', highlightId);
    final currentIds = currentRows.map((row) => row['story_id'] as String).toSet();
    final selectedIds = uniqueIds.toSet();
    final additions = uniqueIds.where((id) => !currentIds.contains(id)).toList();
    final removals = currentIds.where((id) => !selectedIds.contains(id)).toList();

    if (additions.isNotEmpty) {
      final maxPosition = currentRows.fold<int>(
        -1,
        (value, row) => (row['position'] as int) > value
            ? row['position'] as int
            : value,
      );
      await _client.from('story_highlight_items').insert([
        for (var i = 0; i < additions.length; i++)
          {
            'highlight_id': highlightId,
            'story_id': additions[i],
            'position': maxPosition + i + 1,
          }
      ]);
    }

    try {
      await _client.from('story_highlights')
          .update({'title': cleanTitle})
          .eq('id', highlightId)
          .eq('owner_id', ownerId);

      if (removals.isNotEmpty) {
        await _client.from('story_highlight_items')
            .delete()
            .eq('highlight_id', highlightId)
            .inFilter('story_id', removals);
      }
    } catch (_) {
      // Best-effort compensation prevents newly added items from being left
      // behind when a later edit step fails.
      if (additions.isNotEmpty) {
        try {
          await _client.from('story_highlight_items')
              .delete()
              .eq('highlight_id', highlightId)
              .inFilter('story_id', additions);
        } catch (_) {}
      }
      try {
        await _client.from('story_highlights')
            .update({'title': oldTitle})
            .eq('id', highlightId)
            .eq('owner_id', ownerId);
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> deleteHighlight(String highlightId) async {
    await _client.from('story_highlights').delete().eq('id', highlightId);
  }
}

class StoryHighlightsStrip extends StatefulWidget {
  const StoryHighlightsStrip({
    required this.ownerId,
    required this.isOwner,
    super.key,
  });

  final String ownerId;
  final bool isOwner;

  @override
  State<StoryHighlightsStrip> createState() => _StoryHighlightsStripState();
}

class _StoryHighlightsStripState extends State<StoryHighlightsStrip> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = StoryHighlightService.loadHighlights(widget.ownerId);
  }

  @override
  void didUpdateWidget(covariant StoryHighlightsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      _future = StoryHighlightService.loadHighlights(widget.ownerId);
    }
  }

  Future<void> _reload() async {
    final next = StoryHighlightService.loadHighlights(widget.ownerId);
    setState(() => _future = next);
    await next;
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryHighlightEditorScreen()),
    );
    if (created == true && mounted) await _reload();
  }

  Future<void> _open(Map<String, dynamic> highlight) async {
    final stories = (highlight['stories'] as List).cast<Map<String, dynamic>>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => StoryViewerScreen(stories: stories)),
    );
  }

  Future<void> _manage(Map<String, dynamic> highlight) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(highlight['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('مدیریت مجموعه هایلایت'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('ویرایش عنوان و استوری‌ها'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('حذف هایلایت', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      final updated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => StoryHighlightEditorScreen(highlight: highlight),
        ),
      );
      if (updated == true && mounted) await _reload();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف هایلایت'),
        content: Text('هایلایت «${highlight['title']}» حذف شود؟ استوری‌های آرشیو شما حذف نمی‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await StoryHighlightService.deleteHighlight(highlight['id'] as String);
      if (mounted) await _reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حذف هایلایت انجام نشد.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      final highlights = snapshot.data ?? [];
      if (!widget.isOwner && snapshot.connectionState == ConnectionState.done && highlights.isEmpty) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: 112,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            if (widget.isOwner)
              _HighlightAvatar(
                title: 'جدید',
                add: true,
                onTap: _create,
              ),
            ...highlights.map((highlight) {
              final stories = (highlight['stories'] as List).cast<Map<String, dynamic>>();
              final first = stories.first;
              return _HighlightAvatar(
                title: highlight['title'] as String,
                imageUrl: first['media_url'] as String?,
                onTap: () => _open(highlight),
                onLongPress: widget.isOwner ? () => _manage(highlight) : null,
                video: first['media_type'] == 'video',
              );
            }),
            if (snapshot.connectionState == ConnectionState.waiting && highlights.isEmpty)
              const SizedBox(width: 54, child: Center(child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
              ))),
          ],
        ),
      );
    },
  );
}

class _HighlightAvatar extends StatelessWidget {
  const _HighlightAvatar({
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.add = false,
    this.video = false,
    this.onLongPress,
  });

  final String title;
  final String? imageUrl;
  final bool add;
  final bool video;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: add ? HomaGramTheme.turquoise : Theme.of(context).dividerColor,
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: add
                  ? const ColoredBox(
                      color: Color(0x1420B8B0),
                      child: Icon(Icons.add_rounded, color: HomaGramTheme.turquoise, size: 30),
                    )
                  : imageUrl == null
                      ? const ColoredBox(
                          color: Color(0x221D2B46),
                          child: Icon(Icons.auto_awesome_rounded, color: HomaGramTheme.turquoise),
                        )
                      : Stack(fit: StackFit.expand, children: [
                          Image(
                            image: StoryImageProvider(imageUrl!, cacheKey: 'highlight-cover:$imageUrl'),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0x221D2B46),
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          if (video)
                            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22)),
                        ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

class StoryHighlightEditorScreen extends StatefulWidget {
  const StoryHighlightEditorScreen({this.highlight, super.key});

  final Map<String, dynamic>? highlight;

  @override
  State<StoryHighlightEditorScreen> createState() => _StoryHighlightEditorScreenState();
}

class _StoryHighlightEditorScreenState extends State<StoryHighlightEditorScreen> {
  final _title = TextEditingController();
  late Future<List<Map<String, dynamic>>> _archive;
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.highlight;
    if (existing != null) {
      _title.text = existing['title'] as String? ?? '';
      final stories = (existing['stories'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      _selected.addAll(stories.map((story) => story['id'] as String));
    }
    _archive = StoryService.loadArchive();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty || _title.text.trim().length > 30) {
      _message('عنوان هایلایت باید ۱ تا ۳۰ نویسه باشد.');
      return;
    }
    if (_selected.isEmpty) {
      _message('حداقل یک استوری از آرشیو انتخاب کنید.');
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.highlight;
      if (existing == null) {
        await StoryHighlightService.createHighlight(_title.text, _selected.toList());
      } else {
        await StoryHighlightService.updateHighlight(
          highlightId: existing['id'] as String,
          oldTitle: existing['title'] as String? ?? '',
          title: _title.text,
          storyIds: _selected.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _message('ساخت هایلایت انجام نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.highlight == null ? 'ساخت هایلایت' : 'ویرایش هایلایت'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '...' : (widget.highlight == null ? 'ذخیره' : 'ذخیره تغییرات')),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _archive,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('آرشیو استوری‌ها بارگذاری نشد.'));
        }
        final itemsById = <String, Map<String, dynamic>>{};
        for (final story in snapshot.data ?? <Map<String, dynamic>>[]) {
          itemsById[story['id'] as String] = story;
        }
        final existingStories = (widget.highlight?['stories'] as List? ?? const [])
            .whereType<Map<String, dynamic>>();
        for (final story in existingStories) {
          itemsById[story['id'] as String] = story;
        }
        final items = itemsById.values.toList()
          ..sort((a, b) => (b['created_at'] as String)
              .compareTo(a['created_at'] as String));
        if (items.isEmpty) {
          return const Center(child: Text('برای ساخت هایلایت، ابتدا باید استوری‌ای در آرشیو داشته باشید.'));
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _title,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'عنوان هایلایت',
                  hintText: 'مثلاً سفرها، پروژه‌ها، لحظه‌ها',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('انتخاب استوری‌ها • ${_selected.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
                  childAspectRatio: .68,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final story = items[index];
                  final id = story['id'] as String;
                  final selected = _selected.contains(id);
                  final url = story['media_url'] as String?;
                  return InkWell(
                    onTap: () => setState(() {
                      if (selected) {
                        _selected.remove(id);
                      } else if (_selected.length < 100) {
                        _selected.add(id);
                      }
                    }),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(fit: StackFit.expand, children: [
                        if (story['media_type'] == 'image' && url != null)
                          Image(
                            image: StoryImageProvider(url, cacheKey: 'highlight-select:$id'),
                            fit: BoxFit.cover,
                          )
                        else
                          const ColoredBox(
                            color: Color(0xFF171C2B),
                            child: Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 36)),
                          ),
                        Positioned(bottom: 6, left: 6, right: 6,
                          child: Text(
                            (story['created_at'] as String).substring(0, 10),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 9,
                              shadows: [Shadow(blurRadius: 5, color: Colors.black)]),
                          ),
                        ),
                        if (selected)
                          const Positioned(top: 6, right: 6,
                            child: CircleAvatar(radius: 12, child: Icon(Icons.check_rounded, size: 16))),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'در حال ذخیره...' :
                      (widget.highlight == null ? 'ساخت هایلایت (${_selected.length})' : 'ذخیره تغییرات (${_selected.length})')),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
