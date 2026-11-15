import 'dart:async';

import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../data/admin_service.dart';

class AdminCommunitiesScreen extends StatefulWidget {
  const AdminCommunitiesScreen({super.key});

  @override
  State<AdminCommunitiesScreen> createState() => _AdminCommunitiesScreenState();
}

class _AdminCommunitiesScreenState extends State<AdminCommunitiesScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<AdminCommunitySummary> _items = [];
  String _kind = 'all';
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

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _hasMore = true;
        _items.clear();
      }
    });
    try {
      final rows = await AdminService.loadCommunities(
        kind: _kind,
        search: _search.text,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == 50;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Admin communities load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _t.adminCommunitiesLoadFailed;
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  Future<String?> _messageDialog({
    required String title,
    required String label,
    String initial = '',
    bool requiredText = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (requiredText && text.length < 8) return;
              Navigator.pop(dialogContext, text);
            },
            child: Text('تأیید'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    if (requiredText && value.length < 8) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminCommunityWarningMinLength)),
      );
      return null;
    }
    return value;
  }

  Future<void> _confirmDelete(AdminCommunitySummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.kind == 'group' ? _t.adminCommunityDeleteGroupTitle : _t.adminCommunityDeleteChannelTitle),
        content: Text(
          _t.adminCommunityDeleteDescription(item.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t.adminCommunityDeleteForEveryone),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(item, 'delete');
  }

  Future<void> _warn(AdminCommunitySummary item) async {
    final message = await _messageDialog(
      title: _t.adminCommunityWarnTitle(item.kind == 'group' ? _t.adminCommunityGroup : _t.adminCommunityChannel),
      label: _t.adminCommunityWarningLabel,
      requiredText: true,
    );
    if (message == null) return;
    await _run(item, 'warn', message: message);
  }

  Future<void> _block(AdminCommunitySummary item) async {
    final reason = await _messageDialog(
      title: _t.adminCommunityBlockTitle(item.kind == 'group' ? _t.adminCommunityGroup : _t.adminCommunityChannel),
      label: _t.adminCommunityBlockReasonOptional,
    );
    if (reason == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t.adminCommunityConfirmBlockTitle),
        content: Text(_t.adminCommunityBlockDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('بازگشت'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t.adminCommunityBlock),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(item, 'block', message: reason);
  }

  Future<void> _run(
    AdminCommunitySummary item,
    String action, {
    String? message,
  }) async {
    if (_working != null) return;
    setState(() => _working = item.id);
    try {
      await AdminService.moderateCommunity(
        conversationId: item.id,
        action: action,
        message: message,
      );
      if (!mounted) return;
      if (action == 'delete') {
        _items.removeWhere((x) => x.id == item.id);
      } else {
        await _load(reset: true);
      }
      if (!mounted) return;
      final text = switch (action) {
        'warn' => _t.adminCommunityWarnSent,
        'block' => _t.adminCommunityBlocked,
        'unblock' => _t.adminCommunityUnblocked,
        'delete' => _t.adminCommunityDeleted,
        _ => _t.adminActionCompleted,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (error) {
      debugPrint('Admin community action failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminCommunityActionFailed)),
      );
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  String _date(DateTime? date) {
    if (date == null) return _t.adminUnknownTime;
    final d = date.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: _searchChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _load(reset: true);
                },
                decoration: InputDecoration(
                  hintText: _t.adminCommunitySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: _t.adminClearSearch,
                          onPressed: () {
                            _search.clear();
                            _load(reset: true);
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(_t.adminCommunities,
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    tooltip: _t.adminRefresh,
                    onPressed: () => _load(reset: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(_t.adminFilterAll),
                      selected: _kind == 'all',
                      onSelected: (_) {
                        setState(() => _kind = 'all');
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: Text(_t.adminCommunityGroups),
                      selected: _kind == 'group',
                      onSelected: (_) {
                        setState(() => _kind = 'group');
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: Text(_t.adminCommunityChannels),
                      selected: _kind == 'channel',
                      onSelected: (_) {
                        setState(() => _kind = 'channel');
                        _load(reset: true);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading && _items.isEmpty
              ? Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _load(reset: true),
                          child: Text(_t.adminRetry),
                        ),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: _items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 100),
                                Icon(Icons.groups_2_outlined, size: 48),
                                SizedBox(height: 12),
                                Center(child: Text(_t.adminNoCommunitiesFound)),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                              itemCount: _items.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                if (index == _items.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: TextButton(
                                        onPressed: _loading ? null : () => _load(),
                                        child: Text(_loading ? _t.adminModerationLoading : _t.adminModerationShowMore),
                                      ),
                                    ),
                                  );
                                }
                                final item = _items[index];
                                final isGroup = item.kind == 'group';
                                final owner = item.ownerDisplayName?.trim().isNotEmpty == true
                                    ? item.ownerDisplayName!
                                    : item.ownerUsername?.trim().isNotEmpty == true
                                        ? '@${item.ownerUsername}'
                                        : _t.adminCommunityUnknownOwner;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: (isGroup
                                          ? const Color(0xFF7356C8)
                                          : const Color(0xFF20B8B0)).withValues(alpha: .16),
                                        child: Icon(
                                          isGroup ? Icons.groups_rounded : Icons.campaign_rounded,
                                          color: isGroup ? const Color(0xFF9B83FF) : const Color(0xFF20B8B0),
                                        ),
                                      ),
                                      title: Row(children: [
                                        Expanded(
                                          child: Text(item.title, maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w900)),
                                        ),
                                        if (item.isBlocked)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Icon(Icons.block_rounded, color: Colors.red, size: 17),
                                          ),
                                      ]),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _t.adminCommunitySummary(isGroup ? _t.adminCommunityGroup : _t.adminCommunityChannel, item.isPublic ? _t.adminCommunityPublic : _t.adminCommunityPrivate, item.memberCount),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 3),
                                            Text(_t.adminCommunityOwnerDate(owner, _date(item.createdAt)),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (item.slug?.isNotEmpty == true)
                                              Text('@${item.slug}', textDirection: TextDirection.ltr,
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (item.isBlocked && item.blockReason?.isNotEmpty == true)
                                              Text(_t.adminCommunityBlockReason(item.blockReason!),
                                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: colors.error)),
                                          ],
                                        ),
                                      ),
                                      trailing: _working == item.id
                                          ? const SizedBox(
                                              width: 24, height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2))
                                          : PopupMenuButton<String>(
                                              tooltip: _t.adminCommunityActions,
                                              onSelected: (action) {
                                                if (action == 'warn') _warn(item);
                                                if (action == 'block') _block(item);
                                                if (action == 'unblock') _run(item, 'unblock');
                                                if (action == 'delete') _confirmDelete(item);
                                              },
                                              itemBuilder: (_) => [
                                                PopupMenuItem(
                                                  value: 'warn',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(Icons.warning_amber_rounded),
                                                    title: Text(_t.adminModerationSendWarning),
                                                  ),
                                                ),
                                                if (item.isBlocked)
                                                  PopupMenuItem(
                                                    value: 'unblock',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(Icons.lock_open_rounded),
                                                      title: Text(_t.adminCommunityUnblock),
                                                    ),
                                                  )
                                                else
                                                  PopupMenuItem(
                                                    value: 'block',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(Icons.block_rounded, color: Colors.orange),
                                                      title: Text(_t.adminCommunityBlock),
                                                    ),
                                                  ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(Icons.delete_forever_outlined, color: Colors.red),
                                                    title: Text(_t.adminCommunityDeleteCompletely),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      onTap: () => showModalBottomSheet<void>(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (ctx) => SafeArea(
                                          child: Padding(
                                            padding: const EdgeInsets.all(18),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item.title,
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                                const SizedBox(height: 8),
                                                Text(_t.adminCommunityId(item.id), textDirection: TextDirection.ltr),
                                                const SizedBox(height: 8),
                                                Text(item.description?.isNotEmpty == true
                                                  ? item.description! : _t.adminCommunityNoDescription),
                                                const SizedBox(height: 8),
                                                Text(_t.adminCommunityActiveMembers(item.memberCount)),
                                                const SizedBox(height: 8),
                                                Text(_t.adminCommunityStatus(item.isBlocked ? _t.adminCommunityBlockedStatus : _t.adminCommunityActiveStatus)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}
