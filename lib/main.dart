import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/homagram_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  final hasSupabaseConfig =
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  if (hasSupabaseConfig) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabasePublishableKey,
    );
  }

  runApp(HomaGramApp(supabaseConfigured: hasSupabaseConfig));
}
