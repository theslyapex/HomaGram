import 'dart:async';
import 'package:flutter/material.dart';
import '../data/admin_service.dart';
import 'admin_user_detail_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت هماگرام', style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: const TabBar(isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.dashboard_outlined), text: 'نمای کلی'),
          Tab(icon: Icon(Icons.people_alt_outlined), text: 'کاربران'),
          Tab(icon: Icon(Icons.flag_outlined), text: 'گزارش پست‌ها'),
          Tab(icon: Icon(Icons.chat_bubble_outline), text: 'گزارش پیام‌ها'),
          Tab(icon: Icon(Icons.history_rounded), text: 'سوابق مدیران'),
        ]),
      ),
      body: const TabBarView(children: [
        _OverviewTab(), _UsersTab(), _ReportsTab(), _MessageReportsTab(), _AuditLogsTab(),
      ]),
    ),
  );
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  AdminDashboardStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AdminService.loadStats();
      if (!mounted) return;
      setState(() { _stats = result; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت آمار مدیریتی انجام نشد.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    final s = _stats!;
    final entries = <_Metric>[
      _Metric('کاربران', s.users, Icons.people_alt_outlined),
      _Metric('پست‌ها', s.posts, Icons.grid_view_rounded),
      _Metric('استوری‌ها', s.stories, Icons.auto_awesome_outlined),
      _Metric('ریلز', s.reels, Icons.video_collection_outlined),
      _Metric('پیام‌ها', s.messages, Icons.chat_bubble_outline_rounded),
      _Metric('گروه‌ها', s.groups, Icons.groups_outlined),
      _Metric('کانال‌ها', s.channels, Icons.campaign_outlined),
      _Metric('گزارش‌های در انتظار', s.pendingPostReports, Icons.flag_outlined),
      _Metric('پشتیبانی باز', s.openSupportConversations, Icons.support_agent_rounded),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 700 ? 3 : 2;
        final width = (box.maxWidth - 32 - (columns - 1) * 10) / columns;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topRight, end: Alignment.bottomLeft,
                  colors: [Color(0xFF14213D), Color(0xFF283E67)],
                ),
              ),
              child: const Row(children: [
                Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF55D6D0), size: 34),
                SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مرکز کنترل هماگرام', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    SizedBox(height: 5),
                    Text('مدیریت کاربران، محتوا و گزارش‌ها',
                      style: TextStyle(color: Color(0xFFD4E1F5), fontSize: 12)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 18),
            Text('آمار کلی', style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [for (final item in entries)
                SizedBox(width: width, child: _MetricCard(item: item))],
            ),
            const SizedBox(height: 18),
            const Text(
              'آمار مستقیماً از دیتابیس خوانده می‌شود؛ مجوزها در سمت سرور کنترل می‌شوند.',
              style: TextStyle(fontSize: 12, height: 1.7, color: Color(0xFF7A879B)),
            ),
          ],
        );
      }),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});
  final _Metric item;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(item.icon, color: colors.primary, size: 22),
          const SizedBox(height: 12),
          Text(item.value.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _search = TextEditingController();
  Timer? _timer;
  List<AdminUserSummary> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _timer?.cancel(); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AdminService.loadUsers(search: _search.text);
      if (!mounted) return;
      setState(() { _users = result; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت فهرست کاربران انجام نشد.'; });
    }
  }

  void _searchChanged(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: TextField(
        controller: _search,
        onChanged: _searchChanged,
        decoration: InputDecoration(
          hintText: 'جست‌وجوی نام یا نام کاربری',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'پاک‌کردن',
            onPressed: () { _search.clear(); _load(); },
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ),
    ),
    Expanded(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? _RetryView(message: _error!, onRetry: _load)
        : RefreshIndicator(
            onRefresh: _load,
            child: _users.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                  SizedBox(height: 100), Icon(Icons.person_search_outlined, size: 48),
                  SizedBox(height: 12), Center(child: Text('کاربری پیدا نشد.')),
                ])
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _UserCard(user: _users[i]),
                ),
          ),
    ),
  ]);
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final AdminUserSummary user;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = user.displayName?.trim().isNotEmpty == true
      ? user.displayName!.trim()
      : (user.username?.trim().isNotEmpty == true ? '@${user.username}' : 'کاربر هماگرام');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AdminUserDetailScreen(userId: user.id),
        )),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: colors.primaryContainer,
            child: Icon(Icons.person_outline_rounded, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('@${user.username ?? 'بدون نام کاربری'}',
                textDirection: TextDirection.ltr, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                'شناسه: ${user.id.substring(0, 8)}…  •  عضویت: ${_adminDate(user.createdAt)}',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
            ],
          )),
          const SizedBox(width: 8),
          Icon(user.isBanned ? Icons.block_rounded : Icons.verified_user_outlined,
            color: user.isBanned ? colors.error : const Color(0xFF20A77A)),
        ]),
        ),
      ),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  List<AdminPostReport> _reports = [];
  bool _loading = true;
  String? _error;
  String? _workingId;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AdminService.loadReports();
      if (!mounted) return;
      setState(() { _reports = result; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت گزارش‌ها انجام نشد.'; });
    }
  }

  Future<void> _review(AdminPostReport report, String status) async {
    if (_workingId != null) return;
    setState(() => _workingId = report.id);
    try {
      await AdminService.reviewReport(report.id, status);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت نتیجه بررسی گزارش انجام نشد.')),
      );
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _reports.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
            SizedBox(height: 110), Icon(Icons.task_alt_rounded, size: 48, color: Color(0xFF20A77A)),
            SizedBox(height: 12), Center(child: Text('گزارش ثبت‌شده‌ای وجود ندارد.')),
          ])
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: _reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final report = _reports[i];
              final pending = report.status == 'pending';
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(_reasonLabel(report.reason),
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                      _ReportStatus(status: report.status),
                    ]),
                    const SizedBox(height: 9),
                    Text(report.postCaption?.trim().isNotEmpty == true
                      ? report.postCaption!.trim() : 'پست بدون توضیح',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (report.details?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text('توضیح گزارش: ${report.details}',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'شناسه پست: ${report.postId.substring(0, 8)}…  •  ${_adminDate(report.createdAt)}',
                      style: Theme.of(context).textTheme.labelSmall),
                    if (report.reviewNote?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text('یادداشت مدیر: ${report.reviewNote}',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (pending) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'dismissed'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('رد گزارش'),
                        ),
                        FilledButton.icon(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'reviewed'),
                          icon: _workingId == report.id
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_rounded, size: 18),
                          label: const Text('بررسی شد'),
                        ),
                        FilledButton.tonal(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'actioned'),
                          child: const Text('اقدام انجام شد'),
                        ),
                      ]),
                    ],
                  ]),
                ),
              );
            },
          ),
    );
  }
}

