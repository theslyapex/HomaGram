import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import '../features/home/presentation/shared_post_screen.dart';
import '../features/auth/data/auth_service.dart';
import '../features/messaging/data/messaging_service.dart';
import '../features/notifications/data/push_notification_service.dart';
import '../features/support/data/support_service.dart';
import '../features/support/presentation/support_chat_screen.dart';
import 'theme/app_theme.dart';

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
  Timer? _presenceHeartbeat;
  bool? _lastPresenceState;
  String? _lastPresenceUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.supabaseConfigured) {
      _authSubscription = AuthService.client.auth.onAuthStateChange.listen((_) {
        _syncPresence();
        _syncPushRegistration();
      });
      _syncPresence();
      _syncPushRegistration();
      _linkSubscription = _appLinks.uriLinkStream.listen(_handleUri);
      _appLinks.getInitialLink().then(_handleUri).catchError((_) {});
      try {
        _pushOpenSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handlePushOpen);
        FirebaseMessaging.instance.getInitialMessage().then(_handlePushOpen).catchError((_) {});
      } catch (error) {
        debugPrint('Push-open routing unavailable: $error');
      }

    }
  }

  void _syncPushRegistration() {
    if (!widget.supabaseConfigured || AuthService.client.auth.currentUser == null) return;
    PushNotificationService.registerCurrentDevice(AuthService.client).catchError((error) {
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
    if (_lastPresenceState == online) return;
    _lastPresenceState = online;
    _presenceHeartbeat?.cancel();
    MessagingService.updatePresence(online).catchError((_) {});
    if (online) {
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
        MessagingService.updatePresence(true).catchError((_) {});
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setPresence(state == AppLifecycleState.resumed);
  }

  void _handlePushOpen(RemoteMessage? message) {
    if (message == null || AuthService.client.auth.currentSession == null) return;
    final data = message.data;
    final type = data['type']?.toString() ?? '';
    final id = data['entity_id']?.toString() ?? '';
    if ((type != 'support_message' && type != 'support_reply') ||
        !RegExp(r'^[0-9a-fA-F-]{36}
    if (uri == null || uri.scheme != 'homagram' || uri.host != 'post') return;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    if (AuthService.client.auth.currentSession == null) return;
    homagramNavigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => SharedPostScreen(postId: id),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    _pushOpenSubscription?.cancel();
    _presenceHeartbeat?.cancel();
    if (widget.supabaseConfigured && AuthService.client.auth.currentUser != null) {
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
    home: widget.supabaseConfigured ? const AuthGate() : const BootstrapScreen(supabaseConfigured: false),
  );
}
).hasMatch(id)) return;

    final isAdmin = SupportService.isSupportAdmin;
    if (type == 'support_message' && !isAdmin) return;
    if (type == 'support_reply' && isAdmin) return;

    homagramNavigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => SupportChatScreen(
        conversationId: id,
        title: isAdmin ? 'درخواست پشتیبانی' : 'پشتیبانی هماگرام',
        isAdmin: isAdmin,
      ),
    ));
  }

  void _handleUri(Uri? uri) {
    if (uri == null || uri.scheme != 'homagram' || uri.host != 'post') return;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    if (AuthService.client.auth.currentSession == null) return;
    homagramNavigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => SharedPostScreen(postId: id),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    _presenceHeartbeat?.cancel();
    if (widget.supabaseConfigured && AuthService.client.auth.currentUser != null) {
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
    home: widget.supabaseConfigured ? const AuthGate() : const BootstrapScreen(supabaseConfigured: false),
  );
}
