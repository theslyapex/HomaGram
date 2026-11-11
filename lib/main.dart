import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/homagram_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final configured = url.startsWith('https://') && key.isNotEmpty;
  if (configured) {
    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }
  runApp(HomaGramApp(supabaseConfigured: configured));
}