class _MessageReportsTab extends StatefulWidget {
  const _MessageReportsTab();
  @override
  State<_MessageReportsTab> createState() => _MessageReportsTabState();
}
class _MessageReportsTabState extends State<_MessageReportsTab> {
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _working;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AdminService.loadMessageReports();
      if (!mounted) return;
      setState(() { _items = result; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت گزارش پیام‌ها انجام نشد.'; });
    }
  }
  Future<void> _review(Map<String,dynamic> item, String status) async {
    final id = item['report_id'] as String;
    if (_working != null) return;
    setState(() => _working = id);
    try {
      await AdminService.reviewMessageReport(id, status);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت نتیجه بررسی انجام نشد.')));
    } finally { if (mounted) setState(() => _working = null); }
  }
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
            SizedBox(height: 100), Icon(Icons.verified_outlined, size: 48),
            SizedBox(height: 12), Center(child: Text('گزارش پیام ثبت نشده است.')),
          ])
        : ListView.separated(
            padding: const EdgeInsets.all(14), itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = _items[index];
              final id = item['report_id'] as String;
              final pending = item['status'] == 'pending';
              return Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_messageReason(item['reason']?.toString() ?? ''),
                      style: const TextStyle(fontWeight: FontWeight.w900))),
                    _ReportStatus(status: item['status']?.toString() ?? 'pending'),
                  ]),
                  const SizedBox(height: 8),
                  Text((item['message_body'] as String?)?.trim().isNotEmpty == true
                    ? item['message_body'] as String : 'پیام بدون متن یا دارای پیوست',
                    maxLines: 5, overflow: TextOverflow.ellipsis),
                  if ((item['details'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 7), Text('توضیح: ${item['details']}'),
                  ],
                  const SizedBox(height: 7),
                  Text('شناسه پیام: ${item['message_id']}',
                    style: Theme.of(context).textTheme.labelSmall),
                  Text('شناسه گزارش‌دهنده: ${item['reporter_id']}',
                    style: Theme.of(context).textTheme.labelSmall),
                  if (pending) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, children: [
                      OutlinedButton(onPressed: _working == id ? null : () => _review(item,'dismissed'),
                        child: const Text('رد گزارش')),
                      FilledButton(onPressed: _working == id ? null : () => _review(item,'reviewed'),
                        child: const Text('بررسی شد')),
                      FilledButton.tonal(onPressed: _working == id ? null : () => _review(item,'actioned'),
                        child: const Text('اقدام انجام شد')),
                    ]),
                  ],
                ]),
              ));
            },
          ),
    );
  }
}
String _messageReason(String value) => switch(value) {
  'spam' => 'هرزنامه', 'harassment' => 'آزار و اذیت', 'threat' => 'تهدید',
  'privacy' => 'نقض حریم خصوصی', 'inappropriate' => 'محتوای نامناسب', 'other' => 'سایر موارد', _ => value,
};

