import 'package:homagram/app/presentation/homagram_branding.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/admin_service.dart';
import 'admin_user_detail_screen.dart';
import 'admin_verification_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_communities_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return DefaultTabController(
    length: 8,
    child: Scaffold(
      appBar: AppBar(
        title: Text(t.adminTitle, style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: TabBar(isScrollable: true, tabs: [
          Tab(icon: Icon(Icons.dashboard_outlined), text: t.adminOverview),
          Tab(icon: Icon(Icons.people_alt_outlined), text: t.adminUsers),
          Tab(icon: Icon(Icons.visibility_outlined), text: t.adminContentModeration),
          Tab(icon: Icon(Icons.flag_outlined), text: t.adminPostReports),
          Tab(icon: Icon(Icons.chat_bubble_outline), text: t.adminMessageReports),
          Tab(icon: Icon(Icons.history_rounded), text: t.adminAuditLogs),
          Tab(icon: Icon(Icons.verified_user_outlined), text: t.adminVerificationTab),
          Tab(icon: Icon(Icons.groups_2_outlined), text: t.adminCommunities),
        ]),
      ),
      body: const HomaGramEntrance(child: TabBarView(children: [
        _OverviewTab(), _UsersTab(), AdminModerationScreen(), _ReportsTab(), _MessageReportsTab(), _AuditLogsTab(), _VerificationTab(), AdminCommunitiesScreen(),
      ])),
    ),
    );
  }
}

