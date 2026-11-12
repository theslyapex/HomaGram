import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';
import '../features/home/presentation/shared_post_screen.dart';
import '../features/auth/data/auth_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> homagramNavigatorKey = GlobalKey<NavigatorState>();

class HomaGramApp extends StatefulWidget {
  const HomaGramApp({required this.supabaseConfigured, super.key});
  final bool supabaseConfigured;
  @override
  State<HomaGramApp> createState() => _HomaGramAppState();
}

class _HomaGramAppState extends State<HomaGramApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.supabaseConfigured) {
      _linkSubscription = _appLinks.uriLinkStream.listen(_handleUri);
      _appLinks.getInitialLink().then(_handleUri).catchError((_) {});
    }
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
    _linkSubscription?.cancel();
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
