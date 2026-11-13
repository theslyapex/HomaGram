import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService._();

  static StreamSubscription<String>? _registeredSubscription;
  static StreamSubscription<String>? _unregisteredSubscription;
  static SupabaseClient? _client;
  static String? _registeredUserId;
  static String? _registeredFid;
  static Completer<String>? _registrationCompleter;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    _registeredSubscription = messaging.onRegistered.listen((fid) {
      _registeredFid = fid;
      final completer = _registrationCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(fid);
      }
      _saveFid(fid).catchError((_) {});
    });
    _unregisteredSubscription = messaging.onUnregistered.listen((fid) {
      if (_registeredFid == fid) _registeredFid = null;
      _removeFid(fid).catchError((_) {});
    });
    _initialized = true;
  }

  static Future<void> registerCurrentDevice(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    if (!_initialized) await initialize();
    if (_registeredUserId == user.id && _registeredFid != null) return;

    _client = client;
    _registeredUserId = user.id;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (_registeredFid != null) {
      await _saveFid(_registeredFid!);
      return;
    }

    final completer = Completer<String>();
    _registrationCompleter = completer;
    try {
      await FirebaseMessaging.instance.register();
      final fid = await completer.future.timeout(const Duration(seconds: 30));
      await _saveFid(fid);
    } finally {
      if (identical(_registrationCompleter, completer)) {
        _registrationCompleter = null;
      }
    }
  }

  static Future<void> _saveFid(String fid) async {
    final client = _client;
    final userId = _registeredUserId;
    if (client == null || userId == null || fid.isEmpty) return;
    await client.from('user_push_tokens').upsert({
      'fid': fid,
      'user_id': userId,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'fid');
  }

  static Future<void> _removeFid(String fid) async {
    final client = _client;
    final userId = _registeredUserId;
    if (client == null || userId == null || fid.isEmpty) return;
    await client.from('user_push_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('fid', fid);
  }

  static Future<void> unregisterCurrentDevice(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    final fid = _registeredFid;
    if (fid != null) {
      await client.from('user_push_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('fid', fid);
    }
    try {
      await FirebaseMessaging.instance.unregister();
    } finally {
      if (_registeredUserId == userId) {
        _registeredFid = null;
        _registeredUserId = null;
        _client = null;
      }
    }
  }

  static Future<void> dispose() async {
    await _registeredSubscription?.cancel();
    await _unregisteredSubscription?.cancel();
    _registeredSubscription = null;
    _unregisteredSubscription = null;
    _registrationCompleter = null;
    _registeredFid = null;
    _registeredUserId = null;
    _client = null;
    _initialized = false;
  }
}
