import 'dart:async';

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
  List<Map<String, dynamic>> _communities = [];
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _filter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() { _loading = true; _error = null; });
    try {
      final rows = await MessagingService.searchPublicCommunities(
        query: _search.text,
        kind: _filter,
      );
      if (!mounted) return;
      setState(() { _communities = rows; _loading = false; _error = null; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'جست‌وجوی گروه‌ها و کانال‌های عمومی انجام نشد.'; });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
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

  Future<void> _openCommunity(Map<String, dynamic> item) async {
    final id = item['conversation_id'] as String;
    final kind = item['kind'] as String;
    final title = item['title'] as String? ?? '@${item['slug']}';
    try {
      if (item['is_member'] != true) {
        if (kind == 'group') {
          await MessagingService.joinPublicGroup(id);
        } else {
          await MessagingService.joinPublicChannel(id);
        }
      }
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversationId: id, title: title),
      ));
      _load(showLoading: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(kind == 'group'
              ? 'عضویت در گروه عمومی انجام نشد.'
              : 'عضویت در کانال عمومی انجام نشد.')),
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
        title: const Text('کشف عمومی'),
        actions: [
          HomaGramSpringPress(child: IconButton(
            onPressed: _joinByCode,
            tooltip: 'ورود با کد دعوت خصوصی',
            icon: const Icon(Icons.key_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            onPressed: _create,
            tooltip: 'ساخت کانال',
            icon: const Icon(Icons.add_circle_outline),
          )),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'گروه‌ها و کانال‌های عمومی را پیدا کن',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  'با نام، شناسه یا توضیحات جست‌وجو کن و مستقیم عضو شو.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _searchDebounce?.cancel();
                    _load();
                  },
                  decoration: InputDecoration(
                    hintText: 'جست‌وجوی گروه یا کانال',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty ? null : IconButton(
                      tooltip: 'پاک کردن جست‌وجو',
                      onPressed: () {
                        _search.clear();
                        _load();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('همه'),
                      selected: _filter == 'all',
                      onSelected: (_) => _setFilter('all'),
                    ),
                    ChoiceChip(
                      label: const Text('گروه‌ها'),
                      selected: _filter == 'group',
                      onSelected: (_) => _setFilter('group'),
                    ),
                    ChoiceChip(
                      label: const Text('کانال‌ها'),
                      selected: _filter == 'channel',
                      onSelected: (_) => _setFilter('channel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(children: const [
                      SizedBox(height: 180),
                      Center(child: CircularProgressIndicator()),
                    ])
                  : _error != null
                      ? ListView(children: [
                          const SizedBox(height: 130),
                          Center(child: Text(_error!)),
                          Center(child: TextButton(
                            onPressed: _load,
                            child: const Text('تلاش دوباره'),
                          )),
                        ])
                      : _communities.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 90),
                                Icon(Icons.travel_explore_rounded, size: 58, color: colors.primary),
                                const SizedBox(height: 14),
                                Center(
                                  child: Text(_search.text.trim().isEmpty
                                      ? 'هنوز مورد عمومی‌ای برای نمایش وجود ندارد.'
                                      : 'نتیجه‌ای برای این جست‌وجو پیدا نشد.'),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    'گروه‌ها و کانال‌های خصوصی در این بخش نمایش داده نمی‌شوند.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(child: HomaGramSpringPress(child: FilledButton.icon(
                                  onPressed: _create,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('ساخت کانال عمومی'),
                                ))),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _communities.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                              itemBuilder: (context, index) {
                                final item = _communities[index];
                                final isGroup = item['kind'] == 'group';
                                final isMember = item['is_member'] == true;
                                final title = item['title'] as String? ?? '';
                                final slug = item['slug'] as String? ?? '';
                                final description = item['description'] as String? ?? '';
                                final count = item['member_count'] ?? 0;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: isGroup
                                        ? const Color(0xFF7356C8).withValues(alpha: .16)
                                        : const Color(0xFF20B8B0).withValues(alpha: .16),
                                    child: Icon(
                                      isGroup ? Icons.groups_rounded : Icons.campaign_rounded,
                                      color: isGroup ? const Color(0xFF9B83FF) : const Color(0xFF20B8B0),
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '@$slug  •  ${isGroup ? 'گروه' : 'کانال'}  •  $count عضو',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (description.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
                                          ),
                                      ],
                                    ),
                                  ),
                                  trailing: HomaGramSpringPress(child: FilledButton.tonal(
                                    onPressed: () => _openCommunity(item),
                                    child: Text(isMember ? 'باز کردن' : 'عضویت'),
                                  )),
                                  onTap: () => _openCommunity(item),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
