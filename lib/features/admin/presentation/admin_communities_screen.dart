import 'dart:async';

import 'package:flutter/material.dart';

import '../data/admin_service.dart';

class AdminCommunitiesScreen extends StatefulWidget {
  const AdminCommunitiesScreen({super.key});

  @override
  State<AdminCommunitiesScreen> createState() => _AdminCommunitiesScreenState();
}

class _AdminCommunitiesScreenState extends State<AdminCommunitiesScreen> {
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
        _error = 'دریافت فهرست گروه‌ها و کانال‌ها انجام نشد.';
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
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (requiredText && text.length < 8) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    if (requiredText && value.length < 8) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('متن اخطار باید حداقل ۸ نویسه داشته باشد.')),
      );
      return null;
    }
    return value;
  }

  Future<void> _confirmDelete(AdminCommunitySummary item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.kind == 'group' ? 'حذف کامل گروه' : 'حذف کامل کانال'),
        content: Text(
          '«${item.title}» و تمام پیام‌ها و عضویت‌های آن برای همه اعضا حذف می‌شود. این عملیات قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف برای همه'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(item, 'delete');
  }

  Future<void> _warn(AdminCommunitySummary item) async {
    final message = await _messageDialog(
      title: 'ارسال اخطار به ${item.kind == 'group' ? 'گروه' : 'کانال'}',
      label: 'متن اخطار برای همه اعضا',
      requiredText: true,
    );
    if (message == null) return;
    await _run(item, 'warn', message: message);
  }

  Future<void> _block(AdminCommunitySummary item) async {
    final reason = await _messageDialog(
      title: 'مسدودسازی ${item.kind == 'group' ? 'گروه' : 'کانال'}',
      label: 'دلیل مسدودسازی (اختیاری)',
    );
    if (reason == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأیید مسدودسازی'),
        content: const Text('با این کار ارسال پیام جدید در این گروه یا کانال برای همه اعضا متوقف می‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('بازگشت'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسدودسازی'),
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
        'warn' => 'اخطار برای اعضای گروه یا کانال ارسال شد.',
        'block' => 'گروه یا کانال مسدود شد.',
        'unblock' => 'محدودیت گروه یا کانال برداشته شد.',
        'delete' => 'گروه یا کانال حذف شد.',
        _ => 'عملیات مدیریتی انجام شد.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (error) {
      debugPrint('Admin community action failed: $error');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عملیات انجام نشد. دسترسی مدیر و اتصال را بررسی کنید.')),
      );
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  String _date(DateTime? date) {
    if (date == null) return 'تاریخ نامشخص';
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
                  hintText: 'جست‌وجوی نام، شناسه یا مالک',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'پاک کردن',
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
                  const Expanded(
                    child: Text('مدیریت گروه‌ها و کانال‌ها',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    tooltip: 'به‌روزرسانی',
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
                      label: const Text('همه'),
                      selected: _kind == 'all',
                      onSelected: (_) {
                        setState(() => _kind = 'all');
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('گروه‌ها'),
                      selected: _kind == 'group',
                      onSelected: (_) {
                        setState(() => _kind = 'group');
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('کانال‌ها'),
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
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _load(reset: true),
                          child: const Text('تلاش دوباره'),
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
                                Center(child: Text('گروه یا کانالی پیدا نشد.')),
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
                                        child: Text(_loading ? 'در حال دریافت…' : 'نمایش موارد بیشتر'),
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
                                        : 'مالک نامشخص';
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
                                              '${isGroup ? 'گروه' : 'کانال'} • ${item.isPublic ? 'عمومی' : 'خصوصی'} • ${item.memberCount} عضو',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 3),
                                            Text('مالک: $owner • ${_date(item.createdAt)}',
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (item.slug?.isNotEmpty == true)
                                              Text('@${item.slug}', textDirection: TextDirection.ltr,
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (item.isBlocked && item.blockReason?.isNotEmpty == true)
                                              Text('دلیل مسدودسازی: ${item.blockReason}',
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
                                              tooltip: 'اقدامات مدیریتی',
                                              onSelected: (action) {
                                                if (action == 'warn') _warn(item);
                                                if (action == 'block') _block(item);
                                                if (action == 'unblock') _run(item, 'unblock');
                                                if (action == 'delete') _confirmDelete(item);
                                              },
                                              itemBuilder: (_) => [
                                                const PopupMenuItem(
                                                  value: 'warn',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(Icons.warning_amber_rounded),
                                                    title: Text('ارسال اخطار'),
                                                  ),
                                                ),
                                                if (item.isBlocked)
                                                  const PopupMenuItem(
                                                    value: 'unblock',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(Icons.lock_open_rounded),
                                                      title: Text('رفع مسدودسازی'),
                                                    ),
                                                  )
                                                else
                                                  const PopupMenuItem(
                                                    value: 'block',
                                                    child: ListTile(
                                                      dense: true,
                                                      leading: Icon(Icons.block_rounded, color: Colors.orange),
                                                      title: Text('مسدودسازی'),
                                                    ),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(Icons.delete_forever_outlined, color: Colors.red),
                                                    title: Text('حذف کامل'),
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
                                                Text('شناسه: ${item.id}', textDirection: TextDirection.ltr),
                                                const SizedBox(height: 8),
                                                Text(item.description?.isNotEmpty == true
                                                  ? item.description! : 'توضیحاتی ثبت نشده است.'),
                                                const SizedBox(height: 8),
                                                Text('تعداد اعضای فعال: ${item.memberCount}'),
                                                const SizedBox(height: 8),
                                                Text('وضعیت: ${item.isBlocked ? 'مسدود' : 'فعال'}'),
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
