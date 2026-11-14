import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/support_service.dart';
import 'support_chat_screen.dart';

class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  List<SupportConversationPreview> _items = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = SupportService.watchAdminInbox(_load);
  }

  Future<void> _load() async {
    try {
      final items = await SupportService.loadAdminInbox();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'دریافت صندوق پشتیبانی ناموفق بود.';
      });
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) SupportService.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('صندوق پشتیبانی',
          style: TextStyle(fontWeight: FontWeight.w900))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  HomaGramSpringPress(child: TextButton(onPressed: _load, child: const Text('تلاش دوباره'))),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                          SizedBox(height: 125),
                          Icon(Icons.mark_chat_unread_outlined, size: 56, color: Color(0xFF8B6CF6)),
                          SizedBox(height: 14),
                          Center(child: Text('درخواست پشتیبانی جدیدی وجود ندارد.')),
                        ])
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final isOpen = item.status == 'open';
                            return Material(
                              color: colors.surfaceContainerHighest.withValues(alpha: .65),
                              borderRadius: BorderRadius.circular(17),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: isOpen
                                      ? const Color(0xFF8B6CF6).withValues(alpha: .15)
                                      : colors.surfaceContainerHighest,
                                  child: Icon(Icons.person_outline_rounded,
                                      color: isOpen ? const Color(0xFF8B6CF6) : colors.onSurfaceVariant),
                                ),
                                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isOpen
                                            ? const Color(0xFF24A879).withValues(alpha: .13)
                                            : colors.surface,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(isOpen ? 'باز' : 'بسته',
                                          style: TextStyle(fontSize: 10,
                                            color: isOpen ? const Color(0xFF24A879) : colors.onSurfaceVariant)),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(_date(item.updatedAt), style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => SupportChatScreen(
                                    conversationId: item.id,
                                    title: item.title,
                                    isAdmin: true,
                                  ),
                                )),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day}';
  }
}
