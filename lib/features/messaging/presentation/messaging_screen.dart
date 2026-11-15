import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/messaging_service.dart';
import '../../support/data/support_service.dart';
import '../../support/presentation/support_chat_screen.dart';
import '../../support/presentation/support_inbox_screen.dart';
import 'chat_screen.dart';
import 'channels_screen.dart';
import '../../../l10n/generated/app_localizations.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;

  String _localizedPreviewText(String value) => switch (value) {
    'گفت‌وگوی خصوصی' => _t.privateConversation,
    'هنوز پیامی ارسال نشده' => _t.noMessagesYet,
    'پیام حذف شده است' => _t.deletedMessagePreview,
    'تصویر' => _t.imagePreview,
    'ویدئو' => _t.videoPreview,
    'فایل صوتی' => _t.audioFilePreview,
    'فایل' => _t.filePreview,
    'مدیر سابق' => _t.formerAdmin,
    'کانال خصوصی' => _t.privateChannel,
    _ => value,
  };
  List<ConversationPreview> _items = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _showArchived = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _load();
    _channel = MessagingService.watchInbox(_load);
  }

  Future<void> _load() async {
    try {
      final items = await MessagingService.loadInbox(archived: _showArchived);
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
        _error = _t.inboxLoadFailed;
      });
    }
  }

  Future<void> _joinGroupByInvite() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t.joinGroup),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: _t.groupInviteCodeOrLink,
            hintText: _t.enter64CharInvite,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text(_t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text(_t.join),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || token == null) return;
    var inviteToken = token;
    final parsed = Uri.tryParse(token);
    if (parsed != null && parsed.scheme == 'homagram' && parsed.host == 'group' &&
        parsed.pathSegments.isNotEmpty) {
      inviteToken = parsed.pathSegments.first;
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(inviteToken)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.invalidInviteCodeOrLink)),
      );
      return;
    }
    try {
      final conversationId = await MessagingService.joinGroupByInvite(inviteToken);
      final row = await Supabase.instance.client
          .from('conversations')
          .select('title')
          .eq('id', conversationId)
          .single();
      final title = row['title'] as String? ?? _t.group;
      await _load();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: conversationId, title: title),
      ));
    } catch (error) {
      debugPrint('Join group by invite failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_t.joinGroupFailed)),
      );
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
    var title = _t.newGroup;
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
    var title = _t.privateConversation;
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
          const SnackBar(content: Text(_t.openSupportFailed)),
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final normalizedSearch = _searchTerm.trim().toLowerCase();
    final visibleItems = normalizedSearch.isEmpty ? _items : _items.where((item) =>
      item.title.toLowerCase().contains(normalizedSearch) ||
      _localizedPreviewText(item.subtitle).toLowerCase().contains(normalizedSearch)).toList();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_t.messages, style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.publicExplore,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ChannelsScreen(),
            )),
            icon: const Icon(Icons.campaign_outlined),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.joinGroupWithInvite,
            onPressed: _joinGroupByInvite,
            icon: const Icon(Icons.key_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.createGroup,
            onPressed: _newGroup,
            icon: const Icon(Icons.group_add_outlined),
          )),
          HomaGramSpringPress(child: IconButton(
            tooltip: _t.newConversation,
            onPressed: _newChat,
            icon: const Icon(Icons.edit_outlined),
          )),
          const SizedBox(width: 8),
        ],
      ),
      body: HomaGramEntrance(child: Column(
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
                          Flexible(child: Text(_t.homagramSupport,
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
                          SizedBox(width: 6),
                          Icon(Icons.verified_rounded, size: 16, color: Color(0xFF65D9F0)),
                        ]),
                        SizedBox(height: 5),
                        Text(_t.directSupportContact,
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
                  child: HomaGramSpringPress(child: TextButton.icon(
                    onPressed: _openSupportInbox,
                    icon: const Icon(Icons.inbox_outlined, size: 18),
                    label: Text(_t.manageSupportRequests),
                  )),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchTerm = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: _t.searchConversationsGroupsChannels,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchTerm.isEmpty ? null : IconButton(
                  onPressed: () { _searchController.clear(); setState(() => _searchTerm = ''); },
                  icon: const Icon(Icons.close_rounded),
                ),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: _showArchived
                ? Padding(
                    key: const ValueKey('archived-mode'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(children: [
                      const Icon(Icons.archive_rounded, size: 19),
                      const SizedBox(width: 8),
                      const Expanded(child: Text(_t.archivedConversations,
                        style: TextStyle(fontWeight: FontWeight.w800))),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _showArchived = false);
                          _load();
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text(_t.back),
                      ),
                    ]),
                  )
                : const SizedBox(key: ValueKey('active-inbox'), height: 2),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (!_showArchived) {
                  setState(() => _showArchived = true);
                }
                await _load();
              },
              child: _loading
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                      SizedBox(height: 125),
                      Center(child: CircularProgressIndicator()),
                    ])
                  : _error != null
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                          const SizedBox(height: 120),
                          Center(child: Text(_error!)),
                          Center(child: HomaGramSpringPress(child: TextButton(onPressed: _load, child: const Text(_t.tryAgain)))),
                        ])
                      : _items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 75),
                                Icon(Icons.forum_outlined, size: 58, color: colors.primary),
                                const SizedBox(height: 16),
                                Center(child: Text(_searchTerm.isEmpty ? _t.noConversationsYet : _t.conversationSearchEmpty,
                                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                                const SizedBox(height: 8),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 42),
                                  child: Text(_t.startPrivateConversationHint,
                                    textAlign: TextAlign.center),
                                ),
                                const SizedBox(height: 18),
                                Center(child: HomaGramSpringPress(child: FilledButton.icon(
                                  onPressed: _newChat,
                                  icon: const Icon(Icons.add_comment_outlined),
                                  label: const Text(_t.startNewConversation, style: TextStyle(fontFamily: 'Estedad')),
                                ))),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: visibleItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                              itemBuilder: (context, index) {
                                final item = visibleItems[index];
                                return Dismissible(
                                  key: ValueKey('conversation-${item.id}-$_showArchived'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) async {
                                    try {
                                      await MessagingService.setConversationArchived(
                                        item.id,
                                        archived: !_showArchived,
                                      );
                                      await _load();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                          content: Text(_showArchived
                                              ? _t.conversationRestored
                                              : _t.conversationArchived),
                                        ));
                                      }
                                    } catch (_) {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text(_t.archiveStatusUpdateFailed)),
                                      );
                                    }
                                    return false;
                                  },
                                  background: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 22),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: .14),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(_showArchived ? Icons.unarchive_rounded : Icons.archive_rounded,
                                      color: colors.primary),
                                  ),
                                  child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: colors.primaryContainer,
                                    backgroundImage: item.photoUrl != null
                                        ? NetworkImage(item.photoUrl!)
                                        : null,
                                    child: item.photoUrl == null
                                        ? Icon(
                                            item.kind == 'group'
                                                ? Icons.groups_rounded
                                                : item.kind == 'channel'
                                                    ? Icons.campaign_rounded
                                                    : Icons.person_rounded,
                                            color: colors.onPrimaryContainer,
                                          )
                                        : null,
                                  ),
                                  title: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Flexible(child: Text(_localizedPreviewText(item.title), maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800))),
                                    const SizedBox(width: 4),
                                    HomaGramVerifiedBadge(userId: item.peerUserId),
                                  ]),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(_localizedPreviewText(item.subtitle), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  trailing: Text(_date(item.updatedAt), style: Theme.of(context).textTheme.labelSmall),
                                  onLongPress: () => _showConversationActions(item),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => ChatScreen(conversationId: item.id, title: item.title),
                                  )),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      )),
    );
  }

  Future<void> _showConversationActions(ConversationPreview item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(_showArchived ? Icons.unarchive_rounded : Icons.archive_outlined),
            title: Text(_showArchived ? _t.restoreToInbox : _t.archiveConversation),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            title: Text(
              item.kind == 'direct' ? _t.deleteConversation :
              item.kind == 'group' ? _t.leaveGroupRemoveFromList : _t.leaveChannelRemoveFromList,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
            onTap: () => Navigator.pop(sheetContext, 'leave'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'archive') {
      try {
        await MessagingService.setConversationArchived(item.id, archived: !_showArchived);
        await _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_showArchived ? _t.conversationRestored : _t.conversationArchived),
        ));
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_t.conversationStatusUpdateFailed)),
        );
      }
      return;
    }

    final label = item.kind == 'direct' ? _t.deleteConversation :
        item.kind == 'group' ? _t.leaveGroup : _t.leaveChannel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: Text(item.kind == 'direct'
          ? _t.deleteConversationExplanation
          : _t.leaveConversationExplanation(item.kind == 'group' ? _t.group : _t.channel)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text(_t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MessagingService.leaveConversation(item.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(item.kind == 'direct' ? _t.conversationRemoved : _t.leftConversation),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_t.deleteConversationFailed)),
      );
    }
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
      if (mounted) setState(() => _error = _t.searchFailed);
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
          _error = _t.startConversationRestricted;
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
          const Text(_t.newConversation, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: _find,
            decoration: InputDecoration(
              hintText: _t.searchByUsername,
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
              child: Center(child: Text(_t.userSearchEmpty)),
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
                    title: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(user['display_name'] as String? ?? user['username'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      HomaGramVerifiedBadge(userId: user['id'] as String?),
                    ]),
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
  final _slug = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _users = [];
  bool _searching = false, _creating = false, _isPublic = false;
  String? _error;

  Future<void> _find(String value) async {
    if (value.trim().length < 2) {
      setState(() => _users = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final users = await MessagingService.searchUsers(value);
      if (mounted) setState(() { _users = users; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = _t.userSearchFailed);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = _t.enterGroupName);
      return;
    }
    if (_isPublic && !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(_slug.text.trim())) {
      setState(() => _error = _t.publicGroupSlugRules);
      return;
    }
    setState(() { _creating = true; _error = null; });
    try {
      final id = _isPublic
          ? await MessagingService.createPublicGroup(
              title: _title.text,
              slug: _slug.text,
              description: _description.text,
              memberIds: _selected.toList(),
            )
          : await MessagingService.createGroupConversation(
              title: _title.text,
              memberIds: _selected.toList(),
            );
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) setState(() {
        _creating = false;
        _error = _isPublic
            ? _t.publicGroupCreateFailed
            : _t.groupCreateFailed;
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _search.dispose();
    _slug.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(_t.createNewGroup, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: _title, maxLength: 100,
              decoration: const InputDecoration(labelText: _t.groupName, prefixIcon: Icon(Icons.groups_outlined))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: _creating ? null : (value) => setState(() => _isPublic = value),
              title: Text(_isPublic ? _t.publicGroup : _t.privateGroup),
              subtitle: Text(_isPublic
                  ? _t.publicGroupDiscoverableHint
                  : _t.privateGroupAccessHint),
              secondary: Icon(_isPublic ? Icons.public_rounded : Icons.lock_outline_rounded),
            ),
            if (_isPublic) ...[
              TextField(
                controller: _slug,
                maxLength: 32,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: _t.publicGroupSlug,
                  prefixText: '@',
                  helperText: _t.slugRules,
                ),
              ),
              TextField(
                controller: _description,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(labelText: _t.groupDescriptionOptional),
              ),
            ],
            const SizedBox(height: 8),
            TextField(controller: _search, onChanged: _find,
              decoration: const InputDecoration(hintText: _t.searchMembersByUsername, prefixIcon: Icon(Icons.search_rounded))),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            if (_selected.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_t.membersSelected(_selected.length))),
            if (_users.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
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
              child: HomaGramSpringPress(child: FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: _creating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.group_add_rounded),
                label: Text(_isPublic ? _t.createPublicGroup : _t.createPrivateGroup),
              )),
            ),
          ],
        ),
      ),
    );
  }
}
