import 'dart:ui' as ui;

import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/data/auth_service.dart';
import 'create_post_screen.dart';
import 'feed_screen.dart';
import 'public_profile_screen.dart';
import '../../../core/utils/persian_date.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({this.isVisible = true, this.initialReelId, super.key});
  final bool isVisible;
  final String? initialReelId;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  late Future<List<Map<String, dynamic>>> _reels;
  int _activeIndex = 0;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _reels = _loadReels();
  }

  Future<List<Map<String, dynamic>>> _loadReels() async {
    final client = AuthService.client;
    final uid = client.auth.currentUser!.id;
    final rows = await client.from('posts')
        .select('id,author_id,author_username,author_display_name,caption,media_path,media_type,cover_path,created_at,is_public')
        .eq('is_reel', true)
        .order('created_at', ascending: false)
        .limit(60);
    final authorIds = rows.map((r) => r['author_id'] as String).toSet().toList();
    final profiles = authorIds.isEmpty ? <dynamic>[] : await client.from('profiles')
        .select('id,avatar_path').inFilter('id', authorIds);
    final avatarById = {for (final p in profiles) p['id'] as String: p['avatar_path'] as String?};
    final output = <Map<String, dynamic>>[];
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row);
      final path = item['media_path'] as String?;
      if (path == null || path.isEmpty ||
          (item['media_type'] != 'video' && item['is_reel'] != true)) continue;
      try {
        item['media_url'] = await client.storage.from('post-media').createSignedUrl(path, 3600);
      } catch (_) {
        continue;
      }
      final coverPath = item['cover_path'] as String?;
      if (coverPath != null) {
        try {
          item['cover_url'] = await client.storage.from('post-media').createSignedUrl(coverPath, 3600);
        } catch (_) {}
      }
      final avatarPath = avatarById[item['author_id'] as String];
      if (avatarPath != null) {
        try {
          item['avatar_url'] = await client.storage.from('avatars').createSignedUrl(avatarPath, 3600);
        } catch (_) {}
      }
      item['is_mine'] = item['author_id'] == uid;
      output.add(item);
    }
    if (widget.initialReelId != null) {
      final targetIndex = output.indexWhere((item) => item['id'] == widget.initialReelId);
      if (targetIndex >= 0) _activeIndex = targetIndex;
    }
    return output;
  }

  Future<void> _refresh() async {
    final next = _loadReels();
    setState(() => _reels = next);
    await next;
  }

  Future<void> _createReel() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CreatePostScreen(initialReel: true)),
    );
    if (published == true && mounted) await _refresh();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _reels,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _emptyState(_t.reelsLoadFailed, _t.feedConnectionRetry,
          onPressed: _refresh, icon: Icons.cloud_off_outlined);
      }
      final reels = snapshot.data ?? [];
      if (reels.isEmpty) {
        return _emptyState(_t.reelsEmptyTitle,
          _t.reelsEmptyMessage,
          onPressed: _createReel, icon: Icons.video_collection_outlined,
          actionLabel: _t.reelsCreateFirst);
      }
      _pageController ??= PageController(initialPage: _activeIndex);
      return RefreshIndicator(
        onRefresh: _refresh,
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: reels.length,
          onPageChanged: (index) => setState(() => _activeIndex = index),
          itemBuilder: (context, index) => _ReelCard(
            key: ValueKey(reels[index]['id']),
            reel: reels[index],
            isActive: widget.isVisible && index == _activeIndex,
          ),
        ),
      );
    },
  );

  Widget _emptyState(String title, String subtitle, {
    required VoidCallback onPressed,
    required IconData icon,
    String? actionLabel,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 58, color: HomaGramTheme.turquoise),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8490A4), height: 1.6)),
        const SizedBox(height: 18),
        HomaGramSpringPress(child: FilledButton.icon(onPressed: onPressed,
          icon: const Icon(Icons.add_rounded), label: Text(actionLabel ?? AppLocalizations.of(context)!.feedRetry))),
      ]),
    ),
  );
}

class _ReelCard extends StatefulWidget {
  const _ReelCard({required this.reel, required this.isActive, super.key});
  final Map<String, dynamic> reel;
  final bool isActive;

  @override
  State<_ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<_ReelCard> with WidgetsBindingObserver {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  VideoPlayerController? _video;
  bool _loading = true;
  bool _liked = false;
  bool _busy = false;
  int _likes = 0;
  int _comments = 0;
  bool _showPlay = false;
  bool _muted = false;

  String get _id => widget.reel['id'] as String;
  String get _uid => AuthService.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _initialize();
    _loadInteractions();
  }

