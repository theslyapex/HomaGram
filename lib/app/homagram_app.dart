import 'app_language.dart';
import '../l10n/generated/app_localizations.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../features/auth/data/auth_service.dart';
import '../features/auth/data/multi_account_service.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import '../features/home/presentation/shared_post_screen.dart';
import '../features/messaging/data/messaging_service.dart';
import '../features/messaging/presentation/chat_screen.dart';
import '../features/notifications/data/push_notification_service.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/support/data/support_service.dart';
import '../features/support/presentation/support_chat_screen.dart';
import 'bug_report_service.dart';
import 'theme/app_theme.dart';
import 'presentation/homagram_branding.dart';

final GlobalKey<NavigatorState> homagramNavigatorKey = GlobalKey<NavigatorState>();

class HomaGramApp extends StatefulWidget {
  const HomaGramApp({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  State<HomaGramApp> createState() => _HomaGramAppState();
}

class _HomaGramAppState extends State<HomaGramApp> with WidgetsBindingObserver {
  AppLocalizations get _t => AppLocalizations.of(context)!;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<RemoteMessage>? _pushOpenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundPushSubscription;
  StreamSubscription<AccelerometerEvent>? _shakeSubscription;
  Timer? _presenceHeartbeat;
  DateTime _lastShakeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _bugReportDialogOpen = false;
  bool? _lastPresenceState;
  String? _lastPresenceUserId;
  String? _activitySessionId;
  String? _activityUserId;
  bool _activitySessionEnded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.supabaseConfigured) return;
    BugReportPreferences.load();
    _shakeSubscription = accelerometerEventStream().listen(
      _handleAccelerometer,
      onError: (_) {},
    );

    _authSubscription = AuthService.client.auth.onAuthStateChange.listen((_) {
      _syncPresence();
      _syncPushRegistration();
      _syncTheme();
    });
    _syncPresence();
    _syncPushRegistration();
    _syncTheme();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleUri);
    _appLinks.getInitialLink().then(_handleUri).catchError((_) {});

