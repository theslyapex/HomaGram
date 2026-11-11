import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import '../features/bootstrap/presentation/bootstrap_screen.dart';

class HomaGramApp extends StatelessWidget {
  const HomaGramApp({
    required this.supabaseConfigured,
    super.key,
  });

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomaGram',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: HomaGramTheme.light,
      darkTheme: HomaGramTheme.dark,
      themeMode: ThemeMode.system,
      home: BootstrapScreen(supabaseConfigured: supabaseConfigured),
    );
  }
}