class _VerificationTab extends StatelessWidget {
  const _VerificationTab();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.verified_user_rounded, size: 52, color: Color(0xFF3195F5)),
      const SizedBox(height: 12),
      Text(t.adminVerificationHeading, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      const SizedBox(height: 8),
      Text(t.adminVerificationDescription, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const AdminVerificationScreen(),
        )),
        icon: const Icon(Icons.open_in_new_rounded),
        label: Text(t.adminVerificationOpenRequests),
      ),
    ]),
  ));
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
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
      setState(() { _loading = false; _error = _t.adminStatsLoadFailed; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    final s = _stats!;
    final entries = <_Metric>[
      _Metric(_t.adminMetricUsers, s.users, Icons.people_alt_outlined),
      _Metric(_t.adminMetricPosts, s.posts, Icons.grid_view_rounded),
      _Metric(_t.adminMetricStories, s.stories, Icons.auto_awesome_outlined),
      _Metric(_t.adminMetricReels, s.reels, Icons.video_collection_outlined),
      _Metric(_t.adminMetricMessages, s.messages, Icons.chat_bubble_outline_rounded),
      _Metric(_t.adminMetricGroups, s.groups, Icons.groups_outlined),
      _Metric(_t.adminMetricChannels, s.channels, Icons.campaign_outlined),
      _Metric(_t.adminMetricPendingReports, s.pendingPostReports, Icons.flag_outlined),
      _Metric(_t.adminMetricOpenSupport, s.openSupportConversations, Icons.support_agent_rounded),
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
              child: Row(children: [
                Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF55D6D0), size: 34),
                SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t.adminControlCenter, style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    SizedBox(height: 5),
                    Text(_t.adminControlCenterSubtitle,
                      style: TextStyle(color: Color(0xFFD4E1F5), fontSize: 12)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 18),
            Text(_t.adminOverallStats, style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [for (final item in entries)
                SizedBox(width: width, child: _MetricCard(item: item))],
            ),
            const SizedBox(height: 18),
            Text(
              _t.adminStatsSecurityNote,
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
  AppLocalizations get _t => AppLocalizations.of(context)!;
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
      setState(() { _loading = false; _error = _t.adminUsersLoadFailed; });
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
          hintText: _t.adminSearchUsersHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: HomaGramSpringPress(child: IconButton(
            tooltip: _t.adminClearSearch,
            onPressed: () { _search.clear(); _load(); },
            icon: const Icon(Icons.close_rounded),
          )),
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
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  SizedBox(height: 100), Icon(Icons.person_search_outlined, size: 48),
                  SizedBox(height: 12), Center(child: Text(_t.adminNoUsersFound)),
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
    final t = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final name = user.displayName?.trim().isNotEmpty == true
      ? user.displayName!.trim()
      : (user.username?.trim().isNotEmpty == true ? '@${user.username}' : t.adminUnknownUser);
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
            backgroundImage: user.avatarUrl?.isNotEmpty == true
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl?.isNotEmpty == true
                ? null
                : Icon(Icons.person_outline_rounded, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(width: 4),
                HomaGramVerifiedBadge(userId: user.id, size: 14),
              ]),
              const SizedBox(height: 4),
              Text('@${user.username ?? t.adminNoUsername}',
                textDirection: TextDirection.ltr, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                t.adminUserIdJoined(user.id.substring(0, 8), _adminDate(user.createdAt, t)),
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
  AppLocalizations get _t => AppLocalizations.of(context)!;
  List<AdminPostReport> _reports = [];
  bool _loading = true;
  String? _error;
  String? _workingId;
  String _filter = 'pending';

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
      setState(() { _loading = false; _error = _t.adminReportsLoadFailed; });
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
        SnackBar(content: Text(_t.adminReportReviewFailed)),
      );
    } finally {
      if (mounted) setState(() => _workingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    final visibleReports = _reports.where((report) {
      if (_filter == 'all') return true;
      if (_filter == 'pending') return report.status == 'pending';
      return report.status != 'pending';
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
        child: Row(children: [
          Expanded(child: Text(_t.adminPendingCount(_reports.where((r) => r.status == 'pending').length),
            style: const TextStyle(fontWeight: FontWeight.w800))),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'pending', label: Text(_t.adminFilterPending)),
              ButtonSegment(value: 'reviewed', label: Text(_t.adminFilterReviewed)),
              ButtonSegment(value: 'all', label: Text(_t.adminFilterAll)),
            ],
            selected: {_filter},
            onSelectionChanged: (value) => setState(() => _filter = value.first),
            showSelectedIcon: false,
          ),
        ]),
      ),
      Expanded(child: RefreshIndicator(
      onRefresh: _load,
      child: visibleReports.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            SizedBox(height: 110), Icon(Icons.task_alt_rounded, size: 48, color: Color(0xFF20A77A)),
            SizedBox(height: 12), Center(child: Text(_t.adminNoPostReports)),
          ])
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: visibleReports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final report = visibleReports[i];
              final pending = report.status == 'pending';
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(_reasonLabel(report.reason, _t),
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                      _ReportStatus(status: report.status),
                    ]),
                    const SizedBox(height: 9),
                    Text(report.postCaption?.trim().isNotEmpty == true
                      ? report.postCaption!.trim()  : _t.adminPostWithoutCaption,
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                    if (report.details?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(_t.adminReportDetails(report.details!),
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (report.rightsOwner != null) ...[
                      const SizedBox(height: 7),
                      Text(_t.adminRightsOwner(report.rightsOwner == 'self' ? _t.adminReporterClaimsOwnership : _t.adminThirdPartyOwnsWork),
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (report.rightsHolderName?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(_t.adminRightsHolderName(report.rightsHolderName!),
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (report.authorUsername?.isNotEmpty == true || report.postAuthorId != null) ...[
                      const SizedBox(height: 5),
                      Text(_t.adminContentOwner(report.authorDisplayName ?? _t.storyUserFallback, report.authorUsername ?? _t.adminUnknown),
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _t.adminPostIdDate(report.postId.substring(0, 8), _adminDate(report.createdAt, _t)),
                      style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 5),
                    Text(_t.adminReporterId(report.reporterId),
                      style: Theme.of(context).textTheme.labelSmall),
                    if (report.reviewNote?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(_t.adminManagerNote(report.reviewNote!),
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (pending) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        HomaGramSpringPress(child: OutlinedButton.icon(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'dismissed'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: Text(_t.adminDismissReport),
                        )),
                        HomaGramSpringPress(child: FilledButton.icon(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'reviewed'),
                          icon: _workingId == report.id
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_rounded, size: 18),
                          label: Text(_t.adminMarkReviewed),
                        )),
                        HomaGramSpringPress(child: FilledButton.tonal(
                          onPressed: _workingId == report.id ? null : () => _review(report, 'actioned'),
                          child: Text(_t.adminActionCompleted),
                        )),
                      ]),
                    ],
                  ]),
                ),
              );
            },
          ),
      )),
    ]);
  }
}

