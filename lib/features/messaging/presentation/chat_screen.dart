import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';
import '../../home/presentation/shared_post_screen.dart';

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

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _refresh();
    _channel = MessagingService.watchConversation(widget.conversationId, _refresh);
    _presenceChannel = MessagingService.watchPresence(_refreshPresence);
    _refreshPresence();
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
        _error = 'دریافت پیام‌ها انجام نشد. اتصال را بررسی کنید.';
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
        title: const Text('جست‌وجوی پیام‌ها'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'حداقل دو نویسه')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('جست‌وجو')),
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
                ? const Center(child: Text('پیامی پیدا نشد.'))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return ListTile(
                        title: Text(item['body'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_time(item['created_at'] as String?)),
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جست‌وجوی پیام‌ها انجام نشد.')),
      );
    }
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('انتخاب تصویر'), onTap: () => Navigator.pop(context, 'image')),
          ListTile(leading: const Icon(Icons.video_library_outlined), title: const Text('انتخاب ویدئو'), onTap: () => Navigator.pop(context, 'video')),
          ListTile(leading: const Icon(Icons.attach_file_rounded), title: const Text('انتخاب فایل'), onTap: () => Navigator.pop(context, 'file')),
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
            const SnackBar(content: Text('حجم فایل نباید بیشتر از ۵۰ مگابایت باشد.')),
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
          const SnackBar(content: Text('ارسال فایل انجام نشد. دوباره تلاش کنید.')),
        );
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }
    try {
      final XFile? file = choice == 'image'
          ? await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88)
          : await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 52428800) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حجم رسانه نباید بیشتر از ۵۰ مگابایت باشد.')));
        return;
      }
      final ext = file.name.toLowerCase().split('.').last;
      final mime = choice == 'image'
          ? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg')
          : (ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4');
      setState(() => _sending = true);
      await MessagingService.sendMediaMessage(
        conversationId: widget.conversationId,
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
      );
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارسال رسانه انجام نشد. دوباره تلاش کنید.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _controller.text.trim().isEmpty) return;
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
          const SnackBar(content: Text('ارسال پیام انجام نشد. دوباره تلاش کنید.')),
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
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('پست HomaGram', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 3),
                Text('برای مشاهده پست لمس کنید', style: TextStyle(fontSize: 11)),
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.person_rounded, color: colors.onPrimaryContainer, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  if (_presenceLabel.isNotEmpty)
                    Text(_presenceLabel, style: TextStyle(
                      fontSize: 10,
                      color: _presenceLabel == 'آنلاین'
                          ? colors.primary : colors.onSurfaceVariant,
                    )),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'جست‌وجوی پیام‌ها',
            onPressed: _searchMessages,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'اطلاعات گفتگو',
            onPressed: _showConversationInfo,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? const _EmptyChat()
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
                                    child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (!deleted && (message['attachments'] as List? ?? []).isNotEmpty)
                                        _attachmentPreview((message['attachments'] as List).first as Map<String, dynamic>),
                                      if (deleted)
                                        Text('این پیام حذف شده است',
                                          style: TextStyle(color: colors.onSurfaceVariant, height: 1.6))
                                      else
                                        _messageContent(message['body'] as String? ?? '', colors),
                                      if (!deleted && (message['reactions'] as List? ?? []).isNotEmpty)
                                        _reactionSummary(message),
                                      if (message['edited_at'] != null && !deleted)
                                        const Text('ویرایش‌شده', style: TextStyle(fontSize: 9)),
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
                        Expanded(child: Text('پاسخ به: ${_replyToBody ?? 'پیام'}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                        IconButton(onPressed: () => setState(() { _replyToId = null; _replyToBody = null; }), icon: const Icon(Icons.close, size: 18)),
                      ]),
                    ),
                  Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'افزودن رسانه',
                    onPressed: _sending ? null : _pickMedia,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'پیام خود را بنویسید…',
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
                    onPressed: _sending ? null : _send,
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
        label = online > 0 ? '$online نفر آنلاین' : 'گروه';
      } else if (online > 0) {
        label = 'آنلاین';
      } else if (rows.isNotEmpty && rows.first['last_seen_at'] != null) {
        final last = DateTime.tryParse(rows.first['last_seen_at'] as String);
        label = last == null ? 'آفلاین' : 'آخرین بازدید ${last.toLocal().hour.toString().padLeft(2, '0')}:${last.toLocal().minute.toString().padLeft(2, '0')}';
      } else {
        label = 'آفلاین';
      }
      if (mounted && label != _presenceLabel) setState(() => _presenceLabel = label);
    } catch (_) {}
  }

  Future<void> _showConversationInfo() async {
    try {
      final info = await Supabase.instance.client.from('conversations')
          .select('kind,title').eq('id', widget.conversationId).single();
      var members = await MessagingService.loadConversationMembers(widget.conversationId);
      if (!mounted) return;
      String myRole = 'member';
      for (final member in members) {
        if (member['user_id'] == _myId) {
          myRole = member['role'] as String? ?? 'member';
          break;
        }
      }
      final isGroup = info['kind'] == 'group';
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(children: [
                  Expanded(child: Text(
                    isGroup ? (info['title'] as String? ?? 'گروه') : widget.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  )),
                  if (isGroup && (myRole == 'owner' || myRole == 'admin'))
                    IconButton(
                      tooltip: 'تغییر نام گروه', icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final controller = TextEditingController(text: info['title'] as String? ?? '');
                        final title = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('نام گروه'),
                            content: TextField(controller: controller, maxLength: 100),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('ذخیره')),
                            ],
                          ),
                        );
                        controller.dispose();
                        if (title != null && title.trim().isNotEmpty) {
                          await MessagingService.updateGroupTitle(widget.conversationId, title);
                          if (mounted) setState(() {});
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        }
                      },
                    ),
                  if (isGroup && (myRole == 'owner' || myRole == 'admin'))
                    IconButton(
                      tooltip: 'افزودن عضو', icon: const Icon(Icons.person_add_alt_1_rounded),
                      onPressed: () async {
                        final queryController = TextEditingController();
                        final query = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('افزودن عضو'),
                            content: TextField(controller: queryController, autofocus: true, decoration: const InputDecoration(hintText: 'نام کاربری')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, queryController.text), child: const Text('جست‌وجو')),
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
                        await MessagingService.manageGroupMember(widget.conversationId, selected['id'] as String, 'add');
                        members = await MessagingService.loadConversationMembers(widget.conversationId);
                        if (sheetContext.mounted) setSheetState(() {});
                      },
                    ),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (ctx, index) {
                    final member = members[index];
                    final role = member['role'] as String? ?? 'member';
                    final isMe = member['user_id'] == _myId;
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                      title: Text(member['display_name'] as String? ?? ''),
                      subtitle: Text('@${member['username']} • ${role == 'owner' ? 'مالک' : role == 'admin' ? 'مدیر' : 'عضو'}'),
                      trailing: isGroup && !isMe && (myRole == 'owner' || (myRole == 'admin' && role == 'member'))
                          ? PopupMenuButton<String>(
                              onSelected: (action) async {
                                await MessagingService.manageGroupMember(widget.conversationId, member['user_id'] as String, action);
                                members = await MessagingService.loadConversationMembers(widget.conversationId);
                                if (sheetContext.mounted) setSheetState(() {});
                              },
                              itemBuilder: (_) => [
                                if (myRole == 'owner' && role == 'member')
                                  const PopupMenuItem(value: 'promote', child: Text('ارتقا به مدیر')),
                                if (myRole == 'owner' && role == 'admin')
                                  const PopupMenuItem(value: 'demote', child: Text('تنزل به عضو')),
                                if (role != 'owner' && (myRole == 'owner' || role == 'member'))
                                  const PopupMenuItem(value: 'remove', child: Text('حذف از گروه')),
                              ],
                            )
                          : role == 'owner' ? const Icon(Icons.verified_rounded, size: 18) : null,
                    );
                  },
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
                    icon: const Icon(Icons.logout_rounded), label: const Text('خروج از گفتگو'),
                  )),
                ),
              ),
            ]),
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اطلاعات گفتگو دریافت نشد.')),
      );
    }
  }

  Widget _attachmentPreview(Map<String, dynamic> attachment) {
    final url = attachment['signed_url'] as String?;
    final mime = attachment['mime_type'] as String? ?? '';
    if (url == null) return const Padding(padding: EdgeInsets.all(8), child: Text('رسانه در دسترس نیست.'));
    if (mime.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, width: 230, height: 190, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(width: 230, height: 90, child: Center(child: Icon(Icons.broken_image_outlined)))),
        ),
      );
    }
    if (mime.startsWith('video/')) return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _VideoMessagePreview(url: url),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.attach_file_rounded), const SizedBox(width: 6),
      Flexible(child: Text(attachment['file_name'] as String? ?? 'فایل')),
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('پاسخ به پیام'),
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
            if (mine) ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('ویرایش پیام'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            if (mine) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('حذف برای همه', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'reply') {
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
            title: const Text('ویرایش پیام'),
            content: TextField(controller: controller, autofocus: true, maxLines: 5, maxLength: 10000),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('ذخیره')),
            ],
          ),
        );
        controller.dispose();
        if (updated != null) {
          await MessagingService.editMessage(message['id'] as String, updated);
          await _refresh();
        }
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف پیام'),
            content: const Text('این پیام برای همه اعضای گفتگو حذف شود؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
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
          const SnackBar(content: Text('عملیات انجام نشد. دوباره تلاش کنید.')),
        );
      }
    }
  }

  String _time(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text('گفتگو را شروع کنید', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 6),
              const Text('اولین پیام این گفتگو را ارسال کنید.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
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
