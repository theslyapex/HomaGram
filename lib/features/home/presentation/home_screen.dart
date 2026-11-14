import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../../admin/data/admin_service.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import 'feed_screen.dart';
import 'reels_screen.dart';
import 'explore_screen.dart';
import 'public_profile_screen.dart';
import '../../messaging/presentation/messaging_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/data/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _unreadNotifications = 0;
  bool _isAdmin = false;
  RealtimeChannel? _notificationChannel;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
    _loadAdminAccess();
    final userId = AuthService.client.auth.currentUser?.id;
    if (userId != null) {
      _notificationChannel = AuthService.client.channel('home-notification-count-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_id', value: userId),
          callback: (_) => _refreshUnread(),
        ).subscribe();
    }
  }

  Future<void> _loadAdminAccess() async {
    try {
      final allowed = await AdminService.isCurrentUserAdmin();
      if (mounted) setState(() => _isAdmin = allowed);
    } catch (_) {
      if (mounted) setState(() => _isAdmin = false);
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final count = await NotificationService.unreadCount();
      if (mounted && count != _unreadNotifications) {
        setState(() => _unreadNotifications = count);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final channel = _notificationChannel;
    if (channel != null) AuthService.client.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedScreen(),
      ReelsScreen(isVisible: _tab == 1),
      const ExploreScreen(),
      const MessagingScreen(),
      const NotificationsScreen(),
      PublicProfileScreen(userId: AuthService.client.auth.currentUser!.id),
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
          if (_isAdmin)
            IconButton(
              tooltip: 'پنل مدیریت',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminDashboardScreen(),
                ),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.video_collection_outlined), selectedIcon: Icon(Icons.video_collection_rounded), label: 'ریلز'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'جست‌وجو'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_rounded), label: 'پیام‌ها'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(_unreadNotifications > 99 ? '99+' : '$_unreadNotifications'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(_unreadNotifications > 99 ? '99+' : '$_unreadNotifications'),
              child: const Icon(Icons.notifications_rounded),
            ),
            label: 'اعلان‌ها',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'پروفایل'),
        ],
      ),
    );
  }
}
