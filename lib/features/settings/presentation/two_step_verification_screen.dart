import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/presentation/homagram_branding.dart';

class TwoStepVerificationScreen extends StatefulWidget {
  const TwoStepVerificationScreen({super.key});

  @override
  State<TwoStepVerificationScreen> createState() => _TwoStepVerificationScreenState();
}

class _TwoStepVerificationScreenState extends State<TwoStepVerificationScreen> {
  final _code = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _factorId;
  String? _secret;
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final factors = await _client.auth.mfa.listFactors();
      final verified = factors.totp.where((factor) =>
        factor.status.toString().toLowerCase().contains('verified')).toList();
      if (!mounted) return;
      setState(() {
        _factorId = verified.isEmpty ? null : verified.first.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'وضعیت تأیید دومرحله‌ای دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _beginEnrollment() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'HomaGram',
        friendlyName: 'HomaGram Authenticator',
      );
      if (!mounted) return;
      setState(() {
        _factorId = result.id;
        _secret = result.totp.secret;
        _code.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'شروع فعال‌سازی انجام نشد. کمی بعد دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEnrollment() async {
    final id = _factorId;
    final code = _code.text.trim();
    if (id == null || _secret == null || code.length != 6 || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _client.auth.mfa.challengeAndVerify(factorId: id, code: code);
      if (!mounted) return;
      setState(() {
        _secret = null;
        _code.clear();
      });
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تأیید دومرحله‌ای با موفقیت فعال شد.')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'کد واردشده معتبر نیست یا منقضی شده است. کد تازه را وارد کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final id = _factorId;
    final code = _code.text.trim();
    if (id == null || code.length != 6 || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('غیرفعال‌سازی تأیید دومرحله‌ای'),
        content: const Text('برای خاموش‌کردن این لایه امنیتی، کد فعلی برنامه احراز هویت را وارد و عملیات را تأیید کنید.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید و غیرفعال‌سازی')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _client.auth.mfa.challengeAndVerify(factorId: id, code: code);
      await _client.auth.mfa.unenroll(factorId: id);
      await _client.auth.refreshSession();
      _code.clear();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تأیید دومرحله‌ای غیرفعال شد.')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'غیرفعال‌سازی انجام نشد. کد فعلی را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _factorId != null && _secret == null;
    return Scaffold(
      appBar: AppBar(title: const Text('تأیید دومرحله‌ای')),
      body: HomaGramEntrance(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF293C75), Color(0xFF174D60), Color(0xFF17233E)],
              ),
            ),
            child: const Row(children: [
              Icon(Icons.shield_moon_rounded, color: Colors.white, size: 34),
              SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('یک لایه امنیتی بیشتر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                SizedBox(height: 5),
                Text('پس از رمز عبور، کد زمان‌دار برنامه احراز هویت نیز لازم می‌شود.',
                  style: TextStyle(color: Colors.white70, height: 1.7, fontSize: 11)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator())
          else if (_error != null && _factorId == null && _secret == null)
            _errorBox()
          else if (_secret != null) ...[
            _statusCard('در حال راه‌اندازی', 'کلید زیر را در برنامه احراز هویت وارد کنید؛ سپس کد شش‌رقمی را برای تأیید بنویسید.', Icons.qr_code_2_rounded),
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('کلید راه‌اندازی خصوصی', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                SelectableText(_secret!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: _secret!)),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('کپی کلید'),
                ),
              ]),
            )),
            const SizedBox(height: 12),
            _codeField(),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _verifyEnrollment,
              icon: _busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_rounded),
              label: const Text('تأیید و فعال‌سازی'),
            ),
            const SizedBox(height: 8),
            const Text('کلید را فقط در برنامه احراز هویت خود وارد کنید و آن را برای هیچ‌کس نفرستید.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4))),
          ] else if (enabled) ...[
            _statusCard('تأیید دومرحله‌ای فعال است', 'برای ورود به هماگرام، علاوه بر روش ورود اصلی، کد برنامه احراز هویت لازم است.',
              Icons.verified_user_rounded),
            const SizedBox(height: 14),
            _codeField(hint: 'کد فعلی برای غیرفعال‌سازی'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _disable,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('غیرفعال‌سازی با کد فعلی'),
            ),
          ] else ...[
            _statusCard('تأیید دومرحله‌ای خاموش است', 'با فعال‌سازی، ورود به حساب به کد زمان‌دار برنامه احراز هویت نیز نیاز خواهد داشت.',
              Icons.shield_outlined),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _beginEnrollment,
              icon: _busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shield_rounded),
              label: const Text('فعال‌سازی تأیید دومرحله‌ای'),
            ),
          ],
          if (_error != null && (_factorId != null || _secret != null)) ...[
            const SizedBox(height: 12),
            _errorBox(),
          ],
          const SizedBox(height: 14),
          const Text('نکته: هماگرام کدهای بازیابی جداگانه ارائه نمی‌کند. دسترسی امن به برنامه احراز هویت خود را حفظ کنید؛ در صورت گم‌شدن دستگاه، از مسیر پشتیبانی درخواست راهنمایی کنید.',
            style: TextStyle(fontSize: 11, height: 1.8, color: Color(0xFF8490A4))),
        ],
      )),
    );
  }

  Widget _codeField({String hint = 'کد شش‌رقمی برنامه احراز هویت'}) => TextField(
    controller: _code,
    keyboardType: TextInputType.number,
    textAlign: TextAlign.center,
    maxLength: 6,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: hint,
      counterText: '',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
    ),
  );

  Widget _statusCard(String title, String body, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HomaGramTheme.turquoise.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .22)),
    ),
    child: Row(children: [
      Icon(icon, color: HomaGramTheme.turquoise, size: 27),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text(body, style: const TextStyle(fontSize: 11, height: 1.7)),
      ])),
    ]),
  );

  Widget _errorBox() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(_error ?? '', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
  );
}

class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({required this.onVerified, super.key});
  final VoidCallback onVerified;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  String? _factorId;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFactor();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadFactor() async {
    try {
      final factors = await Supabase.instance.client.auth.mfa.listFactors();
      final verified = factors.totp.where((factor) =>
        factor.status.toString().toLowerCase().contains('verified')).toList();
      if (!mounted) return;
      setState(() {
        _factorId = verified.isEmpty ? null : verified.first.id;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'عامل امنیتی حساب دریافت نشد.'; });
    }
  }

  Future<void> _verify() async {
    final id = _factorId;
    final code = _code.text.trim();
    if (id == null || code.length != 6 || _busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(factorId: id, code: code);
      await Supabase.instance.client.auth.refreshSession();
      if (mounted) widget.onVerified();
    } catch (_) {
      if (mounted) setState(() => _error = 'کد معتبر نیست یا منقضی شده است. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const HomaGramLogo(size: 100),
          const SizedBox(height: 18),
          const Text('تأیید هویت دومرحله‌ای', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('کد شش‌رقمی برنامه احراز هویت را وارد کنید تا ورود به حساب تکمیل شود.',
            textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
          const SizedBox(height: 18),
          if (_loading) const CircularProgressIndicator()
          else if (_factorId == null)
            const Text('عامل تأییدشده‌ای پیدا نشد. برای راهنمایی با پشتیبانی تماس بگیرید.', textAlign: TextAlign.center)
          else ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'کد شش‌رقمی', counterText: ''),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy ? const CircularProgressIndicator() : const Text('تأیید و ورود'),
            )),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('خروج از حساب'),
          ),
        ]),
      ),
    )),
  );
}