class _ReportStatus extends StatelessWidget {
  const _ReportStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'pending'
      ? const Color(0xFFE29A31)
      : status == 'dismissed'
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : const Color(0xFF20A77A);
    final label = switch (status) {
      'pending' => 'در انتظار',
      'dismissed' => 'رد شده',
      'actioned' => 'اقدام شده',
      'reviewed' => 'بررسی شده',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}


class _AuditLogsTab extends StatefulWidget {
  const _AuditLogsTab();
  @override
  State<_AuditLogsTab> createState() => _AuditLogsTabState();
}

class _AuditLogsTabState extends State<_AuditLogsTab> {
  List<AdminAuditLog> _logs = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AdminService.loadAuditLogs();
      if (!mounted) return;
      setState(() { _logs = result; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت سوابق مدیریتی انجام نشد.'; });
    }
  }

  String _date(DateTime? value) {
    if (value == null) return 'زمان نامشخص';
    final d = value.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _label(String action) => switch (action) {
    'post_report_reviewed' => 'بررسی گزارش پست',
    'message_report_reviewed' => 'بررسی گزارش پیام',
    'user_suspended' => 'محدودسازی حساب',
    'user_unsuspended' => 'رفع محدودیت حساب',
    _ => action.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _logs.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
            SizedBox(height: 110), Icon(Icons.history_rounded, size: 46),
            SizedBox(height: 12), Center(child: Text('هنوز سابقه مدیریتی ثبت نشده است.')),
          ])
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: _logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = _logs[index];
              final actor = log.actorDisplayName?.trim().isNotEmpty == true
                ? log.actorDisplayName! : (log.actorUsername == null ? 'مدیر' : '@${log.actorUsername}');
              final target = log.targetDisplayName?.trim().isNotEmpty == true
                ? log.targetDisplayName! : (log.targetUsername == null ? null : '@${log.targetUsername}');
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.admin_panel_settings_outlined, size: 19),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_label(log.action),
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 7),
                    Text('مدیر اجراکننده: $actor', style: Theme.of(context).textTheme.bodySmall),
                    if (target != null) Text('کاربر مرتبط: $target',
                      style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(_date(log.createdAt), style: Theme.of(context).textTheme.labelSmall),
                    if (log.metadata.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('جزئیات: ${log.metadata.entries.map((e) => '${e.key}: ${e.value}').join('  •  ')}',
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 5),
                    Text('شناسه مدیر: ${log.actorId}',
                      textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.labelSmall),
                    if (log.targetUserId != null)
                      Text('شناسه کاربر: ${log.targetUserId}',
                        textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ),
              );
            },
          ),
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ]),
    ),
  );
}

String _reasonLabel(String reason) => switch (reason) {
  'spam' => 'هرزنامه',
  'harassment' => 'آزار و اذیت',
  'misinformation' => 'اطلاعات نادرست',
  'inappropriate' => 'محتوای نامناسب',
  'other' => 'سایر موارد',
  _ => reason,
};

String _adminDate(DateTime? date) {
  if (date == null) return 'نامشخص';
  final d = date.toLocal();
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
