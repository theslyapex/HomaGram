import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';

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
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _refresh();
    _channel = MessagingService.watchConversation(widget.conversationId, _refresh);
  }

  Future<void> _refresh() async {
    try {
      final messages = await MessagingService.loadMessages(widget.conversationId);
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

  Future<void> _send() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    final text = _controller.text;
    _controller.clear();
    setState(() => _sending = true);
    try {
      await MessagingService.sendTextMessage(widget.conversationId, text);
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    final channel = _channel;
    if (channel != null) MessagingService.removeChannel(channel);
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
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'اطلاعات گفتگو',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('مدیریت گفتگو در مرحله بعد اضافه می‌شود.')),
            ),
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        deleted ? 'این پیام حذف شده است' : (message['body'] as String? ?? ''),
                                        style: TextStyle(
                                          color: deleted ? colors.onSurfaceVariant : colors.onSurface,
                                          height: 1.6,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _time(message['created_at'] as String?),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
            ),
          ),
        ],
      ),
    );
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
