import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/admin_service.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  String _type = 'all';
  final List<AdminModerationItem> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  String? _error;
  String? _working;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final rows = await AdminService.loadModerationContent(type: _type, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _offset += rows.length;
        _hasMore = rows.length == 50;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'دریافت فهرست محتوا انجام نشد. دسترسی مدیریتی و اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _preview(AdminModerationItem item) async {
    final url = item.type == 'profile' ? item.avatarUrl :
        (item.mediaType == 'video' ? (item.mediaUrl ?? item.coverUrl) : (item.mediaUrl ?? item.coverUrl));
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای این محتوا پیش‌نمایش رسانه‌ای در دسترس نیست.')));
      return;
    }
    if (item.type != 'profile' && item.mediaType == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  IconButton(
                    onPressed: () => controller.value.isPlaying ? controller.pause() : controller.play(),
                    icon: Icon(controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  const Expanded(child: Text('پیش‌نمایش ریلز', style: TextStyle(fontWeight: FontWeight.w800))),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                ]),
              ]),
            ),
          ),
        );
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پخش پیش‌نمایش ویدئو ممکن نشد.')));
      } finally {
        await controller.dispose();
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 160, child: Center(child: Text('بارگذاری تصویر ممکن نشد.')))),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ]),
        ),
      ),
    );
  }

  Future<void> _warn(AdminModerationItem item) async {
    final controller = TextEditingController(
      text: 'محتوای منتشرشده شما با بخشی از مقررات هماگرام مغایرت دارد. لطفاً پیش از انتشار محتوای بعدی، راهنمای جامعه و قوانین را مطالعه کنید.');
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ارسال اخطار به کاربر'),
        content: TextField(
          controller: controller, minLines: 3, maxLines: 6, maxLength: 900,
          decoration: const InputDecoration(labelText: 'متن اخطار', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('ارسال اخطار')),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.length < 8) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'warn_user', userId: item.authorId, message: message,
    ), success: 'اخطار برای کاربر ارسال شد.');
  }

  Future<void> _ban(AdminModerationItem item) async {
    String duration = '168h';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('مسدودسازی حساب کاربر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('مدت محدودیت را انتخاب کنید. حساب‌های مدیریتی از این اقدام محافظت می‌شوند.'),
          const SizedBox(height: 10),
          RadioListTile<String>(value: '24h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: const Text('۲۴ ساعت')),
          RadioListTile<String>(value: '168h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: const Text('۷ روز')),
          RadioListTile<String>(value: '720h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: const Text('۳۰ روز')),
          RadioListTile<String>(value: '876000h', groupValue: duration, onChanged: (v) => update(() => duration = v!), title: const Text('بلندمدت')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, duration),
            child: const Text('تأیید مسدودسازی'),
          ),
        ],
      )),
    );
    if (selected == null) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'ban_user', userId: item.authorId, duration: selected,
    ), success: 'حساب کاربر مسدود شد.');
  }

  Future<void> _delete(AdminModerationItem item) async {
    if (item.type == 'profile') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف محتوا'),
        content: const Text('این پست یا ریلز از هماگرام حذف می‌شود و برای صاحب حساب اخطار ارسال خواهد شد. این عملیات قابل بازگشت نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف و ارسال اخطار'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runAction(item, () => AdminService.moderateContent(
      action: 'delete_post', postId: item.id,
    ), success: 'محتوا حذف شد و اخطار برای صاحب آن ارسال شد.', removeItem: true);
  }

  Future<void> _runAction(
    AdminModerationItem item,
    Future<void> Function() action, {
    required String success,
    bool removeItem = false,
  }) async {
    if (_working != null) return;
    setState(() => _working = item.id);
    try {
      await action();
      if (!mounted) return;
      if (removeItem) _items.removeWhere((x) => x.id == item.id && x.type == item.type);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اقدام مدیریتی انجام نشد. نتیجه را بررسی و دوباره تلاش کنید.')));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  String _typeLabel(String type) => switch (type) {
    'post' => 'پست', 'reel' => 'ریلز', 'profile' => 'پروفایل', _ => 'محتوا',
  };

  String _date(DateTime? value) {
    if (value == null) return 'زمان نامشخص';
    final d = value.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(children: [
        const Expanded(child: Text('فهرست محتوای منتشرشده', style: TextStyle(fontWeight: FontWeight.w900))),
        DropdownButton<String>(
          value: _type,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('همه')),
            DropdownMenuItem(value: 'post', child: Text('پست‌ها')),
            DropdownMenuItem(value: 'reel', child: Text('ریلزها')),
            DropdownMenuItem(value: 'profile', child: Text('پروفایل‌ها')),
          ],
          onChanged: (value) {
            if (value == null || value == _type) return;
            setState(() => _type = value);
            _load(reset: true);
          },
        ),
      ]),
    ),
    if (_error != null)
      Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton.tonal(onPressed: () => _load(reset: true), child: const Text('تلاش دوباره')),
      ])))
    else if (_loading && _items.isEmpty)
      const Expanded(child: Center(child: CircularProgressIndicator()))
    else
      Expanded(child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
          itemCount: _items.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _load(),
                  child: Text(_loading ? 'در حال دریافت…' : 'نمایش موارد بیشتر'),
                ),
              ));
            }
            final item = _items[index];
            final busy = _working == item.id;
            final name = item.displayName?.trim().isNotEmpty == true
              ? item.displayName!.trim() : (item.username == null ? 'کاربر هماگرام' : '@${item.username}');
            final previewUrl = item.type == 'profile' ? item.avatarUrl :
              (item.mediaType == 'video' ? item.coverUrl : item.mediaUrl);
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundImage: item.avatarUrl == null ? null : NetworkImage(item.avatarUrl!),
                      child: item.avatarUrl == null ? const Icon(Icons.person_outline_rounded) : null,
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text('@${item.username ?? 'بدون نام کاربری'}',
                        style: Theme.of(context).textTheme.labelSmall,
                        textDirection: TextDirection.ltr),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF20B8B0).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_typeLabel(item.type), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  if (previewUrl != null) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () => _preview(item),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Stack(children: [
                          SizedBox(
                            height: 175, width: double.infinity,
                            child: Image.network(previewUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0x221F8F8A), child: SizedBox(height: 175)),
                            ),
                          ),
                          if (item.type != 'profile' && item.mediaType == 'video')
                            const Positioned.fill(child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 52, color: Colors.white))),
                          const Positioned(right: 8, bottom: 8, child: Icon(Icons.open_in_full_rounded, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ],
                  if ((item.caption ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(item.caption!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.7)),
                  ],
                  if (item.type == 'profile' && (item.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.bio!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.7)),
                  ],
                  const SizedBox(height: 7),
                  Text('شناسه محتوا: ${item.id}  •  ${_date(item.createdAt)}',
                    style: Theme.of(context).textTheme.labelSmall),
                  Text('شناسه صاحب محتوا: ${item.authorId}',
                    style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _warn(item),
                      icon: const Icon(Icons.warning_amber_rounded, size: 17),
                      label: const Text('ارسال اخطار'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _ban(item),
                      icon: const Icon(Icons.block_rounded, size: 17),
                      label: const Text('مسدودسازی حساب'),
                    ),
                    if (item.type != 'profile')
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : () => _delete(item),
                        icon: busy
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline_rounded, size: 17),
                        label: const Text('حذف محتوا'),
                      ),
                  ]),
                ]),
              ),
            );
          },
        ),
      )),
  ]);
}
