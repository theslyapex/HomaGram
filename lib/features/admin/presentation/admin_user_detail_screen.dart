import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/persian_date.dart';
import '../data/admin_service.dart';

class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({required this.userId, super.key});
  final String userId;
  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _future = AdminService.loadUserDetail(widget.userId); }
  Future<void> _refresh() async {
    final next = AdminService.loadUserDetail(widget.userId);
    setState(() => _future = next);
    await next;
  }
  String _date(dynamic value) {
    final d = value is String ? DateTime.tryParse(value)?.toLocal() : null;
    return d == null ? 'نامشخص' : persianDate(d);
  }
  String _duration(dynamic value) {
    final seconds = (value as num?)?.toInt() ?? 0;
    return '${seconds ~/ 3600} ساعت و ${(seconds % 3600) ~/ 60} دقیقه';
  }
  int _n(Map<String,dynamic> data, String key) => (data[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('پرونده کاربر', style: TextStyle(fontWeight: FontWeight.w900))),
    body: FutureBuilder<Map<String,dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اطلاعات کاربر دریافت نشد.'),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: _refresh, child: const Text('تلاش دوباره')),
        ]));
        final d = snapshot.data!;
        final name = (d['display_name'] as String?)?.trim();
        final username = d['username'] as String?;
        final submitted = (d['reports_submitted'] as List? ?? const []).cast<Map>();
        final against = (d['reports_against'] as List? ?? const []).cast<Map>();
        final metrics = <(String,String,IconData)>[
          ('پست‌ها', '${_n(d,'posts')}', Icons.grid_view_rounded),
          ('ریلز', '${_n(d,'reels')}', Icons.video_collection_outlined),
          ('استوری‌ها', '${_n(d,'stories')}', Icons.auto_awesome_outlined),
          ('دیدگاه‌ها', '${_n(d,'comments')}', Icons.mode_comment_outlined),
          ('پسندهای دریافتی', '${_n(d,'likes_received')}', Icons.favorite_border_rounded),
          ('دنبال‌کننده‌ها', '${_n(d,'followers')}', Icons.people_outline_rounded),
          ('دنبال‌شونده‌ها', '${_n(d,'following')}', Icons.person_add_alt_rounded),
          ('پیام‌های ارسال‌شده', '${_n(d,'messages_sent')}', Icons.chat_bubble_outline_rounded),
          ('گزارش‌های ثبت‌شده', '${_n(d,'reports_made')}', Icons.outbox_outlined),
          ('گزارش‌های دریافتی پست', '${_n(d,'reports_received')}', Icons.flag_outlined),
          ('گزارش پیام ثبت‌شده', '${_n(d,'message_reports_made')}', Icons.outbox_outlined),
          ('گزارش پیام دریافتی', '${_n(d,'message_reports_received')}', Icons.report_gmailerrorred_outlined),
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
                    Text(name?.isNotEmpty == true ? name! : 'کاربر هماگرام',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                    Text('@${username ?? 'بدون نام کاربری'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                ]),
                const SizedBox(height: 15),
                const Text('شناسه یکتای حساب', style: TextStyle(color: Colors.white70, fontSize: 11)),
                SelectableText(widget.userId, textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.8)),
                const Divider(color: Colors.white24, height: 22),
                _headerInfo('تاریخ عضویت', _date(d['created_at'])),
                const SizedBox(height: 6),
                _headerInfo('آخرین ورود ثبت‌شده', _date(d['last_sign_in_at'])),
                if ((d['bio'] as String?)?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  const Text('معرفی کاربر', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 3),
                  Text(d['bio'] as String, style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.6)),
                ],
                if ((d['website_url'] as String?)?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  _headerInfo('وب‌سایت', d['website_url'] as String),
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
                  const Text('مجموع زمان فعالیت ثبت‌شده', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_duration(d['activity_seconds']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 3),
                  const Text('محاسبه از نسخه دارای ثبت فعالیت؛ آمار گذشته در دسترس نیست.',
                    style: TextStyle(fontSize: 10, height: 1.5, color: Color(0xFF8490A4))),
                ])),
              ]),
            ),
            const SizedBox(height: 18),
            const Text('عملکرد حساب', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
            _reportSection('گزارش‌هایی که این کاربر ثبت کرده', submitted, true),
            const SizedBox(height: 12),
            _reportSection('گزارش‌های ثبت‌شده علیه محتوای این کاربر', against, false),
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
          child: const Text('موردی ثبت نشده است.', style: TextStyle(fontSize: 12)))
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
                Text('محتوای گزارش‌شده: ${report['post_caption'] ?? report['message_body']}',
                  maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
              ],
              const SizedBox(height: 5),
              Text('تاریخ: ${_date(report['created_at'])}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8490A4))),
              if (!submitted && report['reporter_id'] != null)
                Text('شناسه گزارش‌دهنده: ${report['reporter_id']}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF8490A4))),
            ]),
          )),
    ],
  );
  Widget _status(String value) {
    final color = value == 'pending' ? Colors.orange : (value == 'actioned' ? Colors.redAccent : Colors.green);
    final label = switch(value) {'pending' => 'در انتظار', 'reviewed' => 'بررسی شده', 'dismissed' => 'رد شده', 'actioned' => 'اقدام شده', _ => value};
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)));
  }
  String _reason(String reason) => switch(reason) {
    'spam' => 'هرزنامه', 'harassment' => 'آزار و اذیت', 'misinformation' => 'اطلاعات نادرست',
    'inappropriate' => 'محتوای نامناسب', 'other' => 'سایر موارد', _ => reason,
  };
}
