import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../home/presentation/public_profile_screen.dart';
import '../data/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationService.load();
  }

  Future<void> _refresh() async {
    final next = NotificationService.load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _markAllRead() async {
    try {
      await NotificationService.markAllRead();
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('علامت‌گذاری اعلان‌ها انجام نشد.')),
        );
      }
    }
  }

  String _description(Map<String, dynamic> item) {
    final actor = item['actor'] as Map<String, dynamic>?;
    final name = (actor?['display_name'] as String?)?.trim();
    final username = actor?['username'] as String?;
    final label = name?.isNotEmpty == true ? name! : (username ?? 'یک کاربر');
    return '$label ${item['message'] ?? 'با شما تعامل داشت.'}';
  }

  IconData _icon(String type) {
    switch (type) {
      case 'follow': return Icons.person_add_alt_1_rounded;
      case 'post_like': return Icons.favorite_rounded;
      case 'post_comment':
      case 'comment_reply': return Icons.mode_comment_rounded;
      case 'post_repost': return Icons.repeat_rounded;
      case 'story_reaction': return Icons.auto_awesome_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  String _time(dynamic value) {
    if (value is! String) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return 'همین الان';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} دقیقه پیش';
    if (elapsed.inDays < 1) return '${elapsed.inHours} ساعت پیش';
    if (elapsed.inDays < 7) return '${elapsed.inDays} روز پیش';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final notificationId = item['id'] as String?;
    if (notificationId != null && item['is_read'] != true) {
      try {
        await NotificationService.markRead(notificationId);
      } catch (_) {}
    }
    if (!mounted) return;
    final actor = item['actor'] as Map<String, dynamic>?;
    final actorId = actor?['id'] as String?;
    if (actorId != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: actorId),
      ));
    } else {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('بارگذاری اعلان‌ها با مشکل مواجه شد.'),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _refresh, child: const Text('تلاش دوباره')),
            ],
          ));
        }

        final items = snapshot.data ?? [];
        final unread = items.where((item) => item['is_read'] != true).length;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(children: [
              const Expanded(child: Text('اعلان‌های شما',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
              if (unread > 0)
                TextButton(onPressed: _markAllRead, child: const Text('خواندن همه')),
            ]),
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: _refresh,
            child: items.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                    SizedBox(height: 110),
                    Icon(Icons.notifications_off_outlined, size: 54, color: Colors.grey),
                    SizedBox(height: 14),
                    Center(child: Text('هنوز اعلان تازه‌ای ندارید.')),
                  ])
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final type = item['type'] as String? ?? '';
                      final read = item['is_read'] == true;
                      final iconColor = type == 'post_like'
                          ? Colors.pinkAccent : HomaGramTheme.turquoise;
                      return Material(
                        color: read ? Theme.of(context).cardColor
                            : HomaGramTheme.turquoise.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _open(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              CircleAvatar(
                                backgroundColor: iconColor.withValues(alpha: .13),
                                child: Icon(_icon(type), color: iconColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_description(item),
                                      style: const TextStyle(fontWeight: FontWeight.w600, height: 1.7)),
                                  const SizedBox(height: 4),
                                  Text(_time(item['created_at']),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      )),
                                ],
                              )),
                              if (!read) Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: HomaGramTheme.turquoise, shape: BoxShape.circle,
                                ),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          )),
        ]);
      },
    );
  }
}