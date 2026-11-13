import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/homagram_app.dart';
import 'features/notifications/data/push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final configured = url.startsWith('https://') && key.isNotEmpty;
  if (configured) {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }

  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await PushNotificationService.initialize();
    } catch (error) {
      debugPrint('Firebase Messaging initialization skipped: $error');
    }
  }

  runApp(HomaGramApp(supabaseConfigured: configured));
}
