import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService._();

  static StreamSubscription<String>? _tokenSubscription;
  static SupabaseClient? _client;
  static String? _registeredUserId;
  static bool _initialized = false;
  static bool _permissionRequested = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _saveToken(token),
      onError: (_) {},
    );
    _initialized = true;
  }

  static Future<void> registerCurrentDevice(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    if (!_initialized) await initialize();
    if (_registeredUserId == user.id) return;

    _client = client;
    _registeredUserId = user.id;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(token);
    }
  }

  static Future<void> _saveToken(String token) async {
    final client = _client;
    final userId = _registeredUserId;
    if (client == null || userId == null || token.isEmpty) return;
    await client.from('user_push_tokens').upsert({
      'token': token,
      'user_id': userId,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  static Future<void> unregisterCurrentDevice(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await client.from('user_push_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
    } finally {
      if (_registeredUserId == userId) {
        _registeredUserId = null;
        _client = null;
      }
    }
  }

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _initialized = false;
    _client = null;
    _registeredUserId = null;
    _permissionRequested = false;
  }
}
