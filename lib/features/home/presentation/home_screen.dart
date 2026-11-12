import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/presentation/profile_home_screen.dart';
import 'feed_screen.dart';
import '../../messaging/presentation/messaging_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedScreen(),
      const _ComingSoonPage(
        icon: Icons.explore_outlined,
        title: 'کشف HomaGram',
        description: 'جست‌وجوی افراد، موضوعات و محتوای موردعلاقه در مرحله بعد فعال می‌شود.',
      ),
      const MessagingScreen(),
      const _ComingSoonPage(
        icon: Icons.notifications_none_rounded,
        title: 'اعلان‌ها',
        description: 'اعلان‌های دنبال‌کردن، پسندیدن و پیام‌ها اینجا نمایش داده می‌شوند.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.bubble_chart_rounded, color: HomaGramTheme.turquoise, size: 29),
            SizedBox(width: 8),
            Text('HomaGram', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.4)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'پروفایل من',
            onPressed: _openProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'جست‌وجو'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_rounded), label: 'پیام‌ها'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_rounded), label: 'اعلان‌ها'),
        ],
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: HomaGramTheme.turquoise.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: HomaGramTheme.turquoise),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              Text(description, textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.9, color: Color(0xFF7A879B))),
              const SizedBox(height: 14),
              const Chip(label: Text('در حال توسعه')),
            ],
          ),
        ),
      );
}
