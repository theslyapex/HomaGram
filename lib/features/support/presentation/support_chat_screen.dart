import 'package:homagram/app/presentation/homagram_branding.dart';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/support_service.dart';
import '../../../l10n/generated/app_localizations.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    this.conversationId,
    this.initialMessage,
    this.title = 'پشتیبانی هماگرام',
    this.isAdmin = false,
    super.key,
  });

  final String? conversationId;
  final String? initialMessage;
  final String title;
  final bool isAdmin;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  String? _conversationId;
  String _status = 'open';
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  bool _initialMessageSent = false;
  String? _replyToId;
  String? _replyToBody;
  String? _error;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final id = widget.conversationId ??
          await SupportService.getOrCreateConversation();
      final info = await SupportService.loadConversationInfo(id);
      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _status = info['status'] as String? ?? 'open';
      });
      _channel = SupportService.watchMessages(id, _loadMessages);
      await _loadMessages();
      final initial = widget.initialMessage?.trim();
      if (!_initialMessageSent && initial != null && initial.isNotEmpty && !widget.isAdmin) {
        _initialMessageSent = true;
        try {
          await SupportService.sendText(id, initial);
          await _loadMessages();
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(_t.supportInitialSendFailed)),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t.supportConnectionFailed;
      });
    }
  }

  Future<void> _loadMessages() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final results = await Future.wait([
        SupportService.loadConversationInfo(id),
        SupportService.loadMessages(id),
      ]);
      if (!mounted) return;
      final info = results[0] as Map<String, dynamic>;
      final rows = results[1] as List<Map<String, dynamic>>;
      setState(() {
        _status = info['status'] as String? ?? 'open';
        _messages = rows;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t.supportMessagesLoadFailed;
      });
    }
  }

  Future<void> _sendText() async {
    final id = _conversationId;
    final text = _controller.text.trim();
    if (id == null || text.isEmpty || _sending) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await SupportService.sendText(id, text, replyToId: _replyToId);
      if (mounted) setState(() { _replyToId = null; _replyToBody = null; });
      await _loadMessages();
    } catch (_) {
      if (mounted) {
        _controller.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_t.supportMessageSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAccountDeletionRequest() async {
    if (widget.isAdmin || _conversationId == null || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(_t.supportDeleteAccountTitle),
        content: const Text(_t.supportDeleteAccountConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(_t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(_t.supportSendRequest)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final request = _t.supportDeleteAccountRequestBody;
    try {
      await SupportService.sendText(_conversationId!, request);
      await _loadMessages();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_t.supportDeleteAccountRequestFailed)),
      );
    }
  }

  Future<void> _pickAttachment() async {
    if (_sending || _conversationId == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text(_t.supportSendImage),
            onTap: () => Navigator.pop(context, 'image'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_rounded),
            title: const Text(_t.supportSendFile),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    try {
      Uint8List? bytes;
      String name;
      String mime;
      if (choice == 'image') {
        final image = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 88,
        );
        if (image == null) return;
        bytes = await image.readAsBytes();
        name = image.name;
        final ext = name.toLowerCase().split('.').last;
        mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : ext == 'gif' ? 'image/gif' : 'image/jpeg';
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf','doc','docx','xls','xlsx','ppt','pptx','txt','csv','zip'],
          allowMultiple: false,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;
        bytes = file.bytes;
        name = file.name;
        mime = _mimeFor(file.extension ?? '');
      }
      if (bytes == null || bytes.isEmpty) return;
      if (bytes.length > 52428800) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_t.supportFileMaxSize)),
        );
        return;
      }
      setState(() => _sending = true);
      await SupportService.sendAttachment(
        conversationId: _conversationId!,
        bytes: bytes,
        fileName: name,
        mimeType: mime,
      );
      await _loadMessages();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_t.supportFileSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      case 'zip': return 'application/zip';
      default: throw ArgumentError('Unsupported file type');
    }
  }

  Future<void> _toggleStatus() async {
    final id = _conversationId;
    if (id == null || !widget.isAdmin) return;
    final next = _status == 'open' ? 'closed' : 'open';
    try {
      await SupportService.updateStatus(id, next);
      if (mounted) setState(() => _status = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_t.supportStatusChangeFailed)),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    final channel = _channel;
    if (channel != null) SupportService.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSend = widget.isAdmin || _status == 'open';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                colors: [Color(0xFF8057F5), Color(0xFF35BDEB)],
              ),
            ),
            child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title.isEmpty ? _t.supportChatTitle : widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                Text(_status == 'open' ? _t.supportActiveRequest : _t.supportClosedRequest,
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
        actions: [
          if (widget.isAdmin)
            HomaGramSpringPress(child: IconButton(
              tooltip: _status == 'open' ? _t.supportCloseRequest : _t.supportReopenRequest,
              onPressed: _toggleStatus,
              icon: Icon(_status == 'open' ? Icons.lock_outline_rounded : Icons.lock_open_rounded),
            )),
        ],
      ),
      body: Column(children: [
        if (!widget.isAdmin)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.primary.withValues(alpha: .12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.verified_user_outlined, size: 19),
                SizedBox(width: 9),
                Expanded(child: Text(_t.supportDirectTeamMessage,
                    style: TextStyle(fontSize: 12, height: 1.6))),
              ]),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _sendAccountDeletionRequest,
                  icon: const Icon(Icons.person_remove_alt_1_rounded, size: 17),
                  label: const Text(_t.supportDeleteAccountAction),
                ),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      HomaGramSpringPress(child: TextButton(onPressed: _loadMessages, child: const Text(_t.retry))),
                    ]))
                  : _messages.isEmpty
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                          SizedBox(height: 110),
                          Icon(Icons.support_agent_rounded, size: 58, color: Color(0xFF8B6CF6)),
                          SizedBox(height: 14),
                          Center(child: Text(_t.supportWelcome,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                          SizedBox(height: 8),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 38),
                            child: Text(_t.supportWelcomeHint,
                                textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
                          ),
                        ])
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final mine = message['sender_id'] == _myId;
                            final isImage = message['message_type'] == 'image';
                            final url = message['signed_url'] as String?;
                            return Align(
                              alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                                margin: const EdgeInsets.only(bottom: 9),
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: GestureDetector(
                                  onHorizontalDragEnd: (details) {
                                    final velocity = details.primaryVelocity ?? 0;
                                    if (velocity > 280) {
                                      setState(() {
                                        _replyToId = message['id'] as String;
                                        _replyToBody = (message['body'] as String? ?? '').isNotEmpty
                                            ? message['body'] as String
                                            : (isImage ? _t.supportGenericImage : _t.supportGenericMessage);
                                      });
                                    }
                                  },
                                  child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        child: Text(_t.supportReplyPrefix(message['reply_to_body'] as String? ?? _t.supportGenericMessage),
                                          maxLines: 2, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                                      ),
                                    if (url != null && isImage)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(url, width: 220, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Text(_t.supportImageUnavailable)),
                                      ),
                                    if (url != null && !isImage)
                                      InkWell(
                                        onTap: () => SharePlus.instance.share(ShareParams(uri: Uri.parse(url))),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.insert_drive_file_outlined, size: 22),
                                          const SizedBox(width: 8),
                                          Flexible(child: Text(message['file_name'] as String? ?? _t.supportAttachmentFallback,
                                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.open_in_new_rounded, size: 16),
                                        ]),
                                      ),
                                    if ((message['body'] as String? ?? '').isNotEmpty)
                                      Text(message['body'] as String, style: const TextStyle(height: 1.65)),
                                    const SizedBox(height: 4),
                                    Text(_time(message['created_at']),
                                        style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
                                  ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
        if (!canSend)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            color: colors.surfaceContainerHighest,
            child: Text(_t.supportClosedConversationHint,
                textAlign: TextAlign.center),
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_replyToId != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(_t.supportReplyPrefix(_replyToBody ?? _t.supportGenericMessage),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11))),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() { _replyToId = null; _replyToBody = null; }),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                    ]),
                  ),
                Row(children: [
                  HomaGramSpringPress(child: IconButton(
                    onPressed: _sending ? null : _pickAttachment,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: _t.supportAddAttachment,
                  )),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _t.supportWriteMessage,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  HomaGramSpringPress(child: IconButton.filled(
                    onPressed: _sending ? null : _sendText,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  )),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  String _time(dynamic value) {
    final date = DateTime.tryParse(value as String? ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
