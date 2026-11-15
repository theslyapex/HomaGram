import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/presentation/homagram_branding.dart';
import '../../../core/utils/persian_date.dart';
import '../data/admin_service.dart';
import '../../support/presentation/support_chat_screen.dart';

class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({required this.userId, super.key});
  final String userId;
  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  late Future<Map<String, dynamic>> _future;
  bool _isAdmin = false;
  bool _deleting = false;
  bool _verified = false;
  bool _verificationBusy = false;
  @override
  void initState() {
    super.initState();
    _future = AdminService.loadUserDetail(widget.userId);
    _checkAdmin();
  }
  Future<void> _checkAdmin() async {
    try {
      final value = await AdminService.isCurrentUserAdmin();
      final profile = await Supabase.instance.client.from('profiles')
        .select('is_verified').eq('id', widget.userId).maybeSingle();
      if (mounted) setState(() { _isAdmin = value; _verified = profile?['is_verified'] == true; });
    } catch (_) {}
  }

  Future<void> _confirmDelete(Map<String, dynamic> userData) async {
    if (!_isAdmin || _deleting) return;
    final name = (userData['display_name'] as String?)?.trim();
    final username = userData['username'] as String?;
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t.adminDeleteAccountConfirmTitle),
        content: Text(_t.adminDeleteAccountQuestion(name?.isNotEmpty == true ? name! : (username ?? widget.userId))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t.feedCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t.adminContinueDelete),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final controller = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
        title: Text(_t.adminFinalDeleteConfirm),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_t.adminDeleteAccountInstruction(_t.adminDeleteAccountPhrase)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            onChanged: (_) => setDialogState(() {}),
            decoration: InputDecoration(labelText: _t.adminDeleteAccountField),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t.feedCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: controller.text.trim() == _t.adminDeleteAccountPhrase ? () => Navigator.pop(ctx, true) : null,
            child: Text(_t.adminDeleteAccountPermanent),
          ),
        ],
      )),
    );
    controller.dispose();
    if (second != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await AdminService.deleteUser(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminUserDeleted)),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.adminDeleteAccountFailed)),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }
  Future<void> _toggleVerified() async {
    if (!_isAdmin || _verificationBusy) return;
    setState(() => _verificationBusy = true);
    try {
      await AdminService.setVerified(widget.userId, !_verified);
      if (mounted) {
        setState(() => _verified = !_verified);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_verified ? _t.adminVerificationEnabled : _t.adminVerificationDisabled)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t.adminVerificationToggleFailed)));
    } finally { if (mounted) setState(() => _verificationBusy = false); }
  }

  Future<void> _messageUser() async {
    if (!_isAdmin) return;
    try {
      final id = await AdminService.openSupportForUser(widget.userId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        SupportChatScreen(conversationId: id, title: _t.adminUserSupportTitle, isAdmin: true)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_t.adminUserSupportFailed)));
    }
  }

  Future<void> _refresh() async {
    final next = AdminService.loadUserDetail(widget.userId);
    setState(() => _future = next);
    await next;
  }
  String _date(dynamic value) {
    final d = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    return d == null ? _t.adminUnknown : persianDate(d);
  }
  String _duration(dynamic value) {
    final seconds = (value as num?)?.toInt() ?? 0;
    return _t.adminDurationHoursAndMinutes(seconds ~/ 3600, (seconds % 3600) ~/ 60);
  }
  int _n(Map<String,dynamic> data, String key) => (data[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t.adminUserFileTitle, style: TextStyle(fontWeight: FontWeight.w900))),
    body: FutureBuilder<Map<String,dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_t.adminUserDataLoadFailed),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: _refresh, child: Text(_t.adminRetry)),
        ]));
        final d = snapshot.data!;
        final name = (d['display_name'] as String?)?.trim();
        final username = d['username'] as String?;
        final submitted = (d['reports_submitted'] as List? ?? const []).cast<Map>();
        final against = (d['reports_against'] as List? ?? const []).cast<Map>();
        final metrics = <(String,String,IconData)>[
          (_t.adminMetricPosts, '${_n(d,'posts')}', Icons.grid_view_rounded),
          (_t.adminMetricReels, '${_n(d,'reels')}', Icons.video_collection_outlined),
          (_t.adminMetricStories, '${_n(d,'stories')}', Icons.auto_awesome_outlined),
          (_t.adminMetricComments, '${_n(d,'comments')}', Icons.mode_comment_outlined),
          (_t.adminMetricLikesReceived, '${_n(d,'likes_received')}', Icons.favorite_border_rounded),
          (_t.adminMetricFollowers, '${_n(d,'followers')}', Icons.people_outline_rounded),
          (_t.adminMetricFollowing, '${_n(d,'following')}', Icons.person_add_alt_rounded),
          (_t.adminMetricMessages, '${_n(d,'messages_sent')}', Icons.chat_bubble_outline_rounded),
          (_t.adminMetricReportsSubmitted, '${_n(d,'reports_made')}', Icons.outbox_outlined),
          (_t.adminMetricPostReportsReceived, '${_n(d,'reports_received')}', Icons.flag_outlined),
          (_t.adminMetricMessageReportsSubmitted, '${_n(d,'message_reports_made')}', Icons.outbox_outlined),
          (_t.adminMetricMessageReportsReceived, '${_n(d,'message_reports_received')}', Icons.report_gmailerrorred_outlined),
        ];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
                  colors: [Color(0xFF283B70), Color(0xFF174D60), Color(0xFF17233E)])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const CircleAvatar(radius: 26, backgroundColor: Color(0x33FFFFFF),
                    child: Icon(Icons.person_rounded, color: Colors.white, size: 29)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(name?.isNotEmpty == true ? name! : _t.adminUnknownUser,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17))),
                      const SizedBox(width: 4),
                      HomaGramVerifiedBadge(userId: widget.userId, size: 16),
                    ]),
                    Text('@${username ?? _t.adminNoUsername}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                ]),
                const SizedBox(height: 15),
                Text(_t.adminUniqueAccountId, style: TextStyle(color: Colors.white70, fontSize: 11)),
                SelectableText(widget.userId, textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.8)),
                const Divider(color: Colors.white24, height: 22),
                _headerInfo(_t.adminJoinedAt, _date(d['created_at'])),
                const SizedBox(height: 6),
                _headerInfo(_t.adminLastSignIn, _date(d['last_sign_in_at'])),
                if ((d['bio'] as String?)?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(_t.adminUserBio, style: TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 3),
                  Text(d['bio'] as String, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.6)),
                ],
                if ((d['website_url'] as String?)?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  _headerInfo(_t.adminWebsite, d['website_url'] as String),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: HomaGramTheme.turquoise.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(18), border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .2))),
              child: Row(children: [
                const Icon(Icons.timer_outlined, color: HomaGramTheme.turquoise, size: 27),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_t.adminActivityTotal, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_duration(d['activity_seconds']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 3),
                  Text(_t.adminActivityTrackingNote,
                    style: TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF8490A4))),
                ])),
              ]),
            ),
            const SizedBox(height: 18),
            Text(_t.adminAccountPerformance, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, box) {
              final columns = box.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.65),
                itemBuilder: (context, i) {
                  final m = metrics[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(m.$3, color: HomaGramTheme.turquoise, size: 19),
                      const SizedBox(height: 6),
                      Text(m.$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(m.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                    ]),
                  );
                },
              );
            }),
            const SizedBox(height: 18),
            _reportSection(_t.adminUserSubmittedReports, submitted, true),
            const SizedBox(height: 12),
            _reportSection(_t.adminReportsAgainstUser, against, false),
            if (_isAdmin) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _verificationBusy ? null : _toggleVerified,
                icon: Icon(_verified ? Icons.verified_rounded : Icons.verified_outlined),
                label: Text(_verified ? _t.adminRevokeVerification : _t.adminGrantVerification),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _messageUser,
                icon: const Icon(Icons.support_agent_rounded),
                label: Text(_t.adminSendSupportMessage),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _deleting ? null : () => _confirmDelete(d),
                icon: _deleting
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_remove_alt_1_rounded),
                label: Text(_deleting ? _t.adminDeletingAccount : _t.adminDeleteUserAccount),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ]),
        );
      },
    ),
  );

  Widget _headerInfo(String title, String value) => Row(children: [
    Text('$title: ', style: const TextStyle(color: Colors.white70, fontSize: 11)),
    Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11))),
  ]);
  Widget _reportSection(String title, List<Map> reports, bool submitted) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      const SizedBox(height: 8),
      if (reports.isEmpty)
        Container(width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(16)),
          child: Text(_t.adminNoReports, style: TextStyle(fontSize: 12)))
      else
        for (final report in reports)
          Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(
            padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_reason(report['reason']?.toString() ?? ''),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                _status(report['status']?.toString() ?? 'pending'),
              ]),
              if ((report['details'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text(report['details'] as String, style: const TextStyle(fontSize: 11, height: 1.6)),
              ],
              if (((report['post_caption'] as String?)?.isNotEmpty ?? false) ||
                  ((report['message_body'] as String?)?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 5),
                Text(_t.adminReportedContent(report['post_caption'] ?? report['message_body']),
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
              ],
              const SizedBox(height: 5),
              Text(_t.adminReportDate(_date(report['created_at'])),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
              if (!submitted && report['reporter_id'] != null)
                Text(_t.adminReporterId(report['reporter_id'].toString()),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF8490A4))),
            ]),
          )),
    ],
  );
  Widget _status(String value) {
    final color = value == 'pending' ? Colors.orange : (value == 'actioned' ? Colors.redAccent : Colors.green);
    final label = switch(value) {'pending' => _t.adminFilterPending, 'reviewed' => _t.adminFilterReviewed, 'dismissed' => _t.adminStatusDismissed, 'actioned' => _t.adminStatusActioned, _ => value};
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)));
  }
  String _reason(String reason) => switch(reason) {
    'spam' => _t.adminReasonSpam, 'harassment' => _t.adminReasonHarassment, 'misinformation' => _t.adminReasonMisinformation,
    'inappropriate' => _t.adminReasonInappropriate, 'other' => _t.adminReasonOther, _ => reason,
  };
}
