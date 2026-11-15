import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/presentation/homagram_branding.dart';
import '../../auth/data/auth_service.dart';
import '../../admin/data/admin_service.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import 'feed_screen.dart';
import 'explore_screen.dart';
import 'public_profile_screen.dart';
import '../../messaging/presentation/messaging_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/data/notification_service.dart';
import '../../settings/presentation/settings_screen.dart';

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

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
  }) {
    final selected = _tab == index;
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: () => setState(() => _tab = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary.withValues(alpha: .13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 23,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const FeedScreen(),
      const ExploreScreen(),
      const MessagingScreen(),
      PublicProfileScreen(userId: AuthService.client.auth.currentUser!.id),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const HomaGramEntrance(
          delay: Duration(milliseconds: 100),
          child: Row(
          children: [
            HomaGramLogo(size: 38),
            SizedBox(width: 8),
            Text('HomaGram', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.4)),
          ],
        )),
        actions: [
          IconButton(
            tooltip: 'تنظیمات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'اعلان‌ها',
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(_unreadNotifications > 99 ? '99+' : '$_unreadNotifications'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
            ),
          ),
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
      body: HomaGramEntrance(
        delay: const Duration(milliseconds: 90),
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark ? .22 : .09,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildNavItem(
                      index: 0,
                      label: 'خانه',
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                    ),
                    _buildNavItem(
                      index: 1,
                      label: 'کشف',
                      icon: Icons.search_rounded,
                      selectedIcon: Icons.explore_rounded,
                    ),
                    _buildNavItem(
                      index: 2,
                      label: 'پیام‌ها',
                      icon: Icons.chat_bubble_outline_rounded,
                      selectedIcon: Icons.chat_rounded,
                    ),
                    _buildNavItem(
                      index: 3,
                      label: 'پروفایل',
                      icon: Icons.person_outline_rounded,
                      selectedIcon: Icons.person_rounded,
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
