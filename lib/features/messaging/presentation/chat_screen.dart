import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';
import '../../home/presentation/shared_post_screen.dart';
import '../../../core/utils/persian_date.dart';

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
          HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف'))),
          HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('جست‌وجو'))),
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
          HomaGramSpringPress(child: IconButton(
            tooltip: 'جست‌وجوی پیام‌ها',
            onPressed: _searchMessages,
            icon: const Icon(Icons.search_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: 'اطلاعات گفتگو',
            onPressed: _showConversationInfo,
            icon: const Icon(Icons.more_vert_rounded),
          )),
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
                        Expanded(child: Text('پاسخ به: ${_replyToBody ?? 'پیام'}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                        HomaGramSpringPress(child: IconButton(onPressed: () => setState(() { _replyToId = null; _replyToBody = null; }), icon: const Icon(Icons.close, size: 18))),
                      ]),
                    ),
                  Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  HomaGramSpringPress(child: IconButton(
                    tooltip: 'افزودن رسانه',
                    onPressed: _sending ? null : _pickMedia,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  )),
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
                  HomaGramSpringPress(child: IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  )),
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


  Future<void> _showChannelAuditLogs(String conversationId) async {
    var loading = true;
    String? error;
    var logs = <Map<String, dynamic>>[];
    try {
      logs = await MessagingService.loadChannelAuditLogs(conversationId);
      loading = false;
    } catch (_) {
      loading = false;
      error = 'دریافت تاریخچه فعالیت‌ها ممکن نشد.';
    }
    if (!mounted) return;

    String actionTitle(String action) {
      switch (action) {
        case 'channel_created': return 'ایجاد کانال';
        case 'member_added': return 'افزودن عضو';
        case 'member_removed': return 'حذف عضو';
        case 'member_role_changed': return 'تغییر نقش عضو';
        case 'channel_permissions_changed': return 'تغییر دسترسی اعضا';
        case 'channel_details_changed': return 'ویرایش اطلاعات کانال';
        case 'ownership_transferred': return 'انتقال مالکیت';
        case 'invite_created': return 'ساخت کد دعوت';
        case 'invite_revoked': return 'لغو کد دعوت';
        default: return 'فعالیت مدیریتی';
      }
    }

    String actionDetail(Map<String, dynamic> row) {
      final metadata = row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : <String, dynamic>{};
      final target = row['target_label'] as String?;
      switch (row['action']) {
        case 'member_added': return target == null ? 'عضو جدید به کانال اضافه شد.' : '$target به کانال اضافه شد.';
        case 'member_removed': return target == null ? 'یک عضو از کانال حذف شد.' : '$target از کانال حذف شد.';
        case 'member_role_changed':
          return '${metadata['old_role'] ?? '—'} ← ${metadata['new_role'] ?? '—'}';
        case 'ownership_transferred': return target == null ? 'مالکیت کانال منتقل شد.' : 'مالک جدید: $target';
        case 'channel_permissions_changed':
          return 'ارسال متن: ${metadata['members_can_post'] == true ? 'فعال' : 'غیرفعال'} • رسانه: ${metadata['members_can_send_media'] == true ? 'فعال' : 'غیرفعال'}';
        case 'invite_created': return 'اعتبار: ${metadata['expires_at'] ?? '—'} • سقف استفاده: ${metadata['max_uses'] ?? '—'}';
        case 'invite_revoked': return 'یک کد دعوت غیرفعال شد.';
        case 'channel_details_changed':
          return metadata['title'] is String ? 'نام کانال: ${metadata['title']}' : 'اطلاعات کانال به‌روزرسانی شد.';
        case 'channel_created': return 'کانال ایجاد شد.';
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
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
                child: Row(children: [
                  Icon(Icons.history_rounded),
                  SizedBox(width: 9),
                  Text('تاریخچه فعالیت‌های کانال',
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
                            ? const Center(child: Text('هنوز فعالیت مدیریتی ثبت نشده است.'))
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
                                          Text('${row['actor_label'] ?? 'مدیر سیستم'} • $dateLabel',
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

  Future<void> _manageChannelInvites(String conversationId) async {
    var invites = <Map<String, dynamic>>[];
    var loading = true;
    String? loadError;

    try {
      invites = await MessagingService.loadChannelInvites(conversationId);
      loading = false;
    } catch (_) {
      loading = false;
      loadError = 'دریافت کدهای دعوت ممکن نشد.';
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
              final rows = await MessagingService.loadChannelInvites(conversationId);
              if (!sheetContext.mounted) return;
              setSheetState(() { invites = rows; loading = false; });
            } catch (_) {
              if (!sheetContext.mounted) return;
              setSheetState(() { loading = false; loadError = 'به‌روزرسانی فهرست ممکن نشد.'; });
            }
          }

          Future<void> createInvite() async {
            final expiryController = TextEditingController(text: '168');
            final usesController = TextEditingController(text: '100');
            final formKey = GlobalKey<FormState>();
            final values = await showDialog<List<int>>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('ساخت کد دعوت جدید'),
                content: Form(
                  key: formKey,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: expiryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'اعتبار به ساعت (۱ تا ۷۲۰)'),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        return number == null || number < 1 || number > 720
                            ? 'عدد باید بین ۱ تا ۷۲۰ باشد.' : null;
                      },
                    ),
                    TextFormField(
                      controller: usesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'حداکثر دفعات استفاده (۱ تا ۵۰۰)'),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        return number == null || number < 1 || number > 500
                            ? 'عدد باید بین ۱ تا ۵۰۰ باشد.' : null;
                      },
                    ),
                  ]),
                ),
                actions: [
                  HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف'))),
                  HomaGramSpringPress(child: FilledButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(dialogContext, [
                          int.parse(expiryController.text),
                          int.parse(usesController.text),
                        ]);
                      }
                    },
                    child: const Text('ساخت کد'),
                  )),
                ],
              ),
            );
            expiryController.dispose();
            usesController.dispose();
            if (values == null || !sheetContext.mounted) return;

            try {
              final token = await MessagingService.createChannelInvite(
                conversationId,
                expiresInHours: values[0],
                maxUses: values[1],
              );
              if (!sheetContext.mounted) return;
              await showDialog<void>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('کد دعوت آماده است'),
                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('این کد فقط همین بار نمایش داده می‌شود. آن را در جای امن نگه دارید و برای افراد موردنظر بفرستید.'),
                    const SizedBox(height: 12),
                    SelectableText(token, textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: HomaGramSpringPress(child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: token));
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text('کد دعوت کپی شد.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('کپی کد'),
                    ))),
                  ]),
                  actions: [
                    HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))),
                  ],
                ),
              );
              await reload();
            } catch (_) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('ساخت کد دعوت انجام نشد.')),
                );
              }
            }
          }

          Future<void> revokeInvite(String inviteId) async {
            final confirmed = await showDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => AlertDialog(
                title: const Text('غیرفعال‌سازی کد دعوت'),
                content: const Text('با این کار، کد دیگر برای عضویت قابل استفاده نخواهد بود.'),
                actions: [
                  HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف'))),
                  HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('غیرفعال کن'))),
                ],
              ),
            );
            if (confirmed != true || !sheetContext.mounted) return;
            try {
              await MessagingService.revokeChannelInvite(inviteId);
              await reload();
            } catch (_) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('غیرفعال‌سازی کد انجام نشد.')),
                );
              }
            }
          }

          String statusLabel(String status) => switch (status) {
            'active' => 'فعال',
            'revoked' => 'غیرفعال‌شده',
            'expired' => 'منقضی‌شده',
            'exhausted' => 'ظرفیت تکمیل',
            _ => 'نامشخص',
          };

          return SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .72,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('مدیریت کدهای دعوت', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: double.infinity, child: HomaGramSpringPress(child: FilledButton.icon(
                  onPressed: createInvite,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('ساخت یا تمدید کد دعوت'),
                ))),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : loadError != null
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(loadError!),
                            HomaGramSpringPress(child: TextButton(onPressed: reload, child: const Text('تلاش دوباره'))),
                          ]))
                        : invites.isEmpty
                            ? const Center(child: Text('هنوز کد دعوتی ساخته نشده است.'))
                            : ListView.separated(
                                itemCount: invites.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, index) {
                                  final invite = invites[index];
                                  final status = invite['invite_status'] as String? ?? '';
                                  final expires = DateTime.tryParse(invite['expires_at'] as String? ?? '');
                                  final expiryText = expires == null
                                      ? 'زمان انقضا نامشخص'
                                      : 'انقضا: ${expires.toLocal().toString().substring(0, 16)}';
                                  return ListTile(
                                    leading: Icon(
                                      status == 'active' ? Icons.key_rounded : Icons.key_off_rounded,
                                      color: status == 'active' ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                                    title: Text(statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w800)),
                                    subtitle: Text('${invite['use_count']} از ${invite['max_uses']} استفاده • $expiryText'),
                                    trailing: status == 'active'
                                        ? HomaGramSpringPress(child: IconButton(
                                            tooltip: 'غیرفعال‌سازی',
                                            onPressed: () => revokeInvite(invite['id'] as String),
                                            icon: const Icon(Icons.block_rounded),
                                          ))
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

  Future<void> _showConversationInfo() async {
    try {
      final info = await Supabase.instance.client.from('conversations')
          .select('kind,title,channels(slug,description,is_public,members_can_post,members_can_send_media)')
          .eq('id', widget.conversationId).single();
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
      final isChannel = info['kind'] == 'channel';
      final canManage = myRole == 'owner' || myRole == 'admin';
      final channelData = info['channels'] is Map
          ? Map<String, dynamic>.from(info['channels'] as Map)
          : <String, dynamic>{};

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
                  Expanded(child: Text(
                    (info['title'] as String?) ?? (isChannel ? 'کانال' : isGroup ? 'گروه' : widget.title),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  )),
                  if ((isGroup || isChannel) && canManage)
                    HomaGramSpringPress(child: IconButton(
                      tooltip: isChannel ? 'ویرایش اطلاعات کانال' : 'تغییر نام گروه',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final titleController = TextEditingController(text: info['title'] as String? ?? '');
                        final slugController = TextEditingController(text: channelData['slug'] as String? ?? '');
                        final descriptionController = TextEditingController(text: channelData['description'] as String? ?? '');
                        final values = await showDialog<List<String>>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isChannel ? 'اطلاعات کانال' : 'نام گروه'),
                            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              TextField(controller: titleController, maxLength: 100,
                                decoration: const InputDecoration(labelText: 'نام')),
                              if (isChannel) ...[
                                TextField(controller: slugController, maxLength: 32,
                                  decoration: const InputDecoration(labelText: 'شناسه', prefixText: '@')),
                                TextField(controller: descriptionController, maxLength: 500, maxLines: 3,
                                  decoration: const InputDecoration(labelText: 'توضیحات')),
                              ],
                            ])),
                            actions: [
                              HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))),
                              HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx, [
                                titleController.text, slugController.text, descriptionController.text,
                              ]), child: const Text('ذخیره'))),
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
                              const SnackBar(content: Text('شناسه باید ۳ تا ۳۲ حرف انگلیسی، عدد یا زیرخط باشد.')),
                            );
                            return;
                          }
                          await MessagingService.updateChannelDetails(
                            conversationId: widget.conversationId,
                            title: values[0], slug: values[1], description: values[2],
                          );
                        } else {
                          await MessagingService.updateGroupTitle(widget.conversationId, values[0]);
                        }
                        if (mounted) setState(() {});
                        if (sheetContext.mounted) Navigator.pop(sheet)Context);
                      },
                    ),
                  if (isChannel && canManage)
                    HomaGramSpringPress(child: IconButton(
                      tooltip: 'تنظیمات دسترسی اعضا',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () async {
                        var canPost = channelData['members_can_post'] as bool? ?? true;
                        var canSendMedia = channelData['members_can_send_media'] as bool? ?? true;
                        final values = await showDialog<List<bool>>(
                          context: context,
                          builder: (dialogContext) => StatefulBuilder(
                            builder: (dialogContext, setDialogState) => AlertDialog(
                              title: const Text('دسترسی اعضای عادی'),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('ارسال پیام متنی'),
                                  subtitle: const Text('اعضای عادی بتوانند پیام متنی بفرستند.'),
                                  value: canPost,
                                  onChanged: (value) => setDialogState(() => canPost = value),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('ارسال رسانه و فایل'),
                                  subtitle: const Text('اعضای عادی بتوانند تصویر، ویدئو و فایل بفرستند.'),
                                  value: canSendMedia,
                                  onChanged: (value) => setDialogState(() => canSendMedia = value),
                                ),
                                const SizedBox(height: 4),
                                const Text('مالک و مدیران کانال همیشه امکان ارسال دارند.',
                                  style: TextStyle(fontSize: 12)),
                              ]),
                              actions: [
                                HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف'))),
                                HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, [canPost, canSendMedia]),
                                  child: const Text('ذخیره تنظیمات'))),
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
                            const SnackBar(content: Text('دسترسی اعضا به‌روزرسانی شد.')),
                          );
                        } catch (_) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ذخیره تنظیمات دسترسی انجام نشد.')),
                          );
                )        }
                      },
                    ),
                  if (isChannel && canManage)
                    HomaGramSpringPress(child: IconButton(
                      tooltip: 'تاریخچه فعالیت‌های کانال',
                      icon: const Icon(Icons.history_rounded),
                      onPressed: () => _showChannelAuditLogs(widget.conversationId),
                    )),
                  if (isChannel && canManage && channelData['is_public'] == false)
                    HomaGramSpringPress(child: IconButton(
                      tooltip: 'مدیریت کدهای دعوت',
                      icon: const Icon(Icons.key_rounded),
                      onPressed: () => _manageChannelInvites(widget.conversationId),
                    )),
                  if ((isGroup || isChannel) && canManage)
                    HomaGramSpringPress(child: IconButton(
                      tooltip: 'افزودن عضو', icon: const Icon(Icons.person_add_alt_1_rounded),
                      onPressed: () async {
                        final queryController = TextEditingController();
                        final query = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('افزودن عضو'),
                            content: TextField(controller: queryController, autofocus: true,
                              decoration: const InputDecoration(hintText: 'نام کاربری')),
                            actions: [
                              HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))),
                              HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx, queryController.text),
                                child: const Text('جست‌وجو'))),
                            ],
                          ),
                        );
                        queryController.dispose();
                        if (query == null || query.trim().length < 2) return;
                        final users = await MessagingService.searchUsers(query);
                        if (!mounted) return;
                        final selected = await showModalBottomSheet<Map<String, dynamic>>(
                          context: context, showDragHandle: true,
                          builder: (ctx) => HomaGramEntrance(child: ListView(
                            shrinkWrap: true,
                            children: users.map((user) => ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                              title: Text(user['display_name'] as String? ?? user['username'] as String),
                              subtitle: Text('@${user['username']}'),
                              onTap: () => Navigator.pop(ctx, user),
                            )).toList(),
                          )),
                        );
                        if (selected == null) return;
                        await manageMember(selected['id'] as String, 'add');
                        if (sheetContext.mounted) setSheetStat)e(() {});
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
                    final canAct = (isGroup || isChannel) && !isMe && canManage &&
                        (myRole == 'owner' || role == 'member');
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                      title: Text(member['display_name'] as String? ?? ''),
                      subtitle: Text('@${member['username']} • ${role == 'owner' ? 'مالک' : role == 'admin' ? 'مدیر' : 'عضو'}'),
                      trailing: canAct
                          ? PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'transfer') {
                                  final displayName = member['display_name'] as String? ?? member['username'] as String? ?? 'این عضو';
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('انتقال مالکیت کانال'),
                                      content: Text('مالکیت کانال به $displayName منتقل شود؟ شما پس از انتقال، مدیر کانال خواهید بود و مالک جدید کنترل کامل کانال را در اختیار می‌گیرد.'),
                                      actions: [
                                        HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف'))),
                                        HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأیید انتقال'))),
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
                                      const SnackBar(content: Text('مالکیت کانال با موفقیت منتقل شد.')),
                                    );
                                  } catch (_) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('انتقال مالکیت انجام نشد. فقط مالک فعلی می‌تواند این کار را انجام دهد.')),
                                    );
                                  }
                                  return;
                                }
                                await manageMember(member['user_id'] as String, action);
                                if (sheetContext.mounted) setSheetState(() {});
                              },
                              itemBuilder: (_) => [
                                if (myRole == 'owner' && role == 'member')
                                  const PopupMenuItem(value: 'promote', child: Text('ارتقا به مدیر')),
                                if (myRole == 'owner' && role == 'admin')
                                  const PopupMenuItem(value: 'demote', child: Text('تنزل به عضو')),
                                if (isChannel && myRole == 'owner' && role != 'owner')
                                  const PopupMenuItem(value: 'transfer', child: Text('انتقال مالکیت کانال')),
                                if (role != 'owner' && (myRole == 'owner' || role == 'member'))
                                  PopupMenuItem(value: 'remove', child: Text(isChannel ? 'حذف از کانال' : 'حذف از گروه')),
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
                  child: SizedBox(width: double.infinity, child: HomaGramSpringPress(child: OutlinedButton.icon(
                    onPressed: () async {
                      await MessagingService.leaveConversation(widget.conversationId);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(isChannel ? 'خروج از کانال' : isGroup ? 'خروج از گروه' : 'خروج از گفتگو'),
                  ))),
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
                HomaGramSpringPress(child: TextButton(
                  onPressed: () => Navigator.pop(context, 'reaction:$emoji'),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                )),
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
            if (!mine) ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('گزارش این پیام'),
              subtitle: const Text('ارسال محرمانه برای بررسی مدیران'),
              onTap: () => Navigator.pop(context, 'report'),
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
              HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف'))),
              HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('ذخیره'))),
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
              const Padding(padding: EdgeInsets.all(16),
                child: Text('دلیل گزارش پیام', style: TextStyle(fontWeight: FontWeight.w900))),
              for (final item in const [
                ('spam','هرزنامه یا تبلیغات مزاحم'),
                ('harassment','آزار و اذیت'),
                ('threat','تهدید یا محتوای خطرناک'),
                ('privacy','نقض حریم خصوصی'),
                ('inappropriate','محتوای نامناسب'),
                ('other','سایر موارد'),
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
              title: const Text('توضیحات تکمیلی'),
              content: TextField(controller: detailsController, maxLength: 1000,
                minLines: 2, maxLines: 5, decoration: const InputDecoration(
                  hintText: 'در صورت نیاز توضیح کوتاهی بنویسید.')),
              actions: [
                HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: const Text('رد کردن'))),
                HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, detailsController.text.trim()),
                  child: const Text('ثبت گزارش'))),
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
              const SnackBar(content: Text('گزارش برای بررسی ارسال شد.')));
          }
        }
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف پیام'),
            content: const Text('این پیام برای همه اعضای گفتگو حذف شود؟'),
            actions: [
              HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف'))),
              HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))),
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
