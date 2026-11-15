import 'dart:async';

import 'package:homagram/app/presentation/homagram_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/messaging_service.dart';
import 'chat_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  AppLocalizations get _t => AppLocalizations.of(context)!;
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
      setState(() { _loading = false; _error = _t.publicCommunitiesSearchFailed; });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
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
        title: Row(children: [
          Icon(Icons.lock_outline_rounded),
          SizedBox(width: 8),
          Expanded(child: Text(_t.privateChannelInviteCode)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_t.privateChannelInviteExplanation),
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
                      SnackBar(content: Text(_t.inviteCodeCopied)),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(_t.copyInviteCode),
              )),
            ),
          ],
        ),
        actions: [
          HomaGramSpringPress(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.gotIt))),
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
          title: Text(_t.createChannel),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: title,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: _t.channelName),
                  validator: (v) => (v == null || v.trim().isEmpty) ? _t.enterChannelName : null,
                ),
                TextFormField(
                  controller: slug,
                  maxLength: 32,
                  decoration: InputDecoration(labelText: _t.channelSlug, prefixText: '@'),
                  validator: (v) => (v == null || !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v.trim()))
                      ? _t.slugRules : null,
                ),
                TextFormField(
                  controller: description,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: _t.descriptionOptional),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isPublic,
                  onChanged: (value) => setDialogState(() => isPublic = value),
                  title: Text(isPublic ? _t.publicChannel : _t.privateChannel),
                  subtitle: Text(isPublic
                      ? _t.publicChannelDiscoverableHint
                      : _t.privateChannelInviteOnlyHint),
                  secondary: Icon(isPublic ? Icons.public_rounded : Icons.lock_rounded),
                ),
              ]),
            ),
          ),
          actions: [
            HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.cancel))),
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
              child: Text(_t.createChannel),
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
              SnackBar(content: Text(_t.channelCreatedInviteFailed)),
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
          SnackBar(content: Text(_t.channelCreateFailedSlugTaken)),
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
        builder: (_) => ChatScreen(
          conversationId: id,
          title: title.trim().isEmpty ? _t.privateChannel : title,
        ),
      ));
      _load(showLoading: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(kind == 'group'
              ? _t.joinPublicGroupFailed
              : _t.joinPublicChannelFailed)),
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
        title: Text(_t.joinPrivateChannel),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: _t.inviteCode,
              hintText: _t.inviteCode64CharHint,
              counterText: '',
            ),
            validator: (value) => value == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value.trim())
                ? _t.enterValid64CharInvite : null,
          ),
        ),
        actions: [
          HomaGramSpringPress(child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t.cancel))),
          HomaGramSpringPress(child: FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
            },
            child: Text(_t.joinMembership),
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
        builder: (_) => ChatScreen(
          conversationId: id,
          title: title.trim().isEmpty ? _t.privateChannel : title,
        ),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t.inviteInvalidExpiredRevoked)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t.publicExplore),
        actions: [
          HomaGramSpringPress(child: IconButton(
            onPressed: _joinByCode,
            tooltip: _t.joinWithPrivateInvite,
            icon: const Icon(Icons.key_rounded),
          )),
          HomaGramSpringPress(child: IconButton(
            onPressed: _create,
            tooltip: _t.createChannel,
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
                Text(
                  _t.discoverPublicGroupsChannels,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  _t.searchAndJoinCommunitiesHint,
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
                    hintText: _t.searchGroupOrChannel,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty ? null : IconButton(
                      tooltip: _t.clearSearch,
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
                      label: Text(_t.all),
                      selected: _filter == 'all',
                      onSelected: (_) => _setFilter('all'),
                    ),
                    ChoiceChip(
                      label: Text(_t.groups),
                      selected: _filter == 'group',
                      onSelected: (_) => _setFilter('group'),
                    ),
                    ChoiceChip(
                      label: Text(_t.channels),
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
                            child: Text(_t.tryAgain),
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
                                      ? _t.noPublicItemsYet
                                      : _t.communitySearchNoResults),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    _t.privateCommunitiesNotShown,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(child: HomaGramSpringPress(child: FilledButton.icon(
                                  onPressed: _create,
                                  icon: const Icon(Icons.add_rounded),
                                  label: Text(_t.createPublicChannel),
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
                                          _t.communityMemberSummary(slug, isGroup ? _t.group : _t.channel, count),
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
                                    child: Text(isMember ? _t.open : _t.joinMembership),
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