class _MessageReportsTab extends StatefulWidget {
  const _MessageReportsTab();
  @override
  State<_MessageReportsTab> createState() => _MessageReportsTabState();
}
class _MessageReportsTabState extends State<_MessageReportsTab> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  List<Map<String,dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _working;
  String _filter = 'pending';
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
      setState(() { _loading = false; _error = _t.adminMessageReportsLoadFailed; });
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
        SnackBar(content: Text(_t.adminReportReviewFailed)));
    } finally { if (mounted) setState(() => _working = null); }
  }
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    final visibleItems = _items.where((item) {
      if (_filter == 'all') return true;
      if (_filter == 'pending') return item['status'] == 'pending';
      return item['status'] != 'pending';
    }).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
        child: Row(children: [
          Expanded(child: Text(_t.adminPendingCount(_items.where((r) => r['status'] == 'pending').length),
            style: const TextStyle(fontWeight: FontWeight.w800))),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'pending', label: Text('بررسی‌نشده')),
              ButtonSegment(value: 'reviewed', label: Text('بررسی‌شده')),
              ButtonSegment(value: 'all', label: Text('همه')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) => setState(() => _filter = value.first),
            showSelectedIcon: false,
          ),
        ]),
      ),
      Expanded(child: RefreshIndicator(
      onRefresh: _load,
      child: visibleItems.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            SizedBox(height: 100), Icon(Icons.verified_outlined, size: 48),
            SizedBox(height: 12), Center(child: Text(_t.adminNoMessageReports)),
          ])
        : ListView.separated(
            padding: const EdgeInsets.all(14), itemCount: visibleItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              final id = item['report_id'] as String;
              final pending = item['status'] == 'pending';
              return Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_messageReason(item['reason']?.toString() ?? '', _t),
                      style: const TextStyle(fontWeight: FontWeight.w900))),
                    _ReportStatus(status: item['status']?.toString() ?? 'pending'),
                  ]),
                  const SizedBox(height: 8),
                  Text((item['message_body'] as String?)?.trim().isNotEmpty == true
                    ? item['message_body'] as String  : _t.adminMessageWithoutText,
                    maxLines: 5, overflow: TextOverflow.ellipsis),
                  if ((item['details'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 7), Text(_t.adminMessageReportDetails(item['details'])),
                  ],
                  const SizedBox(height: 7),
                  Text(_t.adminMessageId(item['message_id']),
                    style: Theme.of(context).textTheme.labelSmall),
                  Text(_t.adminReporterId(item['reporter_id']),
                    style: Theme.of(context).textTheme.labelSmall),
                  if (pending) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, children: [
                      HomaGramSpringPress(child: OutlinedButton(onPressed: _working == id ? null : () => _review(item,'dismissed'),
                        child: Text(_t.adminDismissReport))),
                      HomaGramSpringPress(child: FilledButton(onPressed: _working == id ? null : () => _review(item,'reviewed'),
                        child: Text(_t.adminMarkReviewed))),
                      HomaGramSpringPress(child: FilledButton.tonal(onPressed: _working == id ? null : () => _review(item,'actioned'),
                        child: Text(_t.adminActionCompleted))),
                    ]),
                  ],
                ]),
              ));
            },
          ),
      )),
    ]);
  }
}
String _messageReason(String value, AppLocalizations t) => switch(value) {
  'spam' => t.adminReasonSpam, 'harassment' => t.adminReasonHarassment, 'threat' => t.adminReasonThreat,
  'privacy' => t.adminReasonPrivacy, 'inappropriate' => t.adminReasonInappropriate, 'other' => t.adminReasonOther, _ => value,
};

