import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_service.dart';
import '../../home/presentation/home_screen.dart';
import 'auth_screen.dart';
import 'password_recovery_screen.dart';
import 'profile_home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  bool _recovering = false;
  String? _connectionWarning;
  int _profileRefresh = 0;

  @override
  void initState() {
    super.initState();
    _subscription = AuthService.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (state.event == AuthChangeEvent.signedOut) _recovering = false;
        _profileRefresh++;
        _connectionWarning = null;
      });
    }, onError: (Object error, StackTrace stack) {
      if (mounted) setState(() => _connectionWarning = 'ارتباط با سرویس حساب موقتاً قطع شد.');
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<bool> _isProfileComplete(String userId) async {
    final row = await AuthService.client
        .from('profiles')
        .select('profile_completed_at')
        .eq('id', userId)
        .maybeSingle();
    return row != null && row['profile_completed_at'] != null;
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) return const PasswordRecoveryScreen();
    final user = AuthService.client.auth.currentUser;
    final Widget page;

    if (user == null) {
      page = const AuthScreen();
    } else {
      page = FutureBuilder<bool>(
        key: ValueKey('${user.id}-$_profileRefresh'),
        future: _isProfileComplete(user.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 42),
                      const SizedBox(height: 12),
                      const Text(
                        'وضعیت پروفایل دریافت نشد. برای حفظ امنیت، ورود به صفحه اصلی تا برقراری ارتباط متوقف شده است.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () => setState(() => _profileRefresh++),
                        child: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snapshot.data == true) return const HomeScreen();
          return ProfileHomeScreen(
            onCompleted: () => setState(() => _profileRefresh++),
          );
        },
      );
    }

    return Stack(
      children: [
        page,
        if (_connectionWarning != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_connectionWarning!, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }
}