  Future<void> _initialize() async {
    final url = widget.reel['media_url'] as String;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 25));
      await controller.setLooping(true);
      await controller.setVolume(1);
      if (widget.isActive) { await controller.play(); } else { await controller.pause(); }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      await controller.dispose();
      if (identical(_video, controller)) _video = null;
    }
  }

  Future<void> _toggleMute() async {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    final nextMuted = !_muted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => _muted = nextMuted);
  }

  @override
  void didUpdateWidget(covariant _ReelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      final controller = _video;
      if (widget.isActive) {
        if (controller == null) { _initialize(); }
        else if (controller.value.isInitialized) { controller.play(); }
      } else if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }
    }
  }

  Future<void> _loadInteractions() async {
    try {
      final client = AuthService.client;
      final likes = await client.from('post_likes').select('user_id').eq('post_id', _id);
      final comments = await client.from('post_comments').select('id').eq('post_id', _id);
      final myLike = await client.from('post_likes').select('post_id')
          .eq('post_id', _id).eq('user_id', _uid).maybeSingle();
      if (!mounted) return;
      setState(() {
        _likes = likes.length;
        _comments = comments.length;
        _liked = myLike != null;
      });
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final query = AuthService.client.from('post_likes');
      if (_liked) {
        await query.delete().eq('post_id', _id).eq('user_id', _uid);
      } else {
        await query.insert({'post_id': _id, 'user_id': _uid});
      }
      if (mounted) setState(() {
        _liked = !_liked;
        _likes += _liked ? 1 : -1;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.feedCommentLikeFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePlayback() {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
      setState(() => _showPlay = true);
    } else {
      controller.play();
      setState(() => _showPlay = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _video?.pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _video?.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _openComments() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostCommentsScreen(postId: _id),
    ));
    _loadInteractions();
  }

  Future<void> _openProfile() {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PublicProfileScreen(userId: widget.reel['author_id'] as String),
    ));
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(text:  '${_t.reelsShareTitle}\n${widget.reel['caption'] ?? ''}'));
  }

  Future<void> _reportReel() async {
    final reasons = <String, String>{
      'harassment': _t.feedReportHarassment,
      'copied_content': _t.feedReportCopied,
      'copyright_claim': _t.feedReportCopyright,
      'violence': _t.feedReportViolence,
      'inappropriate': _t.feedReportInappropriate,
      'political_insult': _t.feedReportPolitical,
      'illegal_content': _t.feedReportIllegal,
      'spam': _t.feedReportSpam,
      'other': _t.feedReportOther,
    };
    String? reason, rightsOwner;
    final details = TextEditingController();
    final rightsHolder = TextEditingController();
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_t.reelsReportTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(_t.feedReportInstructions),
            ...reasons.entries.map((entry) => RadioListTile<String>(
              dense: true, contentPadding: EdgeInsets.zero,
              value: entry.key, groupValue: reason, title: Text(entry.value),
              onChanged: (value) => update(() {
                reason = value;
                if (value != 'copyright_claim') rightsOwner = null;
              }),
            )),
            if (reason == 'copyright_claim') ...[
              const Divider(),
              Text(_t.feedCopyrightOwner, style: TextStyle(fontWeight: FontWeight.w800)),
              RadioListTile<String>(dense: true, value: 'self', groupValue: rightsOwner,
                title: Text(_t.feedIAmOwner),
                onChanged: (v) => update(() => rightsOwner = v)),
              RadioListTile<String>(dense: true, value: 'third_party', groupValue: rightsOwner,
                title: Text(_t.feedOtherOwner),
                onChanged: (v) => update(() => rightsOwner = v)),
              if (rightsOwner == 'third_party')
                TextField(controller: rightsHolder, maxLength: 160,
                  decoration: InputDecoration(labelText: _t.feedOwnerName)),
            ],
            TextField(controller: details, maxLength: 1000, minLines: 2, maxLines: 4,
              decoration: InputDecoration(labelText: _t.feedReportDetails, border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: reason == null || (reason == 'copyright_claim' && rightsOwner == null)
                ? null : () => Navigator.pop(ctx, {
                  'reason': reason!, 'details': details.text.trim(),
                  'rights_owner': rightsOwner ?? '',
                  'rights_holder_name': rightsHolder.text.trim(),
                }),
              child: Text(_t.feedSubmitReport),
            ),
          ],
        ))),
      )),
    );
    details.dispose();
    rightsHolder.dispose();
    if (result == null) return;
    try {
      await AuthService.client.from('post_reports').insert({
        'post_id': _id, 'reporter_id': _uid, 'reason': result['reason'],
        'details': (result['details'] ?? '').isEmpty ? null : result['details'],
        'rights_owner': (result['rights_owner'] ?? '').isEmpty ? null : result['rights_owner'],
        'rights_holder_name': (result['rights_holder_name'] ?? '').isEmpty ? null : result['rights_holder_name'],
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.reelsReportSuccess)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.feedReportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _video;
    final author = (widget.reel['author_display_name'] as String?)?.trim();
    final username = widget.reel['author_username'] as String? ?? '';
    final caption = (widget.reel['caption'] as String? ?? '').trim();
    final createdAt = DateTime.tryParse(
      widget.reel['created_at'] as String? ?? '',
    )?.toLocal();
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final avatarUrl = widget.reel['avatar_url'] as String?;

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Estedad', decoration: TextDecoration.none),
      child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (controller != null && controller.value.isInitialized)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayback,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            ),
          )
        else if (_loading)
          Stack(
            fit: StackFit.expand,
            children: [
              if (widget.reel['cover_url'] != null)
                Image.network(
                  widget.reel['cover_url'] as String,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Colors.black),
                ),
              const Center(
                child: CircularProgressIndicator(
                  color: HomaGramTheme.turquoise,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          )
        else
          const Center(
            child: Icon(Icons.video_file_outlined,
              color: Colors.white54, size: 54),
          ),

        // Subtle cinematic contrast keeps controls readable over bright footage.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .42),
                    Colors.transparent,
                    Colors.black.withValues(alpha: .12),
                    Colors.black.withValues(alpha: .78),
                  ],
                  stops: const [0, .25, .55, 1],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          top: safeTop + 10,
          left: 16,
          right: 16,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .34),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: .18)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded,
                      color: HomaGramTheme.turquoise, size: 18),
                    SizedBox(width: 7),
                    Text('HOMAGRAM  /  REELS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
              ),
              const Spacer(),
              if (_showPlay)
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .35),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: .18)),
                  ),
                  child: const Icon(Icons.pause_rounded,
                    color: Colors.white, size: 18),
                ),
            ],
          ),
        ),

        if (_showPlay)
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .42),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .24)),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                size: 48, color: Colors.white),
            ),
          ),

        Positioned(
          left: 14,
          right: 82,
          bottom: safeBottom + 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
                decoration: BoxDecoration(
                  color: const Color(0xD9161C2B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .17),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                HomaGramTheme.turquoise,
                                Color(0xFF8C72FF),
                              ],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF29344B),
                            backgroundImage: avatarUrl == null
                                ? null : NetworkImage(avatarUrl),
                            child: avatarUrl == null
                                ? const Icon(Icons.person_rounded,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _openProfile,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          author == null || author.isEmpty
                                              ? '@$username' : author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      HomaGramVerifiedBadge(
                                        userId: widget.reel['author_id'] as String?,
                                        size: 15,
                                      ),
                                    ],
                                  ),
                                  if (username.isNotEmpty)
                                    Text(
                                      '@$username',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (widget.reel['is_mine'] != true)
                          OutlinedButton(
                            onPressed: _openProfile,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: .55),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 7,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _t.reelsViewProfile,
                              style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        caption,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.55,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.movie_creation_outlined,
                          size: 13, color: HomaGramTheme.turquoise),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            createdAt == null
                                ? 'HomaGram Reels'
                                : 'HomaGram Reels  •  ${persianDateTime(createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          right: 11,
          top: safeTop + 104,
          bottom: safeBottom + 190,
          child: Align(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              _action(
                Icons.favorite_rounded,
                _likes.toString(),
                color: _liked ? Colors.pinkAccent : Colors.white,
                onTap: _toggleLike,
              ),
              const SizedBox(height: 17),
              _action(
                Icons.mode_comment_rounded,
                _comments.toString(),
                onTap: _openComments,
              ),
              const SizedBox(height: 17),
              _action(
                Icons.share_rounded,
                _t.reelsShare,
                onTap: _share,
              ),
              const SizedBox(height: 17),
              _action(
                Icons.flag_outlined,
                _t.reelsReport,
                onTap: _reportReel,
              ),
              const SizedBox(height: 17),
              _action(
                _showPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
                _showPlay ? 'پخش' : 'توقف',
                onTap: _togglePlayback,
              ),
              const SizedBox(height: 17),
              _action(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                _muted ? 'بی‌صدا' : 'صدا',
                onTap: _toggleMute,
              ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _action(
    IconData icon,
    String label, {
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .38),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
