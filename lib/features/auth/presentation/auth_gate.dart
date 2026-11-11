import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _subscription = AuthService.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (state.event == AuthChangeEvent.signedOut) _recovering = false;
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

  @override
  Widget build(BuildContext context) {
    if (_recovering) return const PasswordRecoveryScreen();
    final page = AuthService.client.auth.currentSession == null
        ? const AuthScreen()
        : const ProfileHomeScreen();
    return Stack(children: [
      page,
      if (_connectionWarning != null)
        Positioned(left: 16, right: 16, bottom: 18,
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_connectionWarning!, textAlign: TextAlign.center),
            ),
          ),
        ),
    ]);
  }
}
