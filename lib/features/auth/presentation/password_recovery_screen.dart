import 'package:flutter/material.dart';
import '../../../app/theme/app_theme.dart';
import '../data/auth_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false, _obscure = true;

  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.updatePassword(_password.text);
      await AuthService.signOutThisDevice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('رمز عبور تغییر کرد. اکنون با رمز جدید وارد شوید.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تغییر رمز انجام نشد. دوباره درخواست بازیابی بدهید.'),
        ));
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بازیابی رمز عبور')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Card(child: Padding(padding: const EdgeInsets.all(22),
          child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.lock_reset, size: 48, color: HomaGramTheme.turquoise),
            const SizedBox(height: 14),
            const Text('رمز عبور تازه انتخاب کنید', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 22),
            TextFormField(controller: _password, obscureText: _obscure, textDirection: TextDirection.ltr,
              validator: (v) => (v ?? '').length < 10 ? 'حداقل ۱۰ نویسه وارد کنید.' : null,
              decoration: InputDecoration(labelText: 'رمز عبور جدید',
                suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
            const SizedBox(height: 14),
            TextFormField(controller: _confirm, obscureText: true, textDirection: TextDirection.ltr,
              validator: (v) => v != _password.text ? 'تکرار رمز عبور یکسان نیست.' : null,
              decoration: const InputDecoration(labelText: 'تکرار رمز عبور')),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _save,
              child: Text(_busy ? 'در حال ذخیره...' : 'ثبت رمز جدید')),
          ])),
        )),
      ),
    )),
  );
}
