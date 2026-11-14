import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';
import '../../support/data/support_service.dart';
import '../../support/presentation/support_chat_screen.dart';
import '../../support/presentation/support_inbox_screen.dart';
import 'chat_screen.dart';
import 'channels_screen.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  List<ConversationPreview> _items = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = MessagingService.watchInbox(_load);
  }

  Future<void> _load() async {
    try {
      final items = await MessagingService.loadInbox();
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
        _error = 'فهرست گفتگوها دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _newGroup() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _NewGroupSheet(),
    );
    if (!mounted || id == null) return;
    await _load();
    var title = 'گروه جدید';
    for (final item in _items) {
      if (item.id == id) { title = item.title; break; }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(conversationId: id, title: title),
    ));
  }

  Future<void> _newChat() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _NewChatSheet(),
    );
    if (!mounted || id == null) return;
    await _load();
    var title = 'گفت‌وگوی خصوصی';
    for (final item in _items) {
      if (item.id == id) {
        title = item.title;
        break;
      }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(conversationId: id, title: title),
    ));
  }

  Future<void> _openSupport() async {
    try {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const SupportChatScreen(),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('باز کردن پشتیبانی ممکن نشد.')),
        );
      }
    }
  }

  void _openSupportInbox() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const SupportInboxScreen(),
    ));
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) MessagingService.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('پیام‌ها', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'کانال‌ها',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ChannelsScreen(),
            )),
            icon: const Icon(Icons.campaign_outlined),
          ),
          IconButton(
            tooltip: 'ساخت گروه',
            onPressed: _newGroup,
            icon: const Icon(Icons.group_add_outlined),
          ),
          IconButton(
            tooltip: 'گفت‌وگوی جدید',
            onPressed: _newChat,
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(children: [
              InkWell(
                onTap: _openSupport,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF34236F), Color(0xFF172C55), Color(0xFF123F58)],
                    ),
                    border: Border.all(color: const Color(0xFF9A83FF).withValues(alpha: .42)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF7658E8).withValues(alpha: .15),
                        blurRadius: 22, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9A75FF), Color(0xFF38C7E9)],
                        ),
                      ),
                      child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 25),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(child: Text('پشتیبانی هماگرام',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
                          SizedBox(width: 6),
                          Icon(Icons.verified_rounded, size: 16, color: Color(0xFF65D9F0)),
                        ]),
                        SizedBox(height: 5),
                        Text('ارتباط مستقیم با تیم پشتیبانی',
                          style: TextStyle(color: Color(0xFFD5DDF5), fontSize: 11)),
                      ],
                    )),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 17, color: Colors.white70),
                  ]),
                ),
              ),
              if (SupportService.isSupportAdmin)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openSupportInbox,
                    icon: const Icon(Icons.inbox_outlined, size: 18),
                    label: const Text('مدیریت درخواست‌های پشتیبانی'),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                      SizedBox(height: 125),
                      Center(child: CircularProgressIndicator()),
                    ])
                  : _error != null
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                          const SizedBox(height: 120),
                          Center(child: Text(_error!)),
                          Center(child: TextButton(onPressed: _load, child: const Text('تلاش دوباره'))),
                        ])
                      : _items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 75),
                                Icon(Icons.forum_outlined, size: 58, color: colors.primary),
                                const SizedBox(height: 16),
                                const Center(child: Text('هنوز گفتگویی ندارید',
                                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                                const SizedBox(height: 8),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 42),
                                  child: Text('با شروع یک گفت‌وگوی خصوصی، ارتباط در HomaGram را آغاز کنید.',
                                    textAlign: TextAlign.center),
                                ),
                                const SizedBox(height: 18),
                                Center(child: FilledButton.icon(
                                  onPressed: _newChat,
                                  icon: const Icon(Icons.add_comment_outlined),
                                  label: const Text('شروع گفت‌وگوی جدید', style: TextStyle(fontFamily: 'Estedad')),
                                )),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: colors.primaryContainer,
                                    child: Icon(
                                      item.kind == 'group' ? Icons.groups_rounded : Icons.person_rounded,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  trailing: Text(_date(item.updatedAt), style: Theme.of(context).textTheme.labelSmall),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => ChatScreen(conversationId: item.id, title: item.title),
                                  )),
                                );
                              },
                            ),
            ),
          ),
        ],
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

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet();

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _searching = false;
  bool _opening = false;
  String? _error;

  Future<void> _find(String value) async {
    if (value.trim().length < 2) {
      setState(() {
        _users = [];
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final users = await MessagingService.searchUsers(value);
      if (!mounted) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'جست‌وجو انجام نشد.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _open(Map<String, dynamic> user) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final id = await MessagingService.createDirectConversation(user['id'] as String);
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = 'شروع گفتگو ممکن نشد. ممکن است این کاربر دسترسی پیام را محدود کرده باشد.';
        });
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('گفت‌وگوی جدید', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: _find,
            decoration: InputDecoration(
              hintText: 'جست‌وجو با نام کاربری',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: 8),
          if (_users.isEmpty && _search.text.trim().length >= 2 && !_searching)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: Text('کاربری با این نام پیدا نشد.')),
            ),
          if (_users.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                    title: Text(user['display_name'] as String? ?? user['username'] as String),
                    subtitle: Text('@${user['username']}'),
                    onTap: _opening ? null : () => _open(user),
                  );
                },
              ),
            ),
          if (_opening) const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          )),
        ],
      ),
    );
  }
}

class _NewGroupSheet extends StatefulWidget {
  const _NewGroupSheet();
  @override
  State<_NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<_NewGroupSheet> {
  final _title = TextEditingController();
  final _search = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _users = [];
  bool _searching = false, _creating = false;
  String? _error;

  Future<void> _find(String value) async {
    if (value.trim().length < 2) { setState(() => _users = []); return; }
    setState(() => _searching = true);
    try {
      final users = await MessagingService.searchUsers(value);
      if (mounted) setState(() { _users = users; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'جست‌وجوی کاربران انجام نشد.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'نام گروه را وارد کنید.');
      return;
    }
    setState(() { _creating = true; _error = null; });
    try {
      final id = await MessagingService.createGroupConversation(
        title: _title.text,
        memberIds: _selected.toList(),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) setState(() {
        _creating = false;
        _error = 'ساخت گروه انجام نشد. دوباره تلاش کنید.';
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ساخت گروه جدید', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(controller: _title, maxLength: 100,
            decoration: const InputDecoration(labelText: 'نام گروه', prefixIcon: Icon(Icons.groups_outlined))),
          const SizedBox(height: 8),
          TextField(controller: _search, autofocus: true, onChanged: _find,
            decoration: const InputDecoration(hintText: 'جست‌وجوی اعضا با نام کاربری', prefixIcon: Icon(Icons.search_rounded))),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_selected.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${_selected.length} عضو انتخاب شده‌اند')),
          if (_users.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final id = user['id'] as String;
                  final selected = _selected.contains(id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        if (_selected.length < 99) _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
                    secondary: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(user['display_name'] as String? ?? user['username'] as String),
                    subtitle: Text('@${user['username']}'),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _creating ? null : _create,
              icon: _creating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.group_add_rounded),
              label: const Text('ایجاد گروه'),
            ),
          ),
        ],
      ),
    );
  }
}