class _ReportStatus extends StatelessWidget {
  const _ReportStatus({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final color = status == 'pending'
      ? const Color(0xFFE29A31)
      : status == 'dismissed'
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : const Color(0xFF20A77A);
    final label = switch (status) {
      'pending' => t.adminFilterPending,
      'dismissed' => t.adminStatusDismissed,
      'actioned' => t.adminStatusActioned,
      'reviewed' => t.adminFilterReviewed,
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status == 'pending') const Icon(Icons.pending_outlined, size: 13, color: Color(0xFFE29A31)),
        if (status == 'reviewed' || status == 'actioned') const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF20A77A)),
        if (status == 'dismissed') const Icon(Icons.remove_circle_outline_rounded, size: 13),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}


class _AuditLogsTab extends StatefulWidget {
  const _AuditLogsTab();
  @override
  State<_AuditLogsTab> createState() => _AuditLogsTabState();
}

class _AuditLogsTabState extends State<_AuditLogsTab> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
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
      setState(() { _loading = false; _error = _t.adminAuditLoadFailed; });
    }
  }

  String _date(DateTime? value) {
    if (value == null) return _t.adminUnknownTime;
    final d = value.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _label(String action) => switch (action) {
    'post_report_reviewed' => _t.adminAuditPostReportReviewed,
    'message_report_reviewed' => _t.adminAuditMessageReportReviewed,
    'user_suspended' => _t.adminAuditUserSuspended,
    'user_unsuspended' => _t.adminAuditUserUnsuspended,
    _ => action.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _RetryView(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _logs.isEmpty
        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            SizedBox(height: 110), Icon(Icons.history_rounded, size: 46),
            SizedBox(height: 12), Center(child: Text(_t.adminAuditEmpty)),
          ])
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(14),
            itemCount: _logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = _logs[index];
              final actor = log.actorDisplayName?.trim().isNotEmpty == true
                ? log.actorDisplayName! : (log.actorUsername == null ? _t.adminManager : '@${log.actorUsername}');
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
                    Text(_t.adminAuditActor(actor), style: Theme.of(context).textTheme.bodySmall),
                    if (target != null) Text(_t.adminAuditTarget(target),
                      style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(_date(log.createdAt), style: Theme.of(context).textTheme.labelSmall),
                    if (log.metadata.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_t.adminAuditDetails(log.metadata.entries.map((e) => '${e.key}: ${e.value}').join('  •  ')),
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 5),
                    Text(_t.adminAuditActorId(log.actorId),
                      textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.labelSmall),
                    if (log.targetUserId != null)
                      Text(_t.adminAuditTargetId(log.targetUserId!),
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
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        HomaGramSpringPress(child: FilledButton(onPressed: onRetry, child: Text(t.adminRetry))),
      ]),
    ),
    );
  }
}

String _reasonLabel(String reason, AppLocalizations t) => switch (reason) {
  'spam' => t.adminReasonSpam,
  'harassment' => t.adminReasonHarassment,
  'misinformation' => t.adminReasonMisinformation,
  'copied_content' => t.adminReasonCopiedContent,
  'copyright_claim' => t.adminReasonCopyright,
  'violence' => t.adminReasonViolence,
  'inappropriate' => t.adminReasonInappropriate,
  'political_insult' => t.adminReasonPoliticalInsult,
  'illegal_content' => t.adminReasonIllegal,
  'other' => t.adminReasonOther,
  _ => reason,
};

String _adminDate(DateTime? date, AppLocalizations t) {
  if (date == null) return t.adminUnknownTime;
  final d = date.toLocal();
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
