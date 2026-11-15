import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();
  static const _key = 'homagram_language_code';
  Locale _locale = const Locale('fa');
  Locale get locale => _locale;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code == 'en' || code == 'ar' || code == 'fa') {
      _locale = Locale(code!);
    }
    _loaded = true;
  }

  Future<void> setLanguage(String code) async {
    if (!['fa', 'en', 'ar'].contains(code)) return;
    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
    notifyListeners();
  }
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLanguage.instance,
      builder: (context, _) {
        final code = AppLanguage.instance.locale.languageCode;
        final strings = AppLocalizations.of(context)!;
        final label = code == 'en' ? strings.english : code == 'ar' ? strings.arabic : strings.persian;
        return PopupMenuButton<String>(
          tooltip: strings.language,
          onSelected: AppLanguage.instance.setLanguage,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'fa', child: Text('فارسی')),
            PopupMenuItem(value: 'en', child: Text('English')),
            PopupMenuItem(value: 'ar', child: Text('العربية')),
          ],
          child: compact
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.language_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 7),
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                )
              : ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(strings.language),
                  subtitle: Text(label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
        );
      },
    );
  }
}
