import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_service.dart';

import '../../../app/theme/app_theme.dart';
import '../../home/presentation/public_profile_screen.dart';
import '../../home/data/story_service.dart';
import '../../home/presentation/stories_screen.dart';
import '../../messaging/presentation/chat_screen.dart';
import '../../support/data/support_service.dart';
import '../../support/presentation/support_chat_screen.dart';
import '../data/notification_service.dart';
import '../../../l10n/generated/app_localizations.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _future = NotificationService.load();
    final userId = AuthService.client.auth.currentUser?.id;
    if (userId != null) {
      _channel = AuthService.client.channel('notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_id', value: userId),
          callback: (_) { if (mounted) _refresh(); },
        ).subscribe();
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) AuthService.client.removeChannel(channel);
    super.dispose();
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
          SnackBar(content: Text(_t.markAllNotificationsFailed)),
        );
      }
    }
  }

  Future<void> _openPreferences() async {
    try {
      final preferences = await NotificationService.loadPreferences();
      if (!mounted) return;
      var social = preferences['social'] ?? true;
      var messages = preferences['messages'] ?? true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(_t.notificationSettingsTitle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_t.socialNotificationCategory),
                subtitle: Text(_t.socialNotificationCategoryHint),
                value: social,
                onChanged: (value) => setDialogState(() => social = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_t.messageNotificationCategory),
                subtitle: Text(_t.messageNotificationCategoryHint),
                value: messages,
                onChanged: (value) => setDialogState(() => messages = value),
              ),
            ]),
            actions: [
              HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_t.cancel))),
              HomaGramSpringPress(child: FilledButton(onPressed: () async {
                try {
                  await NotificationService.updatePreferences(socialEnabled: social, messagesEnabled: messages);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (_) {
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(_t.notificationSettingsSaveFailed)),
                  );
                }
              }, child: Text(_t.save))),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t.notificationSettingsLoadFailed)),
      );
    }
  }

  String _description(Map<String, dynamic> item) {
    final actor = item['actor'] as Map<String, dynamic>?;
    final name = (actor?['display_name'] as String?)?.trim();
    final username = actor?['username'] as String?;
    final label = name?.isNotEmpty == true
        ? name!
        : (username ?? _t.notificationSomeone);
    final message = switch (item['type'] as String? ?? '') {
      'follow' => _t.notificationFollowedYou,
      'post_like' => _t.notificationLikedPost,
      'post_comment' => _t.notificationCommentedPost,
      'comment_reply' => _t.notificationRepliedComment,
      'post_repost' => _t.notificationRepostedPost,
      'story_reaction' => _t.notificationReactedStory,
      'story_mention' => _t.notificationMentionedStory,
      'message_new' => _t.notificationSentMessage,
      'support_message' => _t.notificationSupportRequest,
      'support_reply' => _t.notificationSupportReply,
      'moderation_notice' => _t.notificationModerationNotice,
      'report_reviewed' => _t.notificationReportReviewed,
      _ => (item['message'] as String?) ?? _t.notificationGenericActivity,
    };
    return '$label $message';
  }

  IconData _icon(String type) {
    switch (type) {
      case 'follow': return Icons.person_add_alt_1_rounded;
      case 'post_like': return Icons.favorite_rounded;
      case 'post_comment':
      case 'comment_reply': return Icons.mode_comment_rounded;
      case 'post_repost': return Icons.repeat_rounded;
      case 'story_reaction': return Icons.auto_awesome_rounded;
      case 'story_mention': return Icons.alternate_email_rounded;
      case 'message_new': return Icons.mark_chat_unread_rounded;
      case 'support_message':
      case 'support_reply': return Icons.support_agent_rounded;
      case 'moderation_notice': return Icons.gavel_rounded;
      case 'report_reviewed': return Icons.fact_check_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  String _time(dynamic value) {
    if (value is! String) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return _t.notificationJustNow;
    if (elapsed.inHours < 1) return _t.notificationMinutesAgo(elapsed.inMinutes);
    if (elapsed.inDays < 1) return _t.notificationHoursAgo(elapsed.inHours);
    if (elapsed.inDays < 7) return _t.notificationDaysAgo(elapsed.inDays);
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
    final type = item['type'] as String? ?? '';
    final entityId = item['entity_id'] as String?;
    if (type == 'story_mention' && entityId != null) {
      try {
        final story = await StoryService.loadStoryById(entityId);
        if (!mounted) return;
        if (story != null) {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => StoryViewerScreen(stories: [story]),
          ));
          return;
        }
      } catch (_) {}
    }
    if ((type == 'support_reply' || type == 'support_message') && entityId != null) {
      if (type == 'support_message' && SupportService.isSupportAdmin) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(
            conversationId: entityId,
            title: _t.supportRequestTitle,
            isAdmin: true,
          ),
        ));
      } else if (type == 'support_reply') {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupportChatScreen(
            conversationId: entityId,
            title: _t.supportChatTitle,
          ),
        ));
      }
    } else if (type == 'message_new' && entityId != null) {
      final displayName = (actor?['display_name'] as String?)?.trim();
      final username = actor?['username'] as String?;
      final title = displayName?.isNotEmpty == true
          ? displayName!
          : (username ?? _t.conversationFallback);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: entityId,
          title: title,
        ),
      ));
    } else if (actorId != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PublicProfileScreen(userId: actorId),
      ));
    } else {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(_t.notificationCenterTitle, style: const TextStyle(fontWeight: FontWeight.w900))),
      body: HomaGramEntrance(child: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
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
              Text(_t.loadNotificationsFailed),
              const SizedBox(height: 12),
              HomaGramSpringPress(child: FilledButton.tonal(onPressed: _refresh, child: Text(_t.retry))),
            ],
          ));
        }

        final items = snapshot.data ?? [];
        final unread = items.where((item) => item['is_read'] != true).length;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(children: [
              Expanded(child: Text(_t.yourNotifications,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
              HomaGramSpringPress(child: IconButton(tooltip: _t.notificationSettingsTitle, onPressed: _openPreferences, icon: const Icon(Icons.tune_rounded))),
              if (unread > 0)
                HomaGramSpringPress(child: TextButton(onPressed: _markAllRead, child: Text(_t.markAllAsRead))),
            ]),
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: _refresh,
            child: items.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                    const SizedBox(height: 110),
                    const Icon(Icons.notifications_off_outlined, size: 54, color: Colors.grey),
                    const SizedBox(height: 14),
                    Center(child: Text(_t.noNewNotifications)),
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
                      final actor = item['actor'] as Map<String, dynamic>?;
                      final actorAvatar = actor?['avatar_url'] as String?;
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
                                backgroundImage: actorAvatar == null ? null : NetworkImage(actorAvatar),
                                child: actorAvatar == null ? Icon(_icon(type), color: iconColor) : null,
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
    ))),
    );
  }
}