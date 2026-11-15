import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../notifications/data/push_notification_service.dart';
import 'auth_service.dart';

class SavedHomagramAccount {
  const SavedHomagramAccount({
    required this.userId,
    required this.email,
    required this.displayName,
  });

  final String userId;
  final String email;
  final String displayName;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'display_name': displayName,
  };

  factory SavedHomagramAccount.fromJson(Map<String, dynamic> json) =>
      SavedHomagramAccount(
        userId: json['user_id'] as String,
        email: json['email'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
      );
}

/// Keeps each account's rotating Supabase refresh token in encrypted device
/// storage. Passwords are never persisted.
class MultiAccountService {
  MultiAccountService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _indexKey = 'homagram.multi_accounts.v1';
  static StreamSubscription<AuthState>? _authSubscription;
  static Future<void> _writeQueue = Future<void>.value();
  static bool _initialized = false;

  static SupabaseClient get _client => AuthService.client;

  static String _tokenKey(String userId) =>
      'homagram.account.$userId.refresh_token';

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _authSubscription = _client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (session != null) {
        unawaited(_persistSession(session).catchError((_) {}));
      }
    }, onError: (Object error, StackTrace stack) {
      // A temporary auth-stream error must not interrupt app startup.
    });

    final current = _client.auth.currentSession;
    if (current != null) await _persistSession(current);
  }

  static Future<void> rememberCurrentSession() async {
    final session = _client.auth.currentSession;
    if (session != null) await _persistSession(session);
  }

  static Future<void> _persistSession(Session session) {
    final task = _writeQueue.then((_) async {
      final refreshToken = session.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) return;

      final user = session.user;
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final displayName = (metadata['display_name'] ??
              metadata['username'] ??
              user.email ??
              'HomaGram')
          .toString()
          .trim();
      final accounts = await _readIndex();
      accounts.removeWhere((item) => item.userId == user.id);
      accounts.add(SavedHomagramAccount(
        userId: user.id,
        email: user.email ?? '',
        displayName: displayName.isEmpty ? 'HomaGram' : displayName,
      ));

      await _storage.write(
        key: _tokenKey(user.id),
        value: refreshToken,
      );
      await _storage.write(
        key: _indexKey,
        value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
      );
    });
    _writeQueue = task.catchError((_) {});
    return task;
  }

  static Future<List<SavedHomagramAccount>> _readIndex() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => SavedHomagramAccount.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SavedHomagramAccount>> listAccounts() async {
    await _writeQueue;
    final accounts = await _readIndex();
    final available = <SavedHomagramAccount>[];
    for (final account in accounts) {
      final token = await _storage.read(key: _tokenKey(account.userId));
      if (token != null && token.isNotEmpty) available.add(account);
    }
    return available;
  }

  static Future<void> _prepareAccountChange() async {
    await rememberCurrentSession();
    if (_client.auth.currentUser != null) {
      try {
        await PushNotificationService.unregisterCurrentDevice(_client);
      } catch (_) {
        // Authentication must remain usable if push registration is unavailable.
      }
    }
  }

  static Future<void> addAccount({
    required String email,
    required String password,
  }) async {
    await _prepareAccountChange();
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final session = response.session;
      if (session != null) await _persistSession(session);
    } catch (_) {
      if (_client.auth.currentUser != null) {
        try {
          await PushNotificationService.registerCurrentDevice(_client);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> switchTo(String userId) async {
    if (_client.auth.currentUser?.id == userId) return;
    await _prepareAccountChange();

    final refreshToken = await _storage.read(key: _tokenKey(userId));
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('This account is no longer available on this device.');
    }

    try {
      final response = await _client.auth.setSession(refreshToken);
      final session = response.session;
      if (session == null) {
        throw StateError('The saved account session could not be restored.');
      }
      await _persistSession(session);
    } catch (_) {
      if (_client.auth.currentUser != null) {
        try {
          await PushNotificationService.registerCurrentDevice(_client);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> removeAccount(String userId) async {
    await _writeQueue;
    await _storage.delete(key: _tokenKey(userId));
    final accounts = await _readIndex();
    accounts.removeWhere((item) => item.userId == userId);
    await _storage.write(
      key: _indexKey,
      value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }
}