    try {
      _pushOpenSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen(_handlePushOpen);
      _foregroundPushSubscription =
          FirebaseMessaging.onMessage.listen(_showForegroundPush);
      FirebaseMessaging.instance
          .getInitialMessage()
          .then(_handlePushOpen)
          .catchError((_) {});
    } catch (error) {
      debugPrint('Push-open routing unavailable: $error');
    }
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    if (!BugReportPreferences.shakeEnabled.value ||
        AuthService.client.auth.currentUser == null) return;
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (magnitude < 22) return;
    final now = DateTime.now();
    if (now.difference(_lastShakeAt) < const Duration(seconds: 3)) return;
    _lastShakeAt = now;
    unawaited(_openQuickBugReport());
  }

  Future<void> _openQuickBugReport() async {
    if (_bugReportDialogOpen || !mounted) return;
    _bugReportDialogOpen = true;
    final controller = TextEditingController();
    try {
      final bytes = await BugReportPreferences.captureScreen();
      final dialogContext = homagramNavigatorKey.currentContext;
      if (!mounted || dialogContext == null || bytes == null) return;
      final t = AppLocalizations.of(dialogContext)!;
      final send = await showDialog<bool>(
        context: dialogContext,
        builder: (ctx) => AlertDialog(
          title: Text(t.quickBugReportTitle),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.quickBugReportScreenshotPrivacy,
                  style: TextStyle(fontSize: 12, height: 1.7)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.memory(bytes, height: 190, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Text(t.quickBugReportPreviewUnavailable)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1200,
                  decoration: InputDecoration(
                    labelText: t.quickBugReportDescriptionLabel,
                    hintText: t.quickBugReportDescriptionHint,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send_rounded),
              label: Text(t.quickBugReportSend),
            ),
          ],
        ),
      );
      if (send != true || !mounted) return;
      final conversationId = await SupportService.getOrCreateConversation();
      await SupportService.sendAttachment(
        conversationId: conversationId,
        bytes: bytes,
        fileName: 'homagram-bug-report.png',
        mimeType: 'image/png',
        caption: controller.text.trim().isEmpty
            ? t.quickBugReportCaptionDefault
            : t.quickBugReportCaptionDetails(controller.text.trim()),
      );
      if (!mounted) return;
      homagramNavigatorKey.currentState?.push(MaterialPageRoute<void>(
        builder: (_) => SupportChatScreen(conversationId: conversationId),
      ));
    } catch (_) {
      final context = homagramNavigatorKey.currentContext;
      final t = context == null ? null : AppLocalizations.of(context);
      if (context != null && t != null && mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(t.quickBugReportSubmitFailed)),
      );
    } finally {
      controller.dispose();
      _bugReportDialogOpen = false;
    }
  }

  Future<void> _syncTheme() async {
    final user = AuthService.client.auth.currentUser;
    if (user == null) {
      HomaGramTheme.mode.value = ThemeMode.system;
      return;
    }
    try {
      final row = await AuthService.client.from('account_settings')
          .select('theme').eq('user_id', user.id).maybeSingle();
      if (!mounted) return;
      final theme = row?['theme'] as String? ?? 'system';
      HomaGramTheme.mode.value = switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
  }

  void _syncPushRegistration() {
    if (!widget.supabaseConfigured ||
        AuthService.client.auth.currentUser == null) {
      return;
    }
    PushNotificationService.registerCurrentDevice(AuthService.client)
        .catchError((error) {
      debugPrint('Push token registration failed: $error');
    });
  }

  void _syncPresence() {
    final user = AuthService.client.auth.currentUser;
    if (user == null) {
      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = null;
      _lastPresenceState = null;
      _lastPresenceUserId = null;
      _activityUserId = null;
      _activitySessionId = null;
      _activitySessionEnded = true;
      return;
    }
    _setPresence(AuthService.client.auth.currentSession != null);
  }

  void _setPresence(bool online) {
    final user = AuthService.client.auth.currentUser;
    if (!widget.supabaseConfigured || user == null) return;
    if (_lastPresenceUserId != user.id) {
      _lastPresenceUserId = user.id;
      _lastPresenceState = null;
    }
    if (_activityUserId != user.id) {
      _activityUserId = user.id;
      _activitySessionId = _newActivitySessionId();
      _activitySessionEnded = true;
    }
    if (_lastPresenceState == online) return;
    _lastPresenceState = online;
    _presenceHeartbeat?.cancel();
    MessagingService.updatePresence(online).catchError((_) {});
    _trackActivity(online);
    if (online) {
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
        MessagingService.updatePresence(true).catchError((_) {});
        _trackActivity(true);
      });
    }
  }

  String _newActivitySessionId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _trackActivity(bool active) {
    if (!widget.supabaseConfigured || AuthService.client.auth.currentUser == null) return;
    if (active && _activitySessionEnded) {
      _activitySessionId = _newActivitySessionId();
      _activitySessionEnded = false;
    }
    final id = _activitySessionId;
    if (id == null) return;
    AuthService.client.rpc('track_user_activity', params: {
      'p_session_id': id,
      'p_is_active': active,
    }).catchError((error) {
      debugPrint('Activity tracking unavailable: $error');
    });
    if (!active) _activitySessionEnded = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setPresence(state == AppLifecycleState.resumed);
  }

  String _localizedPushBody(RemoteMessage message) {
    final actor = (message.data['actor_name'] ??
            message.data['display_name'] ??
            message.data['sender_name'] ??
            '')
        .toString()
        .trim();
    final localized = switch (message.data['type']?.toString() ?? '') {
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
      _ => null,
    };
    if (localized != null) {
      return actor.isEmpty ? localized : '$actor $localized';
    }
    final body = message.notification?.body?.trim();
    return body == null || body.isEmpty
        ? _t.newNotificationInHomagram
        : body;
  }

  void _showForegroundPush(RemoteMessage message) {
    if (AuthService.client.auth.currentSession == null) return;
    final context = homagramNavigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_localizedPushBody(message)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: _t.viewNotification,
          onPressed: () => _handlePushOpen(message),
        ),
      ),
    );
  }

  void _openNotificationsInbox() {
    homagramNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  }

  void _handlePushOpen(RemoteMessage? message) {
    if (message == null ||
        AuthService.client.auth.currentSession == null) {
      return;
    }

    final data = message.data;
    final type = data['type']?.toString() ?? '';
    final id = data['entity_id']?.toString() ?? '';

    if (type == 'support_message' || type == 'support_reply') {
      if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
      final isAdmin = SupportService.isSupportAdmin;
      if (type == 'support_message' && !isAdmin) return;
      if (type == 'support_reply' && isAdmin) return;

      homagramNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => SupportChatScreen(
            conversationId: id,
            title: isAdmin ? _t.supportRequestTitle : _t.supportChatTitle,
            isAdmin: isAdmin,
          ),
        ),
      );
      return;
    }

    const inboxTypes = {
      'follow',
      'post_like',
      'post_comment',
      'comment_reply',
      'post_repost',
      'story_reaction',
      'message_new',
    };
    if (inboxTypes.contains(type)) _openNotificationsInbox();
  }


  void _handleUri(Uri? uri) {
    if (uri == null || uri.scheme != 'homagram') return;
    if (AuthService.client.auth.currentSession == null) return;

    if (uri.host == 'post') {
      final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
      homagramNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => SharedPostScreen(postId: id),
        ),
      );
      return;
    }

    if (uri.host == 'group') {
      final token = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) return;
      unawaited(_openGroupInvite(token));
    }
  }

  Future<void> _openGroupInvite(String token) async {
    try {
      final conversationId = await MessagingService.joinGroupByInvite(token);
      final row = await AuthService.client
          .from('conversations')
          .select('title')
          .eq('id', conversationId)
          .single();
      final title = row['title'] as String? ?? _t.group;
      final navigator = homagramNavigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            title: title,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Group invite deep link failed: $error');
      final context = homagramNavigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t.groupInviteInvalid),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(MultiAccountService.dispose());
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    _pushOpenSubscription?.cancel();
    _foregroundPushSubscription?.cancel();
    _shakeSubscription?.cancel();
    _presenceHeartbeat?.cancel();
    if (widget.supabaseConfigured &&
        AuthService.client.auth.currentUser != null) {
      MessagingService.updatePresence(false).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: HomaGramTheme.mode,
      builder: (context, themeMode, _) {
        return AnimatedBuilder(
          animation: AppLanguage.instance,
          builder: (context, __) {
            return RepaintBoundary(
              key: homagramScreenCaptureKey,
              child: MaterialApp(
                navigatorKey: homagramNavigatorKey,
                title: 'HomaGram',
                debugShowCheckedModeBanner: false,
                locale: AppLanguage.instance.locale,
                supportedLocales: const [
                  Locale('fa'),
                  Locale('en'),
                  Locale('ar'),
                ],
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: HomaGramTheme.light,
                darkTheme: HomaGramTheme.dark,
                themeMode: themeMode,
                home: HomaGramLaunchScreen(
                  child: widget.supabaseConfigured
                      ? const AuthGate()
                      : const BootstrapScreen(supabaseConfigured: false),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
