import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  XFile? _media;
  String? _mediaType;
  bool _posting = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _chooseMedia(bool video) async {
    try {
      final file = video
          ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2))
          : await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 88);
      if (file == null) return;
      final mime = file.mimeType ?? '';
      final allowed = video
          ? const ['video/mp4', 'video/quicktime'].contains(mime) || file.name.toLowerCase().endsWith('.mp4') || file.name.toLowerCase().endsWith('.mov')
          : const ['image/jpeg', 'image/png', 'image/webp'].contains(mime) || RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(file.name);
      if (!allowed) {
        _notice('فرمت این فایل پشتیبانی نمی‌شود.', error: true);
        return;
      }
      final bytes = await file.length();
      final limit = video ? 50 * 1024 * 1024 : 15 * 1024 * 1024;
      if (bytes > limit) {
        _notice(video ? 'حجم ویدئو باید حداکثر ۵۰ مگابایت باشد.' : 'حجم تصویر باید حداکثر ۱۵ مگابایت باشد.', error: true);
        return;
      }
      setState(() {
        _media = file;
        _mediaType = video ? 'video' : 'image';
      });
    } catch (_) {
      _notice('انتخاب فایل انجام نشد.', error: true);
    }
  }

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (caption.isEmpty && _media == null) {
      _notice('برای انتشار، متن یا یک تصویر/ویدئو اضافه کنید.', error: true);
      return;
    }
    if (caption.length > 2200) {
      _notice('متن پست حداکثر ۲۲۰۰ نویسه است.', error: true);
      return;
    }
    setState(() => _posting = true);
    String? uploadedPath;
    try {
      final client = AuthService.client;
      final user = client.auth.currentUser!;
      final profile = await client.from('profiles')
          .select('username,display_name')
          .eq('id', user.id)
          .single();

      if (_media != null) {
        final mime = _media!.mimeType ?? _mimeFromName(_media!.name, _mediaType!);
        final ext = _media!.name.contains('.') ? _media!.name.split('.').last.toLowerCase() : (_mediaType == 'video' ? 'mp4' : 'jpg');
        uploadedPath = '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
        await client.storage.from('post-media').uploadBinary(
          uploadedPath,
          await _media!.readAsBytes(),
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
      }

      await client.from('posts').insert({
        'author_id': user.id,
        'author_username': profile['username'],
        'author_display_name': profile['display_name'],
        'caption': caption,
        'media_path': uploadedPath,
        'media_type': uploadedPath == null ? null : _mediaType,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StorageException catch (e) {
      if (uploadedPath != null) {
        try { await AuthService.client.storage.from('post-media').remove([uploadedPath]); } catch (_) {}
      }
      _notice('بارگذاری رسانه انجام نشد: ${e.message}', error: true);
    } on PostgrestException catch (e) {
      if (uploadedPath != null) {
        try { await AuthService.client.storage.from('post-media').remove([uploadedPath]); } catch (_) {}
      }
      _notice(e.code == '23505' ? 'این پست تکراری است.' : 'انتشار پست انجام نشد. دوباره تلاش کنید.', error: true);
    } catch (_) {
      if (uploadedPath != null) {
        try { await AuthService.client.storage.from('post-media').remove([uploadedPath]); } catch (_) {}
      }
      _notice('انتشار پست انجام نشد. اتصال را بررسی کنید.', error: true);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _mimeFromName(String name, String type) {
    final ext = name.split('.').last.toLowerCase();
    if (type == 'video') return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ایجاد پست')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _caption,
          maxLength: 2200,
          maxLines: 7,
          minLines: 4,
          decoration: const InputDecoration(
            hintText: 'چه چیزی می‌خواهید به اشتراک بگذارید؟',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        if (_media != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(_mediaType == 'video' ? Icons.videocam_rounded : Icons.image_outlined,
                    color: HomaGramTheme.turquoise, size: 30),
                const SizedBox(width: 12),
                Expanded(child: Text(_media!.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => setState(() { _media = null; _mediaType = null; }),
                    icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _posting ? null : () => _chooseMedia(false),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('افزودن تصویر'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _posting ? null : () => _chooseMedia(true),
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('افزودن ویدئو (حداکثر ۲ دقیقه)'),
        ),
        const SizedBox(height: 8),
        const Text('تصویر: حداکثر ۱۵ مگابایت • ویدئو: حداکثر ۵۰ مگابایت',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF7A879B))),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _posting ? null : _publish,
          icon: _posting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(_posting ? 'در حال انتشار...' : 'انتشار پست'),
        ),
      ],
    ),
  );
}
