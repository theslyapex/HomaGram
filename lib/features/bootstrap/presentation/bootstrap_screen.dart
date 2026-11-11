import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({
    required this.supabaseConfigured,
    super.key,
  });

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF101B35),
              Color(0xFF172A45),
              Color(0xFF24345A),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [HomaGramTheme.turquoise, HomaGramTheme.royalPurple],
                        ),
                      ),
                      child: const Icon(
                        Icons.flutter_dash_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'HomaGram',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ارتباطی فراتر از مرزها',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFD6E8F0),
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Card(
                      color: const Color(0xFFF9FBFF),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'زیرساخت اولیه آماده است',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: HomaGramTheme.navy,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'این نسخه، نقطه شروع توسعه مرحله‌ای هماگرام است. قابلیت‌های حساب کاربری، شبکه اجتماعی و پیام‌رسان در مراحل بعدی ساخته و آزمایش می‌شوند.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF536078),
                                    height: 1.8,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: supabaseConfigured
                                    ? const Color(0xFFE8F7F2)
                                    : const Color(0xFFFFF4E5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    supabaseConfigured
                                        ? Icons.check_circle_outline
                                        : Icons.info_outline,
                                    color: supabaseConfigured
                                        ? const Color(0xFF167B5B)
                                        : const Color(0xFF986018),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      supabaseConfigured
                                          ? 'پیکربندی اتصال Supabase بارگذاری شد'
                                          : 'اتصال Supabase هنوز پیکربندی نشده است',
                                      style: const TextStyle(
                                        color: HomaGramTheme.navy,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'مرحله صفر  •  آماده‌سازی پروژه',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'HomaGram  •  Version 0.1.0',
                      style: TextStyle(
                        color: Color(0xFFB7C6D9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
