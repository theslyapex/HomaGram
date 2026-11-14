import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await MessagingService.loadPublicChannels();
      if (!mounted) return;
      setState(() { _channels = rows; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'دریافت فهرست کانال‌ها ممکن نشد.'; });
    }
  }

  Future<void> _showInviteCode(String token) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_outline_rounded),
          SizedBox(width: 8),
          Expanded(child: Text('کد دعوت کانال خصوصی')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('این کد تا ۷ روز معتبر است و حداکثر ۱۰۰ بار قابل استفاده است. فقط برای افرادی بفرستید که می‌خواهید عضو کانال شوند.'),
            const SizedBox(height: 14),
            SelectableText(
              token,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: HomaGramSpringPress(child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('کد دعوت کپی شد.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('کپی کد دعوت'),
              )),
            ),
          ],
        ),
        actions: [
          HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('متوجه شدم'))),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final slug = TextEditingController();
    final description = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isPublic = true;

    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ساخت کانال'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: title,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'نام کانال'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'نام کانال را وارد کنید' : null,
                ),
                TextFormField(
                  controller: slug,
                  maxLength: 32,
                  decoration: const InputDecoration(labelText: 'شناسه کانال', prefixText: '@'),
                  validator: (v) => (v == null || !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v.trim()))
                      ? '۳ تا ۳۲ حرف انگلیسی، عدد یا زیرخط' : null,
                ),
                TextFormField(
                  controller: description,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPublic,
                  onChanged: (value) => setDialogState(() => isPublic = value),
                  title: Text(isPublic ? 'کانال عمومی' : 'کانال خصوصی'),
                  subtitle: Text(isPublic
                      ? 'همه کاربران می‌توانند آن را پیدا کنند و عضو شوند.'
                      : 'فقط با کد دعوت می‌توان به کانال پیوست.'),
                  secondary: Icon(isPublic ? Icons.public_rounded : Icons.lock_rounded),
                ),
              ]),
            ),
          ),
          actions: [
            HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))),
            HomaGramSpringPress(child: FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, {
                    'title': title.text,
                    'slug': slug.text,
                    'description': description.text,
                    'isPublic': isPublic,
                  });
                }
              },
              child: const Text('ساخت کانال'),
            )),
          ],
        ),
      ),
    );

    if (values == null || !mounted) {
      title.dispose(); slug.dispose(); description.dispose();
      return;
    }

    final channelTitle = (values['title'] as String).trim();
    final isPublicChannel = values['isPublic'] as bool;
    try {
      final id = await MessagingService.createChannel(
        title: channelTitle,
        slug: values['slug'] as String,
        description: values['description'] as String,
        isPublic: isPublicChannel,
      );

      if (!mounted) return;
      if (!isPublicChannel) {
        try {
          final token = await MessagingService.createChannelInvite(id);
          if (!mounted) return;
          await _showInviteCode(token);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('کانال ساخته شد، اما ایجاد کد دعوت انجام نشد. از بخش مدیریت کانال دوباره تلاش کنید.')),
            );
          }
        }
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: id, title: channelTitle),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ساخت کانال انجام نشد؛ ممکن است شناسه قبلاً استفاده شده باشد.')),
        );
      }
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
        builder: (_) => ChatScreen(conversationId: id, title: title ?? '@${channel['slug']}'),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('عضویت در کانال انجام نشد.')),
        );
      }
    }
  }

  Future<void> _joinByCode() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ورود به کانال خصوصی'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'کد دعوت',
              hintText: 'کد ۶۴ کاراکتری',
              counterText: '',
            ),
            validator: (value) => value == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value.trim())
                ? 'کد دعوت معتبر ۶۴ کاراکتری وارد کنید.' : null,
          ),
        ),
        actions: [
          HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف'))),
          HomaGramSpringPress(child: FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('عضویت'),
          )),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    try {
      final id = await MessagingService.joinChannelByInvite(code);
      final title = await MessagingService.loadChannelTitle(id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: id, title: title),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کد دعوت نامعتبر، منقضی یا غیرفعال است.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('کانال‌ها'),
        actions: [
          HomaGramSpringPress(child: IconButton(
            onPressed: _joinByCode,
            tooltip: 'ورود با کد دعوت',
            icon: const Icon(Icons.key_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            onPressed: _create,
            tooltip: 'ساخت کانال',
            icon: const Icon(Icons.add_circle_outline),
          )),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [
                SizedBox(height: 220),
                Center(child: CircularProgressIndicator()),
              ])
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 140),
                    Center(child: Text(_error!)),
                    Center(child: HomaGramSpringPress(child: TextButton(onPressed: _load, child: const Text('تلاش دوباره')))),
                  ])
                : _channels.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 100),
                          Icon(Icons.campaign_outlined, size: 58, color: colors.primary),
                          const SizedBox(height: 12),
                          const Center(child: Text('هنوز کانال عمومی ساخته نشده است')),
                          const SizedBox(height: 12),
                          Center(child: HomaGramSpringPress(child: FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add),
                            label: const Text('ساخت اولین کانال'),
                          ))),
                          Center(child: HomaGramSpringPress(child: TextButton.icon(
                            onPressed: _joinByCode,
                            icon: const Icon(Icons.key_rounded),
                            label: const Text('ورود با کد دعوت خصوصی'),
                          ))),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _channels.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                        itemBuilder: (context, index) {
                          final item = _channels[index];
                          final conversation = item['conversations'];
                          final title = conversation is Map ? conversation['title'] as String? : null;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colors.primaryContainer,
                              child: Icon(Icons.campaign_rounded, color: colors.onPrimaryContainer),
                            ),
                            title: Text(
                              title ?? '@${item['slug']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '@${item['slug']} • ${item['description'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: HomaGramSpringPress(child: FilledButton.tonal(
                              onPressed: () => _join(item),
                              child: const Text('عضویت'),
                            )),
                          );
                        },
                      ),
      ),
    );
  }
}
