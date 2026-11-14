import 'package:flutter/material.dart';
import '../data/messaging_service.dart';
import 'chat_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await MessagingService.loadPublicChannels();
      if (!mounted) return;
      setState(() { _channels = rows; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت فهرست کانال‌ها ممکن نشد.'; });
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final slug = TextEditingController();
    final description = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ساخت کانال عمومی'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: title, maxLength: 100,
              decoration: const InputDecoration(labelText: 'نام کانال'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'نام کانال را وارد کنید' : null),
            TextFormField(controller: slug, maxLength: 32,
              decoration: const InputDecoration(labelText: 'شناسه کانال', prefixText: '@'),
              validator: (v) => (v == null || !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v.trim()))
                ? '۳ تا ۳۲ حرف انگلیسی، عدد یا زیرخط' : null),
            TextFormField(controller: description, maxLength: 500, maxLines: 3,
              decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)')),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, [title.text, slug.text, description.text]);
            }
          }, child: const Text('ساخت کانال')),
        ],
      ),
    );
    if (values == null || !mounted) {
      title.dispose(); slug.dispose(); description.dispose(); return;
    }
    try {
      final id = await MessagingService.createChannel(
        title: values[0], slug: values[1], description: values[2]);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: id, title: values[0].trim())));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ساخت کانال انجام نشد؛ ممکن است شناسه قبلاً استفاده شده باشد.')));
    } finally {
      title.dispose(); slug.dispose(); description.dispose();
    }
  }

  Future<void> _join(Map<String, dynamic> channel) async {
    final id = channel['conversation_id'] as String;
    try {
      await MessagingService.joinPublicChannel(id);
      if (!mounted) return;
      final conversation = channel['conversations'];
      final title = conversation is Map ? conversation['title'] as String? : null;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: id, title: title ?? '@${channel['slug']}')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عضویت در کانال انجام نشد.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('کانال‌ها'),
        actions: [IconButton(onPressed: _create, tooltip: 'ساخت کانال', icon: const Icon(Icons.add_circle_outline))]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
          ? ListView(children: [const SizedBox(height: 220), const Center(child: CircularProgressIndicator())])
          : _error != null
            ? ListView(children: [const SizedBox(height: 140), Center(child: Text(_error!)),
                Center(child: TextButton(onPressed: _load, child: const Text('تلاش دوباره')))])
            : _channels.isEmpty
              ? ListView(children: [const SizedBox(height: 110),
                  Icon(Icons.campaign_outlined, size: 58, color: colors.primary),
                  const SizedBox(height: 12),
                  const Center(child: Text('هنوز کانال عمومی ساخته نشده است')),
                  const SizedBox(height: 12),
                  Center(child: FilledButton.icon(onPressed: _create,
                    icon: const Icon(Icons.add), label: const Text('ساخت اولین کانال')))])
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _channels.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, index) {
                    final item = _channels[index];
                    final conversation = item['conversations'];
                    final title = conversation is Map ? conversation['title'] as String? : null;
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: colors.primaryContainer,
                        child: Icon(Icons.campaign_rounded, color: colors.onPrimaryContainer)),
                      title: Text(title ?? '@${item['slug']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('@${item['slug']} • ${item['description'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: FilledButton.tonal(onPressed: () => _join(item), child: const Text('عضویت')),
                    );
                  },
                ),
      ),
    );
  }
}
