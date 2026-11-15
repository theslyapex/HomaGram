import '../../../app/app_language.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/presentation/homagram_branding.dart';
import '../data/auth_service.dart';
import '../domain/auth_constants.dart';

enum _Mode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false, _obscure = true, _obscureConfirmation = true, _verificationSent = false;
  String? _pendingEmail;
  bool get _registering => _mode == _Mode.signUp;
  AppLocalizations get _strings => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _email.dispose(); _password.dispose(); _confirmPassword.dispose(); _username.dispose(); _displayName.dispose();
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (_registering) {
        await AuthService.signUp(
          email: _email.text, password: _password.text,
          username: _username.text, displayName: _displayName.text,
        );
        if (!mounted) return;
        setState(() { _verificationSent = true; _pendingEmail = _email.text.trim(); });
        _message(_strings.registrationSubmitted);
      } else {
        await AuthService.signIn(email: _email.text, password: _password.text);
      }
    } on AuthException catch (error) {
      final detail = error.message.toLowerCase();
      if (_registering && (detail.contains('duplicate') || detail.contains('profiles_username'))) {
        _message(_strings.usernameTaken, error: true);
      } else if (_registering) {
        _message(_strings.signUpFailed, error: true);
      } else {
        _message(_strings.signInFailed, error: true);
      }
    } catch (_) {
      _message(_strings.networkError, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = _pendingEmail;
    if (email == null || _busy) return;
    setState(() => _busy = true);
    try {
      await AuthService.resendSignupEmail(email);
      _message(_strings.verificationResent);
    } catch (_) {
      _message(_strings.resendFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_strings.passwordRecovery),
        content: TextField(
          controller: controller, keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: _strings.accountEmail),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_strings.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(_strings.sendLink)),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AuthService.sendPasswordRecovery(email);
      _message(_strings.recoveryIfExists);
    } catch (_) {
      _message(_strings.recoveryFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF101B35), Color(0xFF172A45), Color(0xFF24345A)],
        )),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              Align(alignment: AlignmentDirectional.centerEnd, child: LanguagePicker(compact: true)),
              const SizedBox(height: 12),
              const HomaGramEntrance(child: HomaGramLogo(size: 116)),
              const SizedBox(height: 12),
              HomaGramEntrance(
                delay: const Duration(milliseconds: 100),
                child: Column(children: [
                  Text(_strings.appName, style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text(_strings.tagline, style: TextStyle(color: Color(0xFFD6E8F0), fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 26),
              HomaGramEntrance(
                delay: const Duration(milliseconds: 220),
                child: Card(color: const Color(0xFFF9FBFF), child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: _verificationSent ? _verificationPanel() : _formPanel(),
                )),
              ),
              const SizedBox(height: 18),
              HomaGramEntrance(
                delay: const Duration(milliseconds: 360),
                child: Text(_strings.termsNotice,
                  textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFCAD5E3), fontSize: 11, height: 1.7)),
              ),
            ]),
          ),
        ))),
      ),
    );
  }

  Widget _verificationPanel() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.mark_email_read_outlined, size: 46, color: HomaGramTheme.turquoise),
    const SizedBox(height: 14),
    Text(_strings.checkYourEmail, textAlign: TextAlign.center,
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HomaGramTheme.navy)),
    const SizedBox(height: 10),
    Text(_strings.verificationSentTo(_pendingEmail ?? _strings.yourEmail),
      textAlign: TextAlign.center, style: const TextStyle(height: 1.8, color: Color(0xFF536078))),
    const SizedBox(height: 18),
    FilledButton(onPressed: _busy ? null : _resend, child: Text(_busy ? _strings.sending : _strings.resendEmail)),
    TextButton(onPressed: _busy ? null : () => setState(() { _verificationSent = false; _mode = _Mode.signIn; }),
      child: Text(_strings.backToSignIn)),
  ]);

  Widget _formPanel() => Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(_registering ? _strings.createNewAccount : _strings.signIn, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: HomaGramTheme.navy)),
    const SizedBox(height: 7),
    Text(_registering ? _strings.joinCommunity : _strings.signInToContinue,
      textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64718A))),
    const SizedBox(height: 22),
    if (_registering) ...[
      _field(_displayName, _strings.displayName, Icons.badge_outlined, validator: (v) {
        final value = (v ?? '').trim();
        if (value.isEmpty) return _strings.enterDisplayName;
        if (value.length > 50) return _strings.max50Characters;
        return null;
      }),
      const SizedBox(height: 14),
      _field(_username, _strings.username, Icons.alternate_email, direction: TextDirection.ltr,
        hint: 'your_name', validator: (value) {
          final error = validateHomagramUsername(value);
          return switch (error) {
            'usernameRequired' => _strings.usernameRequired,
            'usernameInvalid' => _strings.usernameInvalid,
            _ => null,
          };
        }),
      const SizedBox(height: 14),
    ],
    _field(_email, _strings.emailAddress, Icons.email_outlined, direction: TextDirection.ltr,
      keyboardType: TextInputType.emailAddress, validator: (v) {
        final value = (v ?? '').trim();
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return _strings.enterValidEmail;
        return null;
      }),
    const SizedBox(height: 14),
    TextFormField(controller: _password, obscureText: _obscure, textDirection: TextDirection.ltr,
      validator: (v) {
        final value = v ?? '';
        if (value.length < 10) return _strings.passwordMinLength;
        if (value.length > 72) return _strings.passwordTooLong;
        return null;
      },
      decoration: InputDecoration(labelText: _strings.password, prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
    if (_registering) ...[
      const SizedBox(height: 14),
      TextFormField(
        controller: _confirmPassword,
        obscureText: _obscureConfirmation,
        textDirection: TextDirection.ltr,
        validator: (v) {
          if ((v ?? '').isEmpty) return _strings.confirmPassword;
          if (v != _password.text) return _strings.passwordsDoNotMatch;
          return null;
        },
        decoration: InputDecoration(
          labelText: _strings.confirmPassword,
          prefixIcon: const Icon(Icons.lock_reset_outlined),
          suffixIcon: IconButton(
            onPressed: () => setState(() => _obscureConfirmation = !_obscureConfirmation),
            icon: Icon(_obscureConfirmation ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
      ),
    ],
    if (!_registering) Align(alignment: AlignmentDirectional.centerStart,
      child: TextButton(onPressed: _busy ? null : _forgotPassword, child: Text(_strings.forgotPassword))),
    if (_registering) ...[
      const SizedBox(height: 10),
      Text(_strings.usernameCannotChange,
        style: TextStyle(fontSize: 11, color: Color(0xFF64718A), height: 1.6)),
    ],
    const SizedBox(height: 18),
    HomaGramSpringPress(
      child: FilledButton(
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: Text(_busy ? _strings.pleaseWait : (_registering ? _strings.createAccount : _strings.signIn)),
      ),
    ),
    const SizedBox(height: 10),
    TextButton(onPressed: _busy ? null : () => setState(() {
      _mode = _registering ? _Mode.signIn : _Mode.signUp;
      _form.currentState?.reset();
      _confirmPassword.clear();
    }), child: Text(_registering ? _strings.alreadyHaveAccount : _strings.noAccountSignUp)),
  ]));

  Widget _field(TextEditingController controller, String label, IconData icon, {
    String? hint, TextDirection? direction, TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => TextFormField(controller: controller, textDirection: direction,
    keyboardType: keyboardType, autocorrect: false, validator: validator,
    decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon)));
}
