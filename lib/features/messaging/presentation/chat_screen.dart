import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';
import '../../home/presentation/shared_post_screen.dart';
import '../../home/presentation/public_profile_screen.dart';
import '../../../core/utils/persian_date.dart';
import '../../../l10n/generated/app_localizations.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  RealtimeChannel? _presenceChannel;
  String _presenceLabel = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _replyToId;
  String? _replyToBody;
  String? _peerUserId;
  String? _peerAvatarUrl;
  String? _peerDisplayName;
  String _conversationKind = 'direct';
  String? _conversationPhotoUrl;
  String _myConversationRole = 'member';
  bool _membersCanSendMessages = true;
  bool _membersCanSendMedia = true;

  bool get _canSendText => _conversationKind != 'group' ||
      _myConversationRole != 'member' || _membersCanSendMessages;
  bool get _canSendMedia => _conversationKind != 'group' ||
      _myConversationRole != 'member' || _membersCanSendMedia;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadPeerIdentity();
    _loadConversationMetadata();
    _channel = MessagingService.watchConversation(widget.conversationId, _refresh);
    _presenceChannel = MessagingService.watchPresence(_refreshPresence);
    _refreshPresence();
  }

  Future<void> _loadConversationMetadata() async {
    try {
      final row = await Supabase.instance.client
          .from('conversations')
          .select('kind,photo_path,description,is_public,public_slug,members_can_send_messages,members_can_send_media')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (row == null) return;
      final path = row['photo_path'] as String?;
      String? photoUrl;
      if (path != null && path.isNotEmpty) {
        photoUrl = await Supabase.instance.client.storage
            .from('conversation-photos').createSignedUrl(path, 3600);
      }
      var myRole = 'member';
      try {
        final membership = await Supabase.instance.client
            .from('conversation_members')
            .select('role')
            .eq('conversation_id', widget.conversationId)
            .eq('user_id', _myId)
            .isFilter('left_at', null)
            .maybeSingle();
        myRole = membership?['role'] as String? ?? 'member';
      } catch (error) {
        debugPrint('Conversation role load failed: $error');
      }
      if (!mounted) return;
      setState(() {
        _conversationKind = row['kind'] as String? ?? 'direct';
        _conversationPhotoUrl = photoUrl;
        _myConversationRole = myRole;
        _membersCanSendMessages = row['members_can_send_messages'] as bool? ?? true;
        _membersCanSendMedia = row['members_can_send_media'] as bool? ?? true;
      });
    } catch (error) {
      debugPrint('Conversation metadata unavailable: $error');
    }
  }

  Future<void> _loadPeerIdentity() async {
    try {
      final profile = await MessagingService.loadDirectPeerProfile(widget.conversationId);
      if (!mounted || profile == null) return;
      final displayName = (profile['display_name'] as String?)?.trim();
      final username = (profile['username'] as String?)?.trim();
      setState(() {
        _peerUserId = profile['id'] as String?;
        _peerAvatarUrl = profile['avatar_url'] as String?;
        _peerDisplayName = displayName != null && displayName.isNotEmpty
            ? displayName
            : username == null || username.isEmpty ? null : '@$username';
      });
    } catch (error) {
      debugPrint('Direct peer profile load failed: $error');
    }
  }

  void _openPeerProfile() {
    final userId = _peerUserId;
    if (userId == null || _conversationKind != 'direct') return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PublicProfileScreen(userId: userId),
    ));
  }

  Future<void> _refresh() async {
    try {
      final messages = await MessagingService.loadMessages(widget.conversationId);
      await MessagingService.markConversationRead(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t.messagesLoadFailed;
      });
    }
  }




  String _documentMime(String extension) {
    switch (extension) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'csv': return 'text/csv';
      case 'txt': return 'text/plain';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _searchMessages() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t.searchMessages),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: _t.minimumTwoCharacters)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.search)),
        ],
      ),
    );
    final term = controller.text.trim();
    controller.dispose();
    if (!mounted || term.length < 2) return;
    try {
      final results = await MessagingService.searchMessages(widget.conversationId, term);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: results.isEmpty
                ? Center(child: Text(_t.noMessagesFound))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return ListTile(
                        title: Text(item['body'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_time(item['created_at'] as String?)),
                        onTap: () {
                          Navigator.pop(context);
                          final index = _messages.indexWhere((message) => message['id'] == item['id']);
                          if (index >= 0 && _scrollController.hasClients) {
                            final offset = (_messages.length - 1 - index) * 92.0;
                            _scrollController.animateTo(
                              offset.clamp(0.0, _scrollController.position.maxScrollExtent),
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.messageSearchFailed)),
      );
    }
  }

  Future<void> _pickMedia() async {
    if (!_canSendMedia) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.image_outlined), title: Text(_t.chooseImage), onTap: () => Navigator.pop(context, 'image')),
          ListTile(leading: const Icon(Icons.timer_outlined), title: Text(_t.sendTimedImage), subtitle: Text(_t.viewOnceOnly), onTap: () => Navigator.pop(context, 'timed_image')),
          ListTile(leading: const Icon(Icons.video_library_outlined), title: Text(_t.chooseVideo), onTap: () => Navigator.pop(context, 'video')),
          ListTile(leading: const Icon(Icons.attach_file_rounded), title: Text(_t.chooseFile), onTap: () => Navigator.pop(context, 'file')),
        ]),
      ),
    );
    if (!mounted || choice == null || _sending) return;
    if (choice == 'file') {
      try {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf','doc','docx','xls','xlsx','ppt','pptx','txt','csv','zip'],
          allowMultiple: false,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final picked = result.files.single;
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) throw StateError('File bytes unavailable');
        if (bytes.length > 52428800) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t.fileSizeLimit)),
          );
          return;
        }
        final ext = (picked.extension ?? '').toLowerCase();
        final mime = _documentMime(ext);
        setState(() => _sending = true);
        await MessagingService.sendMediaMessage(
          conversationId: widget.conversationId,
          bytes: bytes,
          fileName: picked.name,
          mimeType: mime,
        );
        await _refresh();
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.fileSendFailed)),
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }
    try {
      final XFile? file = (choice == 'image' || choice == 'timed_image')
          ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88)
          : await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 52428800) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t.mediaSizeLimit)));
        return;
      }
      final ext = file.name.toLowerCase().split('.').last;
      final mime = (choice == 'image' || choice == 'timed_image')
          ? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg')
          : (ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4');
      setState(() => _sending = true);
      await MessagingService.sendMediaMessage(
        conversationId: widget.conversationId,
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
        viewOnce: choice == 'timed_image',
      );
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.mediaSendFailed)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    if (_sending || !_canSendText || _controller.text.trim().isEmpty) return;
    final text = _controller.text;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await MessagingService.sendTextMessage(
        widget.conversationId,
        text,
        replyToId: _replyToId,
      );
      if (mounted) setState(() { _replyToId = null; _replyToBody = null; });
      await _refresh();
    } catch (_) {
      if (mounted) {
        _controller.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.messageSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }


  Widget _messageContent(String body, ColorScheme colors) {
    const marker = 'HOMAGRAM_POST:';
    if (body.startsWith(marker)) {
      final postId = body.substring(marker.length, marker.length + 36).trim();
      if (postId.length == 36 && RegExp(r'^[0-9a-fA-F-]{36}').hasMatch(postId)) {
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SharedPostScreen(postId: postId),
          )),
          child: Container(
            width: 245,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: colors.surface.withValues(alpha: .7),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
            ),
            child: Row(children: [
              Container(width: 42, height: 42,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                  color: colors.primaryContainer),
                child: Icon(Icons.article_rounded, color: colors.primary)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_t.homagramPost, style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text(_t.tapToViewPost, style: TextStyle(fontSize: 11)),
              ])),
              Icon(Icons.open_in_new_rounded, size: 17, color: colors.primary),
            ]),
          ),
        );
      }
    }
    return Text(body, style: TextStyle(color: colors.onSurface, height: 1.6));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    final channel = _channel;
    if (channel != null) MessagingService.removeChannel(channel);
    final presenceChannel = _presenceChannel;
    if (presenceChannel != null) MessagingService.removeChannel(presenceChannel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pinnedMessages = _messages.where((message) =>
      message['is_pinned'] == true && message['deleted_at'] == null).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _conversationKind == 'direct' ? _openPeerProfile : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: colors.primaryContainer,
                    backgroundImage: (_conversationKind == 'direct'
                            ? _peerAvatarUrl
                            : _conversationPhotoUrl) == null
                        ? null
                        : NetworkImage((_conversationKind == 'direct'
                            ? _peerAvatarUrl
                            : _conversationPhotoUrl)!),
                    child: (_conversationKind == 'direct'
                                ? _peerAvatarUrl
                                : _conversationPhotoUrl) == null
                        ? Icon(
                            _conversationKind == 'channel'
                                ? Icons.campaign_outlined
                                : _conversationKind == 'group'
                                    ? Icons.groups_rounded
                                    : Icons.person_rounded,
                            color: colors.onPrimaryContainer,
                            size: 20,
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(
                            _conversationKind == 'direct' && _peerDisplayName != null
                                ? _peerDisplayName!
                                : widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 4),
                          HomaGramVerifiedBadge(userId: _peerUserId, size: 15),
                        ]),
                        if (_presenceLabel.isNotEmpty)
                          Text(_presenceLabel, style: TextStyle(
                            fontSize: 10,
                            color: _presenceLabel == _t.online
                                ? colors.primary : colors.onSurfaceVariant,
                          )),
                      ],
                    ),
                  ),
                  if (_conversationKind == 'direct')
                    Icon(Icons.chevron_right_rounded,
                      size: 18, color: colors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        actions: [
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.starredMessages,
            onPressed: _showStarredMessages,
            icon: const Icon(Icons.star_outline_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.searchMessages,
            onPressed: _searchMessages,
            icon: const Icon(Icons.search_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.conversationInfo,
            onPressed: _showConversationInfo,
            icon: const Icon(Icons.more_vert_rounded),
          )),
        ],
      ),
      body: Column(
        children: [
          if (pinnedMessages.isNotEmpty)
            Material(
              color: colors.primaryContainer.withValues(alpha: .55),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.push_pin_rounded),
                title: Text(_t.pinnedMessage, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                subtitle: Text(pinnedMessages.last['body'] as String? ?? _t.mediaMessage,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${pinnedMessages.length}', style: const TextStyle(fontSize: 11)),
                onTap: () => _showPinnedMessages(pinnedMessages),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? _EmptyChat(kind: _conversationKind)
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[_messages.length - 1 - index];
                              final mine = message['sender_id'] == _myId;
                              final deleted = message['deleted_at'] != null;
                              return Align(
                                alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.sizeOf(context).width * .78,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 9),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(mine ? 18 : 5),
                                      bottomRight: Radius.circular(mine ? 5 : 18),
                                    ),
                                  ),
                                  child: GestureDetector(
                                    onLongPress: () => _messageActions(message),
                                    onHorizontalDragEnd: (details) {
                                      final velocity = details.primaryVelocity ?? 0;
                                      if (velocity > 280 && !deleted) {
                                        setState(() {
                                          _replyToId = message['id'] as String;
                                          _replyToBody = message['body'] as String? ?? '';
                                        });
                                      }
                                    },
                                    child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (message['reply_to_id'] != null)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 7),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: colors.surface.withValues(alpha: .55),
                                            borderRadius: BorderRadius.circular(9),
                                            border: Border(right: BorderSide(color: colors.primary, width: 3)),
                                          ),
                                          child: Text(
                                            _t.replyPrefix(message['reply_to_body'] as String? ?? _t.replyFallback),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                                          ),
                                        ),
                                      if (!deleted && (message['attachments'] as List? ?? []).isNotEmpty)
                                        _attachmentPreview((message['attachments'] as List).first as Map<String, dynamic>),
                                      if (message['forwarded_from_display_name'] != null && !deleted)
                                        Align(alignment: Alignment.centerRight, child: Text(
                                          _t.forwardedFrom(message['forwarded_from_display_name'] as String),
                                          style: TextStyle(fontSize: 10, color: colors.primary, fontWeight: FontWeight.w700),
                                        )),
                                      if (deleted)
                                        Text(_t.messageDeletedBy(message['deleted_by_name'] as String? ?? _t.userFallback),
                                          style: TextStyle(color: colors.onSurfaceVariant, height: 1.6))
                                      else
                                        _messageContent(message['body'] as String? ?? '', colors),
                                      if (!deleted && (message['reactions'] as List? ?? []).isNotEmpty)
                                        _reactionSummary(message),
                                      if (!deleted && (message['is_starred'] == true || message['is_pinned'] == true))
                                        Row(mainAxisSize: MainAxisSize.min, children: [
                                          if (message['is_starred'] == true) const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                          if (message['is_pinned'] == true) const Icon(Icons.push_pin_rounded, size: 13),
                                        ]),
                                      if (message['edited_at'] != null && !deleted)
                                        Text(_t.edited, style: TextStyle(fontSize: 9)),
                                      const SizedBox(height: 3),
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        if (mine)
                                          Icon(
                                            (message['read_count'] as int? ?? 0) > 0 ? Icons.done_all_rounded : Icons.done_rounded,
                                            size: 13,
                                            color: (message['read_count'] as int? ?? 0) > 0 ? colors.primary : colors.onSurfaceVariant,
                                          ),
                                        const SizedBox(width: 4),
                                        Text(_time(message['created_at'] as String?),
                                          style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                                        const SizedBox(width: 6),
                                        Text(_messageDate(message['created_at'] as String?),
                                          style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant)),
                                      ]),
                                    ],
                                  ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: colors.outlineVariant.withValues(alpha: .5))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyToId != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(_t.replyPrefix(_replyToBody ?? _t.replyFallback), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        IconButton(onPressed: () => setState(() { _replyToId = null; _replyToBody = null; }), icon: const Icon(Icons.close, size: 18)),
                      ]),
                    ),
                  if (!_canSendText)
                    Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
                      child: Row(children: [
                        Icon(Icons.lock_outline_rounded, size: 17),
                        SizedBox(width: 8),
                        Expanded(child: Text(_t.adminsOnlyMessaging,
                          style: TextStyle(fontSize: 12))),
                      ]),
                    ),
                  Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _canSendMedia ? _t.addMedia : _t.mediaSendingDisabled,
                    onPressed: _sending || !_canSendMedia ? null : _pickMedia,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: _canSendText,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _canSendText ? _t.writeMessage : _t.messagingDisabled,
                        filled: true,
                        fillColor: colors.surfaceContainerHighest.withValues(alpha: .65),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending || !_canSendText ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }





  Future<void> _refreshPresence() async {
    try {
      final info = await Supabase.instance.client.from('conversations')
          .select('kind').eq('id', widget.conversationId).single();
      final rows = await MessagingService.loadConversationPresence(widget.conversationId);
      final now = DateTime.now().toUtc();
      final online = rows.where((row) {
        final last = DateTime.tryParse(row['last_seen_at'] as String? ?? '');
        return row['is_online'] == true && last != null && now.difference(last).inMinutes < 2;
      }).length;
      String label;
      if (info['kind'] == 'group') {
        label = online > 0 ? _t.onlinePeopleCount('$online') : _t.group;
      } else if (online > 0) {
        label = _t.online;
      } else if (rows.isNotEmpty && rows.first['last_seen_at'] != null) {
        final last = DateTime.tryParse(rows.first['last_seen_at'] as String);
        label = last == null ? _t.offline : _t.lastSeenAt('${last.toLocal().hour.toString().padLeft(2, '0')}:${last.toLocal().minute.toString().padLeft(2, '0')}');
      } else {
        label = _t.offline;
      }
      if (mounted && label != _presenceLabel) setState(() => _presenceLabel = label);
    } catch (_) {}
  }


  Future<void> _showChannelAuditLogs(String conversationId) async {
    var loading = true;
    String? error;
    var logs = <Map<String, dynamic>>[];
    try {
      logs = await MessagingService.loadChannelAuditLogs(conversationId);
      loading = false;
    } catch (_) {
      loading = false;
      error = _t.activityHistoryLoadFailed;;
    }
    if (!mounted) return;

    String actionTitle(String action) {
      switch (action) {
        case 'channel_created': return _t.channelCreated;
        case 'member_added': return _t.memberAdded;
        case 'member_removed': return _t.memberRemoved;
        case 'member_role_changed': return _t.memberRoleChanged;
        case 'channel_permissions_changed': return _t.channelPermissionsChanged;
        case 'channel_details_changed': return _t.channelDetailsChanged;
        case 'ownership_transferred': return _t.ownershipTransferred;
        case 'invite_created': return _t.inviteCreated;
        case 'invite_revoked': return _t.inviteRevoked;
        default: return _t.adminActivity;
      }
    }

    String actionDetail(Map<String, dynamic> row) {
      final metadata = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : <String, dynamic>{};
      final target = row['target_label'] as String?;
      switch (row['action']) {
        case 'member_added': return target == null ? _t.newMemberAddedToChannel : _t.memberAddedToChannel(target);
        case 'member_removed': return target == null ? _t.memberRemovedFromChannel : _t.namedMemberRemovedFromChannel(target);
        case 'member_role_changed':
          return '${metadata['old_role'] ?? '—'} ← ${metadata['new_role'] ?? '—'}';
        case 'ownership_transferred': return target == null ? _t.channelOwnershipTransferred : _t.newChannelOwner(target);
        case 'channel_permissions_changed':
          return _t.textAndMediaPermissions(metadata['members_can_post'] == true ? _t.active : _t.revoked, metadata['members_can_send_media'] == true ? _t.active : _t.revoked);
        case 'invite_created': return _t.inviteValidityAndLimit('${metadata['expires_at'] ?? '—'}', '${metadata['max_uses'] ?? '—'}');
        case 'invite_revoked': return _t.inviteCodeDisabledActivity;
        case 'channel_details_changed':
          return metadata['title'] is String ? _t.channelNameActivity(metadata['title'] as String) : _t.channelDetailsUpdatedActivity;
        case 'channel_created': return _t.channelCreatedActivity;
        default: return '';
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .78,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: Row(children: [
                  Icon(Icons.history_rounded),
                  SizedBox(width: 9),
                  Text(_t.channelActivityHistory,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(child: Text(error))
                        : logs.isEmpty
                            ? Center(child: Text(_t.noAdminActivityYet))
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: logs.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 7),
                                itemBuilder: (ctx, index) {
                                  final row = logs[index];
                                  final date = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
                                  final dateLabel = date == null
                                      ? ''
                                      : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        child: Icon(Icons.manage_history_rounded),
                                      ),
                                      title: Text(actionTitle(row['action'] as String? ?? ''),
                                        style: const TextStyle(fontWeight: FontWeight.w800)),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(actionDetail(row)),
                                          const SizedBox(height: 4),
                                          Text('${row['actor_label'] ?? _t.systemAdmin} • $dateLabel',
                                            style: Theme.of(ctx).textTheme.bodySmall),
                                        ],
                                      ),
                                      isThreeLine: true,
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manageConversationInvites(String conversationId, {required bool isGroup}) async {
    var invites = <Map<String, dynamic>>[];
    var loading = true;
    String? loadError;

    try {
      invites = isGroup
          ? await MessagingService.loadGroupInvites(conversationId)
          : await MessagingService.loadChannelInvites(conversationId);
      loading = false;
    } catch (_) {
      loading = false;
      loadError = _t.inviteCodesLoadFailed;;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> reload() async {
            setSheetState(() { loading = true; loadError = null; });
            try {
              final rows = isGroup
                  ? await MessagingService.loadGroupInvites(conversationId)
                  : await MessagingService.loadChannelInvites(conversationId);
              if (!sheetContext.mounted) return;
              setSheetState(() { invites = rows; loading = false; });
            } catch (_) {
              if (!sheetContext.mounted) return;
              setSheetState(() { loading = false; loadError = _t.listRefreshFailed;; });
            }
          }

          Future<void> createInvite() async {
            final expiryController = TextEditingController(text: '168');
            final usesController = TextEditingController(text: '100');
            final formKey = GlobalKey<FormState>();
            final values = await showDialog<List<int>>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: Text(_t.createNewInviteCode),
                content: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: expiryController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _t.validityHours),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        return number == null || number < 1 || number > 720
                            ? _t.hoursRangeError : null;
                      },
                    ),
                    TextFormField(
                      controller: usesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: _t.maximumUses),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        return number == null || number < 1 || number > 500
                            ? _t.usesRangeError : null;
                      },
                    ),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel)),
                  FilledButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(dialogContext, [
                          int.parse(expiryController.text),
                          int.parse(usesController.text),
                        ]);
                      }
                    },
                    child: Text(_t.createCode),
                  ),
                ],
              ),
            );
            expiryController.dispose();
            usesController.dispose();
            if (values == null || !sheetContext.mounted) return;

            try {
              final token = isGroup
                  ? await MessagingService.createGroupInvite(
                      conversationId, expiresInHours: values[0], maxUses: values[1])
                  : await MessagingService.createChannelInvite(
                conversationId,
                expiresInHours: values[0],
                maxUses: values[1],
              );
              if (!sheetContext.mounted) return;
              await showDialog<void>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  title: Text(_t.inviteCodeReady),
                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isGroup
                        ? _t.inviteLinkExpiryHint
                        : _t.inviteCodeOneTimeHint),
                    const SizedBox(height: 12),
                    SelectableText(
                      isGroup ? 'homagram://group/$token' : token,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: isGroup ? 'homagram://group/$token' : token));
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(_t.inviteCodeCopied)),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(isGroup ? _t.copyInviteLink : _t.copyCode),
                    )),
                  ]),
                  actions: [
                    FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.close)),
                  ],
                ),
              );
              await reload();
            } catch (_) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(_t.inviteCodeCreateFailed)),
                );
              }
            }
          }

          Future<void> revokeInvite(String inviteId) async {
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: Text(_t.revokeInviteCodeTitle),
                content: Text(_t.revokeInviteCodeExplanation),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t.cancel)),
                  FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t.revoke)),
                ],
              ),
            );
            if (confirmed != true || !sheetContext.mounted) return;
            try {
              if (isGroup) {
                await MessagingService.revokeGroupInvite(inviteId);
              } else {
                await MessagingService.revokeChannelInvite(inviteId);
              }
              await reload();
            } catch (_) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text(_t.inviteCodeRevokeFailed)),
                );
              }
            }
          }

          String statusLabel(String status) => switch (status) {
            'active' => _t.active,
            'revoked' => _t.revoked,
            'expired' => _t.expired,
            'exhausted' => _t.limitReached,
            _ => _t.unknown,
          };

          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(isGroup ? _t.manageGroupInviteLinks : _t.manageChannelInviteCodes, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: createInvite,
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(isGroup ? _t.createGroupInviteLink : _t.createChannelInviteCode),
                )),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : loadError != null
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(loadError!),
                            TextButton(onPressed: reload, child: Text(_t.retry)),
                          ]))
                        : invites.isEmpty
                            ? Center(child: Text(_t.noInviteCodesYet))
                            : ListView.separated(
                                itemCount: invites.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, index) {
                                  final invite = invites[index];
                                  final status = invite['invite_status'] as String? ?? '';
                                  final expires = DateTime.tryParse(invite['expires_at'] as String? ?? '');
                                  final expiryText = expires == null
                                      ? _t.expirationUnknown
                                      : _t.expirationLabel(expires.toLocal().toString().substring(0, 16));
                                  return ListTile(
                                    leading: Icon(
                                      status == 'active' ? Icons.key_rounded : Icons.key_off_rounded,
                                      color: status == 'active' ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                                    title: Text(statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    subtitle: Text(_t.usesOfLimit('${invite['use_count']}', '$expiryText')),
                                    trailing: status == 'active'
                                        ? IconButton(
                                            tooltip: _t.revokeTooltip,
                                            onPressed: () => revokeInvite(invite['id'] as String),
                                            icon: const Icon(Icons.block_rounded),
                                          )
                                        : null,
                                  );
                                },
                              ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _showGroupPermissions(
    String conversationId,
    Map<String, dynamic> initial,
  ) async {
    var membersCanSendMessages = initial['members_can_send_messages'] as bool? ?? true;
    var membersCanSendMedia = initial['members_can_send_media'] as bool? ?? true;
    var membersCanAddMembers = initial['members_can_add_members'] as bool? ?? false;
    var adminsCanChangeInfo = initial['admins_can_change_info'] as bool? ?? true;
    var adminsCanManageMembers = initial['admins_can_manage_members'] as bool? ?? true;
    final values = await showDialog<List<bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_t.groupPermissions),
          content: SizedBox(
            width: MediaQuery.sizeOf(dialogContext).width * .82,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(alignment: Alignment.centerRight,
                  child: Text(_t.memberPermissions, style: TextStyle(fontWeight: FontWeight.w900))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t.sendTextMessages),
                  value: membersCanSendMessages,
                  onChanged: (v) => setDialogState(() => membersCanSendMessages = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t.sendImagesFiles),
                  value: membersCanSendMedia,
                  onChanged: (v) => setDialogState(() => membersCanSendMedia = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t.addNewMembers),
                  subtitle: Text(_t.membersCanInviteHint),
                  value: membersCanAddMembers,
                  onChanged: (v) => setDialogState(() => membersCanAddMembers = v),
                ),
                const Divider(height: 22),
                Align(alignment: Alignment.centerRight,
                  child: Text(_t.adminPrivileges, style: TextStyle(fontWeight: FontWeight.w900))),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t.editGroupNameDescriptionPhoto),
                  value: adminsCanChangeInfo,
                  onChanged: (v) => setDialogState(() => adminsCanChangeInfo = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t.manageMembersInviteLinks),
                  value: adminsCanManageMembers,
                  onChanged: (v) => setDialogState(() => adminsCanManageMembers = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, [
                membersCanSendMessages, membersCanSendMedia, membersCanAddMembers,
                adminsCanChangeInfo, adminsCanManageMembers,
              ]),
              child: Text(_t.savePermissions),
            ),
          ],
        ),
      ),
    );
    if (values == null || !mounted) return;
    try {
      await MessagingService.updateGroupPermissions(
        conversationId: conversationId,
        membersCanSendMessages: values[0],
        membersCanSendMedia: values[1],
        membersCanAddMembers: values[2],
        adminsCanChangeInfo: values[3],
        adminsCanManageMembers: values[4],
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.groupPermissionsUpdated)),
      );
    } catch (error) {
      debugPrint('Group permissions update failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.groupPermissionsSaveFailed)),
      );
    }
  }

  Future<void> _showConversationInfo() async {
    try {
      // Fetch the conversation row separately from its optional channel row.
      // A nested PostgREST relationship can fail for group/direct conversations.
      final info = await Supabase.instance.client.from('conversations')
          .select('kind,title,photo_path,description,is_public,public_slug,members_can_send_messages,members_can_send_media,members_can_add_members,admins_can_change_info,admins_can_manage_members')
          .eq('id', widget.conversationId).single();
      final isGroup = info['kind'] == 'group';
      final isChannel = info['kind'] == 'channel';
      var channelData = <String, dynamic>{};
      if (isChannel) {
        try {
          final channelRow = await Supabase.instance.client.from('channels')
              .select('slug,description,is_public,members_can_post,members_can_send_media')
              .eq('conversation_id', widget.conversationId).maybeSingle();
          if (channelRow != null) {
            channelData = Map<String, dynamic>.from(channelRow);
          }
        } catch (error) {
          // Keep the information sheet available even if optional channel
          // settings cannot be loaded for this member/session.
          debugPrint('Channel settings unavailable: $error');
        }
      }
      var members = <Map<String, dynamic>>[];
      try {
        members = await MessagingService.loadConversationMembers(widget.conversationId);
      } catch (error) {
        // A member/profile lookup must not hide the conversation profile.
        debugPrint('Conversation members unavailable: $error');
      }
      String? infoPhotoUrl = _conversationPhotoUrl;
      final photoPath = info['photo_path'] as String?;
      if (photoPath != null && photoPath.isNotEmpty) {
        try {
          infoPhotoUrl = await Supabase.instance.client.storage
              .from('conversation-photos').createSignedUrl(photoPath, 3600);
        } catch (error) {
          debugPrint('Conversation photo URL refresh failed: $error');
        }
      }
      if (mounted && infoPhotoUrl != _conversationPhotoUrl) {
        setState(() => _conversationPhotoUrl = infoPhotoUrl);
      }
      final description = (isChannel
              ? channelData['description']
              : info['description']) as String? ?? '';
      if (!mounted) return;
      String myRole = 'member';
      try {
        final ownMembership = await Supabase.instance.client
            .from('conversation_members')
            .select('role')
            .eq('conversation_id', widget.conversationId)
            .eq('user_id', _myId)
            .isFilter('left_at', null)
            .maybeSingle();
        myRole = ownMembership?['role'] as String? ?? 'member';
      } catch (error) {
        debugPrint('Current conversation role unavailable: $error');
        for (final member in members) {
          if (member['user_id'] == _myId) {
            myRole = member['role'] as String? ?? 'member';
            break;
          }
        }
      }
      final canManage = myRole == 'owner' || myRole == 'admin';
      final canManageMembers = isGroup
          ? myRole == 'owner' || (myRole == 'admin' && info['admins_can_manage_members'] == true)
          : canManage;
      final canChangeInfo = isGroup
          ? myRole == 'owner' || (myRole == 'admin' && info['admins_can_change_info'] == true)
          : canManage;
      final canAddMembers = isGroup
          ? canManageMembers || (myRole == 'member' && info['members_can_add_members'] == true)
          : canManage;

      Future<void> manageMember(String targetId, String action) async {
        if (isChannel) {
          await MessagingService.manageChannelMember(widget.conversationId, targetId, action);
        } else {
          await MessagingService.manageGroupMember(widget.conversationId, targetId, action);
        }
        members = await MessagingService.loadConversationMembers(widget.conversationId);
      }

      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: Theme.of(sheetContext).colorScheme.primaryContainer,
                    backgroundImage: infoPhotoUrl == null ? null : NetworkImage(infoPhotoUrl!),
                    child: infoPhotoUrl == null
                        ? Icon(isChannel ? Icons.campaign_outlined : Icons.groups_rounded)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    (info['title'] as String?) ?? (isChannel ? _t.channel : isGroup ? _t.group : widget.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  )),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if ((isGroup || isChannel) && canChangeInfo)
                    IconButton(
                      tooltip: isChannel ? _t.changeChannelPhoto : _t.changeGroupPhoto,
                      icon: const Icon(Icons.camera_alt_outlined),
                      onPressed: () async {
                        try {
                          final picked = await _picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 88,
                            maxWidth: 1440,
                            maxHeight: 1440,
                          );
                          if (picked == null) return;
                          final extension = picked.name.split('.').last.toLowerCase();
                          final mimeType = switch (extension) {
                            'png' => 'image/png',
                            'webp' => 'image/webp',
                            _ => 'image/jpeg',
                          };
                          final url = await MessagingService.uploadConversationPhoto(
                            conversationId: widget.conversationId,
                            bytes: await picked.readAsBytes(),
                            extension: const ['jpg', 'jpeg', 'png', 'webp'].contains(extension)
                                ? extension : 'jpg',
                            mimeType: mimeType,
                          );
                          if (!mounted) return;
                          infoPhotoUrl = url;
                          setState(() => _conversationPhotoUrl = url);
                          if (sheetContext.mounted) setSheetState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isChannel
                                ? _t.channelPhotoUpdated
                                : _t.groupPhotoUpdated)),
                          );
                        } catch (error) {
                          debugPrint('Conversation photo update failed: $error');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.photoChangeFailed)),
                          );
                        }
                      },
                    ),
                  if (isGroup && myRole == 'owner')
                    IconButton(
                      tooltip: _t.groupPublicSettings,
                      icon: const Icon(Icons.public_rounded),
                      onPressed: () async {
                        final slugController = TextEditingController(text: info['public_slug'] as String? ?? '');
                        final descriptionController = TextEditingController(text: description);
                        var isPublic = info['is_public'] == true;
                        final values = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (dialogContext) => StatefulBuilder(
                            builder: (dialogContext, setDialogState) => AlertDialog(
                              title: Text(_t.groupDiscoverability),
                              content: SingleChildScrollView(child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: isPublic,
                                    onChanged: (value) => setDialogState(() => isPublic = value),
                                    title: Text(isPublic ? _t.publicGroup : _t.privateGroup),
                                    subtitle: Text(isPublic
                                      ? _t.groupPublicDiscoverable
                                      : _t.groupPrivateAccessHint),
                                  ),
                                  if (isPublic) ...[
                                    TextField(
                                      controller: slugController,
                                      maxLength: 32,
                                      textDirection: TextDirection.ltr,
                                      decoration: InputDecoration(
                                        labelText: _t.publicId,
                                        prefixText: '@',
                                        helperText: _t.publicIdHelper,
                                      ),
                                    ),
                                    TextField(
                                      controller: descriptionController,
                                      maxLength: 500,
                                      maxLines: 3,
                                      decoration: InputDecoration(labelText: _t.publicDescription),
                                    ),
                                  ],
                                ],
                              )),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel)),
                                FilledButton(
                                  onPressed: () {
                                    if (isPublic && !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(slugController.text.trim())) {
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        SnackBar(content: Text(_t.publicIdRulesError)),
                                      );
                                      return;
                                    }
                                    Navigator.pop(dialogContext, {
                                      'isPublic': isPublic,
                                      'slug': slugController.text,
                                      'description': descriptionController.text,
                                    });
                                  },
                                  child: Text(_t.save),
                                ),
                              ],
                            ),
                          ),
                        );
                        slugController.dispose();
                        descriptionController.dispose();
                        if (values == null) return;
                        try {
                          await MessagingService.updateGroupDiscoverySettings(
                            conversationId: widget.conversationId,
                            isPublic: values['isPublic'] as bool,
                            slug: values['slug'] as String,
                            description: values['description'] as String,
                          );
                          await _loadConversationMetadata();
                          if (mounted) setState(() {});
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(values['isPublic'] == true
                              ? _t.groupPublishedToDiscovery
                              : _t.groupRemovedFromDiscovery)),
                          );
                        } catch (_) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.groupPublicSettingsSaveFailed)),
                          );
                        }
                      },
                    ),
                  if ((isGroup || isChannel) && canChangeInfo)
                    IconButton(
                      tooltip: isChannel ? _t.editChannelDetails : _t.editGroupInfo,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final titleController = TextEditingController(text: info['title'] as String? ?? '');
                        final slugController = TextEditingController(text: channelData['slug'] as String? ?? '');
                        final descriptionController = TextEditingController(text: description);
                        final values = await showDialog<List<String>>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isChannel ? _t.channelInfo : _t.groupInfo),
                            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(controller: titleController, maxLength: 100,
                                decoration: InputDecoration(labelText: _t.name)),
                              if (isChannel)
                                TextField(controller: slugController, maxLength: 32,
                                  decoration: InputDecoration(labelText: _t.identifier, prefixText: '@')),
                              TextField(controller: descriptionController, maxLength: 500, maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: _t.description,
                                  hintText: _t.writeAboutGroupChannel,
                                )),
                            ])),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.cancel)),
                              FilledButton(onPressed: () => Navigator.pop(ctx, [
                                titleController.text, slugController.text, descriptionController.text,
                              ]), child: Text(_t.save)),
                            ],
                          ),
                        );
                        titleController.dispose();
                        slugController.dispose();
                        descriptionController.dispose();
                        if (values == null || values[0].trim().isEmpty) return;
                        if (isChannel) {
                          if (!RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(values[1].trim())) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_t.publicIdRulesError)),
                            );
                            return;
                          }
                          await MessagingService.updateChannelDetails(
                            conversationId: widget.conversationId,
                            title: values[0], slug: values[1], description: values[2],
                          );
                        } else {
                          await MessagingService.updateGroupDetails(
                            conversationId: widget.conversationId,
                            title: values[0],
                            description: values[2],
                          );
                        }
                        if (mounted) setState(() {});
                        await _loadConversationMetadata();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  if (isChannel && canManage)
                    IconButton(
                      tooltip: _t.memberPermissionSettings,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () async {
                        var canPost = channelData['members_can_post'] as bool? ?? true;
                        var canSendMedia = channelData['members_can_send_media'] as bool? ?? true;
                        final values = await showDialog<List<bool>>(
                          context: context,
                          builder: (dialogContext) => StatefulBuilder(
                            builder: (dialogContext, setDialogState) => AlertDialog(
                              title: Text(_t.regularMemberPermissions),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_t.sendTextMessages),
                                  subtitle: Text(_t.regularMembersCanSendText),
                                  value: canPost,
                                  onChanged: (value) => setDialogState(() => canPost = value),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_t.sendMediaFiles),
                                  subtitle: Text(_t.regularMembersCanSendMedia),
                                  value: canSendMedia,
                                  onChanged: (value) => setDialogState(() => canSendMedia = value),
                                ),
                                const SizedBox(height: 4),
                                Text(_t.channelAdminsAlwaysCanSend,
                                  style: TextStyle(fontSize: 12)),
                              ]),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel)),
                                FilledButton(onPressed: () => Navigator.pop(dialogContext, [canPost, canSendMedia]),
                                  child: Text(_t.saveSettings)),
                              ],
                            ),
                          ),
                        );
                        if (values == null) return;
                        try {
                          await MessagingService.updateChannelMemberPermissions(
                            conversationId: widget.conversationId,
                            membersCanPost: values[0],
                            membersCanSendMedia: values[1],
                          );
                          channelData['members_can_post'] = values[0];
                          channelData['members_can_send_media'] = values[1];
                          if (sheetContext.mounted) setSheetState(() {});
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.memberPermissionsUpdated)),
                          );
                        } catch (_) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.memberPermissionsSaveFailed)),
                          );
                        }
                      },
                    ),
                  if (isChannel && canManage)
                    IconButton(
                      tooltip: _t.channelActivityHistory,
                      icon: const Icon(Icons.history_rounded),
                      onPressed: () => _showChannelAuditLogs(widget.conversationId),
                    ),
                  if ((isChannel && canManage && channelData['is_public'] == false) ||
                      (isGroup && canManageMembers))
                    IconButton(
                      tooltip: isGroup ? _t.manageGroupInviteLinks : _t.manageChannelInviteCodes,
                      icon: const Icon(Icons.key_rounded),
                      onPressed: () => _manageConversationInvites(
                        widget.conversationId, isGroup: isGroup,
                      ),
                    ),
                  if (isGroup && myRole == 'owner')
                    IconButton(
                      tooltip: _t.groupPermissions,
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () => _showGroupPermissions(widget.conversationId, info),
                    ),
                  if ((isGroup || isChannel) && canAddMembers)
                    IconButton(
                      tooltip: _t.addMember, icon: const Icon(Icons.person_add_alt_1_rounded),
                      onPressed: () async {
                        final queryController = TextEditingController();
                        final query = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(_t.addMember),
                            content: TextField(controller: queryController, autofocus: true,
                              decoration: InputDecoration(hintText: _t.username)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.cancel)),
                              FilledButton(onPressed: () => Navigator.pop(ctx, queryController.text),
                                child: Text(_t.search)),
                            ],
                          ),
                        );
                        queryController.dispose();
                        if (query == null || query.trim().length < 2) return;
                        final users = await MessagingService.searchUsers(query);
                        if (!mounted) return;
                        final selected = await showModalBottomSheet<Map<String, dynamic>>(
                          context: context, showDragHandle: true,
                          builder: (ctx) => ListView(
                            shrinkWrap: true,
                            children: users.map((user) => ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                              title: Text(user['display_name'] as String? ?? user['username'] as String),
                              subtitle: Text('@${user['username']}'),
                              onTap: () => Navigator.pop(ctx, user),
                            )).toList(),
                          ),
                        );
                        if (selected == null) return;
                        try {
                          await manageMember(selected['id'] as String, 'add');
                          if (sheetContext.mounted) setSheetState(() {});
                        } catch (error) {
                          debugPrint('Add conversation member failed: $error');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.addMemberFailed)),
                          );
                        }
                      },
                    ),

                    ]),
                  ),
                ),
              ),
              if (description.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      description,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (ctx, index) {
                    final member = members[index];
                    final role = member['role'] as String? ?? 'member';
                    final isMe = member['user_id'] == _myId;
                    final canAct = (isGroup || isChannel) && !isMe &&
                        ((myRole == 'owner' && role != 'owner') ||
                         (myRole == 'admin' && role == 'member' &&
                          (!isGroup || info['admins_can_manage_members'] == true)));
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                      title: Text(member['display_name'] as String? ?? ''),
                      subtitle: Text('@${member['username']} • ${role == 'owner' ? _t.owner : role == 'admin' ? _t.admin : _t.member}'),
                      trailing: canAct
                          ? PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'transfer') {
                                  final displayName = member['display_name'] as String? ?? member['username'] as String? ?? _t.thisMember;
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: Text(_t.transferChannelOwnership),
                                      content: Text(_t.transferOwnershipConfirm(displayName)),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t.cancel)),
                                        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t.confirmTransfer)),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  try {
                                    await MessagingService.transferChannelOwnership(
                                      conversationId: widget.conversationId,
                                      newOwnerUserId: member['user_id'] as String,
                                    );
                                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_t.channelOwnershipTransferredSuccess)),
                                    );
                                  } catch (_) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_t.ownershipTransferFailed)),
                                    );
                                  }
                                  return;
                                }
                                try {
                                  await manageMember(member['user_id'] as String, action);
                                  if (sheetContext.mounted) setSheetState(() {});
                                } catch (error) {
                                  debugPrint('Group member action failed: $error');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(_t.memberActionFailed)),
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                if (myRole == 'owner' && role == 'member')
                                  PopupMenuItem(value: 'promote', child: Text(_t.promoteToAdmin)),
                                if (myRole == 'owner' && role == 'admin')
                                  PopupMenuItem(value: 'demote', child: Text(_t.demoteToMember)),
                                if (isChannel && myRole == 'owner' && role != 'owner')
                                  PopupMenuItem(value: 'transfer', child: Text(_t.transferChannelOwnershipMenu)),
                                if (role != 'owner' && (myRole == 'owner' || role == 'member'))
                                  PopupMenuItem(value: 'remove', child: Text(isChannel ? _t.removeFromChannel : _t.removeFromGroup)),
                              ],
                            )
                          : role == 'owner' ? const Icon(Icons.verified_rounded, size: 18) : null,
                    );
                  },
                ),
              ),
              if ((isGroup || isChannel) && myRole == 'owner')
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(sheetContext).colorScheme.error,
                        side: BorderSide(color: Theme.of(sheetContext).colorScheme.error.withValues(alpha: .55)),
                      ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: Text(isGroup ? _t.deleteGroupForEveryone : _t.deleteChannelForEveryone),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: Text(isGroup ? _t.deleteGroup : _t.deleteChannel),
                            content: Text(
                              _t.deleteCommunityConfirm(isGroup ? _t.group : _t.channelInfo),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, false),
                                child: Text(_t.cancel),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                                ),
                                onPressed: () => Navigator.pop(dialogContext, true),
                                child: Text(_t.deleteForEveryone),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await MessagingService.deleteOwnedCommunity(widget.conversationId);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted) Navigator.pop(context);
                        } catch (error) {
                          debugPrint('Delete owned community failed: $error');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_t.deleteCommunityFailed)),
                          );
                        }
                      },
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: () async {
                      await MessagingService.leaveConversation(widget.conversationId);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(isChannel ? _t.leaveChannel : isGroup ? _t.leaveGroup : _t.leaveConversation),
                  )),
                ),
              ),
            ]),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Conversation info sheet failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.conversationInfoLoadFailed)),
      );
    }
  }

  Future<Uint8List?> _downloadAttachmentBytes(Map<String, dynamic> attachment) async {
    final path = attachment['storage_path'] as String?;
    if (path == null || path.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.filePathUnavailable)),
      );
      return null;
    }
    return Supabase.instance.client.storage.from('chat-media').download(path);
  }

  Future<void> _downloadImageAttachment(Map<String, dynamic> attachment) async {
    try {
      final bytes = await _downloadAttachmentBytes(attachment);
      if (bytes == null) return;
      await Gal.putImageBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.imageSavedToGallery)),
      );
    } catch (error) {
      debugPrint('Save chat image failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.imageSaveFailed)),
      );
    }
  }

  Future<void> _downloadVideoAttachment(Map<String, dynamic> attachment) async {
    try {
      final bytes = await _downloadAttachmentBytes(attachment);
      if (bytes == null) return;
      final name = (attachment['file_name'] as String?)?.trim();
      final fileName = name == null || name.isEmpty ? 'HomaGram-video.mp4' : name;
      final savedPath = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.videoSaved)),
      );
    } catch (error) {
      debugPrint('Save chat video failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.videoDownloadFailed)),
      );
    }
  }

  Future<void> _downloadFileAttachment(Map<String, dynamic> attachment) async {
    try {
      final bytes = await _downloadAttachmentBytes(attachment);
      if (bytes == null) return;
      final name = (attachment['file_name'] as String?)?.trim();
      final fileName = name == null || name.isEmpty ? 'HomaGram-file' : name;
      final savedPath = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.fileSaved)),
      );
    } catch (error) {
      debugPrint('Save chat file failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.fileDownloadFailed)),
      );
    }
  }

  Future<void> _openTimedImage(Map<String, dynamic> attachment) async {
    var protectionEnabled = false;
    try {
      await ScreenProtector.preventScreenshotOn();
      protectionEnabled = true;
      if (Platform.isAndroid) {
        await ScreenProtector.protectDataLeakageOn();
      } else if (Platform.isIOS) {
        await ScreenProtector.protectDataLeakageWithBlur();
      }
      final response = await Supabase.instance.client.rpc(
        'open_timed_image',
        params: {'p_attachment_id': attachment['id']},
      );
      final row = (response as List).cast<Map<String, dynamic>>().first;
      final path = row['storage_path'] as String;
      final expiresAt = DateTime.parse(row['expires_at'] as String).toUtc();
      final bytes = await Supabase.instance.client.storage.from('chat-media').download(path);
      if (!mounted) return;
      final remaining = expiresAt.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) {
        throw StateError('Timed image expired before it could be displayed.');
      }
      Timer? countdown;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(builder: (context, updateDialog) {
            var seconds = remaining.inSeconds + (remaining.inMilliseconds % 1000 == 0 ? 0 : 1);
            countdown ??= Timer.periodic(const Duration(milliseconds: 200), (timer) {
              final left = expiresAt.difference(DateTime.now().toUtc());
              if (left <= Duration.zero) {
                timer.cancel();
                if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
              } else {
                updateDialog(() {});
              }
            });
            seconds = expiresAt.difference(DateTime.now().toUtc()).inSeconds +
                (expiresAt.difference(DateTime.now().toUtc()).inMilliseconds % 1000 == 0 ? 0 : 1);
            return PopScope(
              canPop: false,
              child: Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Center(child: Image.memory(
                        bytes, fit: BoxFit.contain,
                        gaplessPlayback: false,
                        errorBuilder: (_, __, ___) => Text(_t.imageCannotDisplay, style: TextStyle(color: Colors.white)),
                      )),
                      Positioned(
                        top: 12, right: 16,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(22)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Text(_t.secondsRemaining('$seconds'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4, left: 4,
                        child: IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          tooltip: _t.closeImage,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      );
      countdown?.cancel();
    } catch (error) {
      debugPrint('Open timed image failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.timedImageUnavailable)),
        );
      }
    } finally {
      if (protectionEnabled) {
        try {
          if (Platform.isAndroid) {
            await ScreenProtector.protectDataLeakageOff();
          } else if (Platform.isIOS) {
            await ScreenProtector.protectDataLeakageWithBlurOff();
          }
          await ScreenProtector.preventScreenshotOff();
        } catch (error) {
          debugPrint('Disable screen protection failed: $error');
        }
      }
    }
  }

  Widget _attachmentPreview(Map<String, dynamic> attachment) {
    final url = attachment['signed_url'] as String?;
    final mime = attachment['mime_type'] as String? ?? '';
    if (attachment['is_view_once'] == true) {
      return Container(
        width: 230, padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(children: [
          const Icon(Icons.timer_rounded, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t.timedImage, style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 3),
              Text(_t.viewOnce10Seconds, style: TextStyle(fontSize: 10)),
            ],
          )),
          if (attachment['uploader_id'] == Supabase.instance.client.auth.currentUser?.id)
            const Icon(Icons.lock_outline_rounded)
          else if (attachment['viewed_by_me'] == true)
            Tooltip(message: _t.alreadyViewed, child: Icon(Icons.check_circle_outline_rounded))
          else
            IconButton(
              tooltip: _t.viewImage,
              onPressed: () => _openTimedImage(attachment),
              icon: const Icon(Icons.visibility_rounded),
            ),
        ]),
      );
    }
    if (url == null) return Padding(padding: EdgeInsets.all(8), child: Text(_t.mediaUnavailable));
    if (mime.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.network(url, width: 230, height: 190, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 230, height: 90, child: Center(child: Icon(Icons.broken_image_outlined)))),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: .62),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _t.downloadImage,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                    padding: EdgeInsets.zero,
                    onPressed: () => _downloadImageAttachment(attachment),
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 21),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (mime.startsWith('video/')) return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          _VideoMessagePreview(url: url),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: .62),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: _t.downloadVideo,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                padding: EdgeInsets.zero,
                onPressed: () => _downloadVideoAttachment(attachment),
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 21),
              ),
            ),
          ),
        ],
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.attach_file_rounded), const SizedBox(width: 6),
      Flexible(child: Text(attachment['file_name'] as String? ?? _t.file)),
      const SizedBox(width: 6),
      IconButton(
        tooltip: _t.downloadFile,
        visualDensity: VisualDensity.compact,
        onPressed: () => _downloadFileAttachment(attachment),
        icon: const Icon(Icons.download_rounded),
      ),
    ]);
  }

  Widget _reactionSummary(Map<String, dynamic> message) {
    final reactions = (message['reactions'] as List? ?? []).cast<Map<String, dynamic>>();
    final counts = <String, int>{};
    for (final reaction in reactions) {
      final emoji = reaction['emoji'] as String? ?? '';
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 4, children: counts.entries.map((entry) => ActionChip(
        visualDensity: VisualDensity.compact,
        label: Text('${entry.key} ${entry.value}', style: const TextStyle(fontSize: 11)),
        onPressed: () async {
          await MessagingService.toggleReaction(message['id'] as String, entry.key);
          await _refresh();
        },
      )).toList()),
    );
  }

  Future<void> _messageActions(Map<String, dynamic> message) async {
    if (message['deleted_at'] != null) return;
    final mine = message['sender_id'] == _myId;
    final createdAt = DateTime.tryParse(message['created_at'] as String? ?? '');
    final canEdit = mine && createdAt != null &&
        DateTime.now().difference(createdAt) <= const Duration(hours: 2);
    final canModerate = _conversationKind == 'direct' ||
        mine || _myConversationRole == 'owner' || _myConversationRole == 'admin';
    final canPin = _conversationKind == 'direct' ||
        _myConversationRole == 'owner' || _myConversationRole == 'admin';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(message['is_starred'] == true ? Icons.star_rounded : Icons.star_border_rounded),
              title: Text(message['is_starred'] == true ? _t.starredRemove : _t.starMessage),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            if (canPin) ListTile(
              leading: Icon(message['is_pinned'] == true ? Icons.push_pin_rounded : Icons.push_pin_outlined),
              title: Text(message['is_pinned'] == true ? _t.unpinMessage : _t.pinMessage),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(_t.copyMessageText),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (message['message_type'] == 'text')
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: Text(_t.forwardToConversation),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text(_t.replyToMessage),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              children: ['👍', '❤️', '😂', '😮', '😢', '🔥'].map((emoji) =>
                TextButton(
                  onPressed: () => Navigator.pop(context, 'reaction:$emoji'),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ).toList(),
            ),
            if (canEdit) ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(_t.editMessage),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            if (canModerate) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: Text(_t.deleteForEveryone, style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            if (!mine) ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: Text(_t.reportThisMessage),
              subtitle: Text(_t.privateAdminReview),
              onTap: () => Navigator.pop(context, 'report'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'star') {
        await MessagingService.toggleMessageStar(message['id'] as String);
        await _refresh();
      } else if (action == 'pin') {
        if (message['is_pinned'] == true) {
          await MessagingService.unpinMessage(message['id'] as String);
        } else {
          await MessagingService.pinMessage(message['id'] as String);
        }
        await _refresh();
      } else if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: message['body'] as String? ?? ''));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.messageTextCopied)));
      } else if (action == 'forward') {
        final conversations = await MessagingService.loadInbox();
        final targets = conversations.where((item) => item.id != widget.conversationId).toList();
        final targetId = await showModalBottomSheet<String>(
          context: context, showDragHandle: true,
          builder: (sheetContext) => SafeArea(child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .6,
            child: targets.isEmpty
              ? Center(child: Text(_t.noOtherConversationsToForward))
              : ListView.builder(
                  itemCount: targets.length,
                  itemBuilder: (context, index) {
                    final target = targets[index];
                    return ListTile(
                      leading: Icon(target.kind == 'group' ? Icons.groups_outlined :
                        target.kind == 'channel' ? Icons.campaign_outlined : Icons.person_outline),
                      title: Text(target.title),
                      onTap: () => Navigator.pop(sheetContext, target.id),
                    );
                  },
                ),
          )),
        );
        if (targetId != null) {
          await MessagingService.forwardTextMessage(message['id'] as String, targetId);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t.messageForwarded)));
        }
      } else if (action == 'reply') {
        setState(() {
          _replyToId = message['id'] as String;
          _replyToBody = message['body'] as String? ?? '';
        });
      } else if (action.startsWith('reaction:')) {
        await MessagingService.toggleReaction(message['id'] as String, action.substring(9));
        await _refresh();
      } else if (action == 'edit') {
        final controller = TextEditingController(text: message['body'] as String? ?? '');
        final updated = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_t.editMessage),
            content: TextField(controller: controller, autofocus: true, maxLines: 5, maxLength: 10000),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(_t.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(_t.save)),
            ],
          ),
        );
        controller.dispose();
        if (updated != null) {
          await MessagingService.editMessage(message['id'] as String, updated);
          await _refresh();
        }
      } else if (action == 'report') {
        final reason = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: EdgeInsets.all(16),
                child: Text(_t.messageReportReason, style: TextStyle(fontWeight: FontWeight.w900))),
              for (final item in [
                ('spam',_t.spamOrAds),
                ('harassment',_t.harassment),
                ('threat',_t.threatOrDangerousContent),
                ('privacy',_t.privacyViolation),
                ('inappropriate',_t.inappropriateContent),
                ('other',_t.other),
              ])
                ListTile(title: Text(item.$2), onTap: () => Navigator.pop(sheetContext, item.$1)),
            ],
          )),
        );
        if (reason != null) {
          final detailsController = TextEditingController();
          final details = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(_t.additionalDetails),
              content: TextField(controller: detailsController, maxLength: 1000,
                minLines: 2, maxLines: 5, decoration: InputDecoration(
                  hintText: _t.optionalShortExplanation)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: Text(_t.skip)),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, detailsController.text.trim()),
                  child: Text(_t.submitReport)),
              ],
            ),
          );
          detailsController.dispose();
          if (details != null) {
            await Supabase.instance.client.rpc('report_message', params: {
              'p_message_id': message['id'],
              'p_reason': reason,
              'p_details': details.isEmpty ? null : details,
            });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_t.reportSubmitted)));
          }
        }
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_t.deleteMessage),
            content: Text(_t.deleteMessageForEveryoneConfirm),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t.delete)),
            ],
          ),
        );
        if (confirmed == true) {
          await MessagingService.deleteMessage(message['id'] as String);
          await _refresh();
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.actionFailedRetry)),
        );
      }
    }
  }

  Future<void> _showPinnedMessages(List<Map<String, dynamic>> pinned) async {
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .55,
        child: ListView.separated(
          itemCount: pinned.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final message = pinned[index];
            return ListTile(
              leading: const Icon(Icons.push_pin_rounded),
              title: Text(message['body'] as String? ?? _t.mediaMessage,
                maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(_time(message['created_at'] as String?)),
            );
          },
        ),
      )),
    );
  }

  Future<void> _showStarredMessages() async {
    try {
      final rows = await MessagingService.loadStarredMessages(widget.conversationId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheetContext) => SafeArea(child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: rows.isEmpty ? Center(child: Text(_t.noStarredMessagesYet))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final message = rows[index]['messages'] as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.star_rounded, color: Colors.amber),
                    title: Text(message['body'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_time(message['created_at'] as String?)),
                  );
                },
              ),
        )),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.starredMessagesLoadFailed)));
    }
  }

  String _messageDate(String? value) {
    final date = value == null ? null : DateTime.tryParse(value)?.toLocal();
    return date == null ? '' : persianDate(date);
  }

  String _time(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final _t = AppLocalizations.of(context)!;
    final isChannel = kind == 'channel';
    final isGroup = kind == 'group';
    final title = isChannel
        ? _t.channelNoPostsYet
        : isGroup ? _t.groupNoMessagesYet : _t.startConversation;
    final subtitle = isChannel
        ? _t.channelFirstPostHint
        : isGroup ? _t.groupFirstMessageHint : _t.conversationFirstMessageHint;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isChannel ? Icons.campaign_outlined : isGroup ? Icons.groups_outlined : Icons.forum_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _VideoMessagePreview extends StatefulWidget {
  const _VideoMessagePreview({required this.url});
  final String url;
  @override
  State<_VideoMessagePreview> createState() => _VideoMessagePreviewState();
}

class _VideoMessagePreviewState extends State<_VideoMessagePreview> {
  late final VideoPlayerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const SizedBox(width: 230, height: 130, child: Center(child: CircularProgressIndicator()));
    }
    return GestureDetector(
      onTap: () {
        if (_controller.value.isPlaying) { _controller.pause(); } else { _controller.play(); }
        setState(() {});
      },
      child: SizedBox(width: 230, child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(_controller),
          if (!_controller.value.isPlaying)
            const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.play_arrow_rounded, color: Colors.white)),
        ]),
      )),
    );
  }
}
