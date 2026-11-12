import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/presentation/profile_home_screen.dart';

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
      _homeFeed(),
      const _ComingSoonPage(
        icon: Icons.explore_outlined,
        title: 'کشف HomaGram',
        description: 'جست‌وجوی افراد، موضوعات و محتوای موردعلاقه در مرحله بعد فعال می‌شود.',
      ),
      const _ComingSoonPage(
        icon: Icons.forum_outlined,
        title: 'گفت‌وگوها',
        description: 'فضای پیام‌های خصوصی در مرحله پیام‌رسانی ساخته خواهد شد.',
      ),
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

  Widget _homeFeed() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF101B35), Color(0xFF273D68), Color(0xFF315A72)],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('فراتر از مرزها، نزدیک‌تر از همیشه',
                    style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.6)),
                SizedBox(height: 7),
                Text('به HomaGram خوش آمدید؛ ارتباط، اشتراک‌گذاری و گفت‌وگو در یک تجربه واحد.',
                    style: TextStyle(color: Color(0xFFDCE8F4), height: 1.9, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text('فضای شما', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: _openProfile,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('پروفایل'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _quickActions(),
          const SizedBox(height: 24),
          const Text('تازه‌ها', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .18)),
            ),
            child: const Column(
              children: [
                Icon(Icons.dynamic_feed_outlined, size: 46, color: HomaGramTheme.turquoise),
                SizedBox(height: 12),
                Text('هنوز پستی برای نمایش وجود ندارد',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                SizedBox(height: 7),
                Text('با شروع فعالیت کاربران، پست‌ها و به‌روزرسانی‌ها در این بخش دیده می‌شوند.',
                    textAlign: TextAlign.center, style: TextStyle(height: 1.8, fontSize: 12, color: Color(0xFF7A879B))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('HomaGram • Connection Beyond Boundaries',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Color(0xFF8792A5))),
          ),
        ],
      );

  Widget _quickActions() => Row(
        children: [
          Expanded(child: _quickAction(Icons.person_search_outlined, 'پیدا کردن افراد', () => setState(() => _tab = 1))),
          const SizedBox(width: 10),
          Expanded(child: _quickAction(Icons.chat_outlined, 'شروع گفت‌وگو', () => setState(() => _tab = 2))),
          const SizedBox(width: 10),
          Expanded(child: _quickAction(Icons.notifications_none, 'اعلان‌ها', () => setState(() => _tab = 3))),
        ],
      );

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 17),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .18)),
          ),
          child: Column(
            children: [
              Icon(icon, color: HomaGramTheme.turquoise, size: 24),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
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
