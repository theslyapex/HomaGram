import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import '../features/home/presentation/shared_post_screen.dart';
import '../features/messaging/data/messaging_service.dart';
import '../features/notifications/data/push_notification_service.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/support/data/support_service.dart';
import '../features/support/presentation/support_chat_screen.dart';
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
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<dynamic>? _authSubscription;
  StreamSubscription<RemoteMessage>? _pushOpenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundPushSubscription;
  Timer? _presenceHeartbeat;
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

    _authSubscription = AuthService.client.auth.onAuthStateChange.listen((_) {
      _syncPresence();
      _syncPushRegistration();
    });
    _syncPresence();
    _syncPushRegistration();
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

  void _showForegroundPush(RemoteMessage message) {
    if (AuthService.client.auth.currentSession == null) return;
    final context = homagramNavigatorKey.currentContext;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final body = message.notification?.body?.trim();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(body == null || body.isEmpty
            ? 'اعلان تازه‌ای در HomaGram دارید.'
            : body),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'مشاهده',
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
            title: isAdmin ? 'درخواست پشتیبانی' : 'پشتیبانی هماگرام',
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
    if (uri == null || uri.scheme != 'homagram' || uri.host != 'post') {
      return;
    }
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    if (AuthService.client.auth.currentSession == null) return;

    homagramNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SharedPostScreen(postId: id),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    _pushOpenSubscription?.cancel();
    _foregroundPushSubscription?.cancel();
    _presenceHeartbeat?.cancel();
    if (widget.supabaseConfigured &&
        AuthService.client.auth.currentUser != null) {
      MessagingService.updatePresence(false).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: homagramNavigatorKey,
        title: 'HomaGram',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: HomaGramTheme.light,
        darkTheme: HomaGramTheme.dark,
        themeMode: ThemeMode.system,
        home: HomaGramLaunchScreen(
          child: widget.supabaseConfigured
              ? const AuthGate()
              : const BootstrapScreen(supabaseConfigured: false),
        ),
      );
}
