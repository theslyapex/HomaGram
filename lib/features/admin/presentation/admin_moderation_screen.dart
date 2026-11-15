import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:video_player/video_player.dart';

import '../data/admin_service.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  String _type = 'all';
  final List<AdminModerationItem> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  String? _error;
  String? _working;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final rows = await AdminService.loadModerationContent(type: _type, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == 50;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t.adminModerationLoadFailed;
      });
    }
  }

  Future<void> _preview(AdminModerationItem item) async {
    final isVideo = item.type != 'profile' && item.mediaType == 'video' && item.mediaUrl != null;
    final url = item.type == 'profile' ? item.avatarUrl :
        (isVideo ? item.mediaUrl : (item.mediaUrl ?? item.coverUrl));
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminModerationPreviewUnavailable)));
      return;
    }
    if (isVideo) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  IconButton(
                    onPressed: () => controller.value.isPlaying ? controller.pause() : controller.play(),
                    icon: Icon(controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  Expanded(child: Text(_t.adminModerationReelPreview, style: TextStyle(fontWeight: FontWeight.w800))),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.adminClose)),
                ]),
              ]),
            ),
          ),
        );
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.adminModerationVideoPreviewFailed)));
      } finally {
        await controller.dispose();
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 160, child: Center(child: Text(_t.adminModerationImageLoadFailed)))),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.adminClose)),
          ]),
        ),
      ),
    );
  }

  Future<void> _warn(AdminModerationItem item) async {
    final controller = TextEditingController(
      text: _t.adminModerationDefaultWarning);
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t.adminModerationWarnTitle),
        content: TextField(
          controller: controller, minLines: 3, maxLines: 6, maxLength: 900,
          decoration: InputDecoration(labelText: _t.adminModerationWarningText, border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.feedCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(_t.adminModerationSendWarning)),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.length < 8) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'warn_user', userId: item.authorId, message: message,
    ), success: _t.adminModerationWarningSent);
  }

  Future<void> _ban(AdminModerationItem item) async {
    String duration = '168h';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: Text(_t.adminModerationBanTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_t.adminModerationBanInstruction),
          const SizedBox(height: 10),
          RadioListTile<String>(value: '24h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: Text(_t.adminDuration24Hours)),
          RadioListTile<String>(value: '168h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: Text(_t.adminDuration7Days)),
          RadioListTile<String>(value: '720h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: Text(_t.adminDuration30Days)),
          RadioListTile<String>(value: '876000h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: Text(_t.adminDurationLongTerm)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.feedCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, duration),
            child: Text(_t.adminModerationConfirmBan),
          ),
        ],
      )),
    );
    if (selected == null) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'ban_user', userId: item.authorId, duration: selected,
    ), success: _t.adminModerationUserBanned);
  }

  Future<void> _removeProfileContent(AdminModerationItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t.adminModerationProfileCleanupTitle),
        content: Text(_t.adminModerationProfileCleanupDescription),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t.feedCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t.adminModerationProfileCleanup),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'remove_profile_content', userId: item.authorId,
    ), success: _t.adminModerationProfileCleaned, removeItem: true);
  }

  Future<void> _delete(AdminModerationItem item) async {
    if (item.type == 'profile') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t.adminModerationDeleteTitle),
        content: Text(_t.adminModerationDeleteDescription),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t.feedCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t.adminModerationDeleteAndWarn),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'delete_post', postId: item.id,
    ), success: _t.adminModerationDeletedAndWarned, removeItem: true);
  }

  Future<void> _runAction(
    AdminModerationItem item,
    Future<void> Function() action, {
    required String success,
    bool removeItem = false,
  }) async {
    if (_working != null) return;
    setState(() => _working = item.id);
    try {
      await action();
      if (!mounted) return;
      if (removeItem) _items.removeWhere((x) => x.id == item.id && x.type == item.type);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminModerationActionFailed)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  String _typeLabel(String type) => switch (type) {
    'post' => _t.adminTypePost, 'reel' => _t.adminTypeReel, 'profile' => _t.adminTypeProfile, _ => _t.adminTypeContent,
  };

  String _date(DateTime? value) {
    if (value == null) return _t.adminUnknownTime;
    final d = value.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(children: [
        Expanded(child: Text(_t.adminModerationPublishedContent, style: TextStyle(fontWeight: FontWeight.w900))),
        DropdownButton<String>(
          value: _type,
          items: [
            DropdownMenuItem(value: 'all', child: Text(_t.adminFilterAll)),
            DropdownMenuItem(value: 'post', child: Text(_t.adminContentTypePosts)),
            DropdownMenuItem(value: 'reel', child: Text(_t.adminContentTypeReels)),
            DropdownMenuItem(value: 'profile', child: Text(_t.adminContentTypeProfiles)),
          ],
          onChanged: (value) {
            if (value == null || value == _type) return;
            setState(() => _type = value);
            _load(reset: true);
          },
        ),
      ]),
    ),
    if (_error != null)
      Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: () => _load(reset: true), child: Text(_t.adminRetry)),
      ])))
    else if (_loading && _items.isEmpty)
      Expanded(child: Center(child: CircularProgressIndicator()))
    else
      Expanded(child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _load(),
                  child: Text(_loading ? _t.adminModerationLoading : _t.adminModerationShowMore),
                ),
              ));
            }
            final item = _items[index];
            final busy = _working == item.id;
            final name = item.displayName?.trim().isNotEmpty == true
              ? item.displayName!.trim() : (item.username == null ? _t.adminUnknownUser : '@${item.username}');
            final previewUrl = item.type == 'profile' ? item.avatarUrl :
              (item.mediaType == 'video' ? item.coverUrl : item.mediaUrl);
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundImage: item.avatarUrl == null ? null : NetworkImage(item.avatarUrl!),
                      child: item.avatarUrl == null ? const Icon(Icons.person_outline_rounded) : null,
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text('@${item.username ?? _t.adminNoUsername}',
                        style: Theme.of(context).textTheme.labelSmall,
                        textDirection: TextDirection.ltr),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20B8B0).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_typeLabel(item.type), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  if (previewUrl != null || (item.type != 'profile' && item.mediaUrl != null)) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () => _preview(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Stack(children: [
                          SizedBox(
                            height: 175, width: double.infinity,
                            child: previewUrl == null
                              ? const ColoredBox(color: Color(0x221F8F8A), child: SizedBox(height: 175))
                              : Image.network(previewUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: Color(0x221F8F8A), child: SizedBox(height: 175)),
                                ),
                          ),
                          if (item.type != 'profile' && item.mediaType == 'video')
                            const Positioned.fill(child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 52, color: Colors.white))),
                          const Positioned(right: 8, bottom: 8, child: Icon(Icons.open_in_full_rounded, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                  if ((item.caption ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(item.caption!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.7)),
                  ],
                  if (item.type == 'profile' && (item.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.bio!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.7)),
                  ],
                  const SizedBox(height: 7),
                  Text(_t.adminModerationContentId(item.id, _date(item.createdAt)),
                    style: Theme.of(context).textTheme.labelSmall),
                  Text(_t.adminModerationOwnerId(item.authorId),
                    style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _warn(item),
                      icon: const Icon(Icons.warning_amber_rounded, size: 17),
                      label: Text(_t.adminModerationSendWarning),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _ban(item),
                      icon: const Icon(Icons.block_rounded, size: 17),
                      label: Text(_t.adminModerationBanTitle),
                    ),
                    if (item.type == 'profile')
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : () => _removeProfileContent(item),
                        icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                        label: Text(_t.adminModerationProfileCleanup),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : () => _delete(item),
                        icon: busy
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline_rounded, size: 17),
                        label: Text(_t.adminModerationDeleteTitle),
                      ),
                  ]),
                ]),
              ),
            );
          },
        ),
      )),
  ]);
}
