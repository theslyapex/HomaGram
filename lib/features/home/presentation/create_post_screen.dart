import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import 'video_trim_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({this.initialReel = false, super.key});
  final bool initialReel;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  XFile? _media;
  String? _mediaType;
  bool _posting = false;
  bool _editing = false;
  bool _asReel = false;

  @override
  void initState() {
    super.initState();
    _asReel = widget.initialReel;
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _chooseMedia(bool video) async {
    if (_editing || _posting) return;
    setState(() => _editing = true);
    try {
      final picked = video
          ? await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 5),
            )
          : await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 2400,
              maxHeight: 2400,
              imageQuality: 95,
            );
      if (picked == null || !mounted) return;

      final edited = video ? await _trimVideo(picked) : await _cropImage(picked);
      if (edited == null || !mounted) return;
      await _acceptMedia(edited, video ? 'video' : 'image');
    } catch (_) {
      _notice('انتخاب یا ویرایش رسانه انجام نشد.', error: true);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<XFile?> _cropImage(XFile file) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      maxWidth: 1920,
      maxHeight: 1920,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'برش و چرخش تصویر',
          toolbarColor: HomaGramTheme.royalPurple,
          toolbarWidgetColor: Colors.white,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: HomaGramTheme.turquoise,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'برش و چرخش تصویر',
          doneButtonTitle: 'تأیید',
          cancelButtonTitle: 'لغو',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );
    if (cropped == null) return null;
    return XFile(cropped.path, mimeType: 'image/jpeg');
  }

  Future<XFile?> _trimVideo(XFile file) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => VideoTrimScreen(file: File(file.path)),
      ),
    );
    if (path == null) return null;
    return XFile(path, mimeType: 'video/mp4');
  }

  Future<void> _acceptMedia(XFile file, String type) async {
    final name = file.name.toLowerCase();
    final mime = file.mimeType ?? '';
    final allowed = type == 'video'
        ? mime == 'video/mp4' ||
            mime == 'video/quicktime' ||
            name.endsWith('.mp4') ||
            name.endsWith('.mov')
        : mime == 'image/jpeg' ||
            mime == 'image/png' ||
            mime == 'image/webp' ||
            RegExp(r'\.(jpe?g|png|webp)$').hasMatch(name);
    if (!allowed) {
      _notice('فرمت این فایل پشتیبانی نمی‌شود.', error: true);
      return;
    }
    final size = await file.length();
    final limit = type == 'video' ? 50 * 1024 * 1024 : 15 * 1024 * 1024;
    if (size > limit) {
      _notice(
        type == 'video'
            ? 'حجم ویدئوی ویرایش‌شده باید حداکثر ۵۰ مگابایت باشد.'
            : 'حجم تصویر ویرایش‌شده باید حداکثر ۱۵ مگابایت باشد.',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _media = file;
      _mediaType = type;
      if (type != 'video') _asReel = false;
    });
  }

  Future<void> _editSelectedMedia() async {
    final current = _media;
    final type = _mediaType;
    if (current == null || type == null || _editing || _posting) return;
    setState(() => _editing = true);
    try {
      final edited = type == 'image'
          ? await _cropImage(current)
          : await _trimVideo(current);
      if (edited != null && mounted) await _acceptMedia(edited, type);
    } catch (_) {
      _notice('ویرایش رسانه انجام نشد.', error: true);
    } finally {
      if (mounted) setState(() => _editing = false);
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
    if (_asReel && (_media == null || _mediaType != 'video')) {
      _notice('برای انتشار ریلز باید یک ویدئو انتخاب کنید.', error: true);
      return;
    }
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
      final profile = await client
          .from('profiles')
          .select('username,display_name')
          .eq('id', user.id)
          .single();

      if (_media != null) {
        final mime = _media!.mimeType ?? _mimeFromName(_media!.name, _mediaType!);
        final ext = _media!.name.contains('.')
            ? _media!.name.split('.').last.toLowerCase()
            : (_mediaType == 'video' ? 'mp4' : 'jpg');
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
        'is_reel': _asReel,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StorageException catch (e) {
      await _removeUploaded(uploadedPath);
      _notice('بارگذاری رسانه انجام نشد: ${e.message}', error: true);
    } on PostgrestException catch (e) {
      await _removeUploaded(uploadedPath);
      _notice(
        e.code == '23505'
            ? 'این پست تکراری است.'
            : 'انتشار پست انجام نشد. دوباره تلاش کنید.',
        error: true,
      );
    } catch (_) {
      await _removeUploaded(uploadedPath);
      _notice('انتشار پست انجام نشد. اتصال را بررسی کنید.', error: true);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _removeUploaded(String? path) async {
    if (path == null) return;
    try {
      await AuthService.client.storage.from('post-media').remove([path]);
    } catch (_) {}
  }

  String _mimeFromName(String name, String type) {
    final ext = name.split('.').last.toLowerCase();
    if (type == 'video') return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Widget _selectedMediaCard() {
    final media = _media!;
    final isVideo = _mediaType == 'video';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isVideo
                    ? Container(
                        width: 76,
                        height: 76,
                        color: Colors.black87,
                        child: const Icon(Icons.movie_creation_outlined,
                            color: HomaGramTheme.turquoise, size: 34),
                      )
                    : Image.file(
                        File(media.path),
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 76,
                          height: 76,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isVideo ? 'ویدئوی آماده انتشار' : 'تصویر آماده انتشار',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(media.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'حذف رسانه',
                onPressed: _posting || _editing
                    ? null
                    : () => setState(() {
                          _media = null;
                          _mediaType = null;
                        }),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _posting || _editing ? null : _editSelectedMedia,
              icon: const Icon(Icons.tune_rounded),
              label: Text(isVideo ? 'تغییر بازه ویدئو' : 'برش و چرخش تصویر'),
            ),
          ),
        ],
      ),
    );
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
            if (_media != null) _selectedMediaCard(),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _asReel,
              onChanged: _mediaType == 'video' && !_posting && !_editing
                  ? (value) => setState(() => _asReel = value)
                  : null,
              secondary: const Icon(Icons.video_collection_outlined, color: HomaGramTheme.turquoise),
              title: const Text('انتشار به‌عنوان ریلز', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_asReel
                  ? 'این ویدئو در بخش ریلز نمایش داده می‌شود.'
                  : 'برای ریلز، ابتدا یک ویدئو انتخاب کنید.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
            ),
            if (!widget.initialReel)
              OutlinedButton.icon(
                onPressed: _posting || _editing ? null : () => _chooseMedia(false),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('افزودن تصویر و برش آن'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _posting || _editing ? null : () => _chooseMedia(true),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('افزودن و کوتاه‌کردن ویدئو'),
            ),
            if (_editing) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              const Text('در حال آماده‌سازی ویرایشگر...', textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            const Text(
              'ویرایش تصویر: برش آزاد، مربع، افقی و چرخش • ویدئو: انتخاب بازه حداکثر ۲ دقیقه',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF7A879B)),
            ),
            const SizedBox(height: 5),
            const Text(
              'حجم نهایی تصویر: حداکثر ۱۵ مگابایت • ویدئو: حداکثر ۵۰ مگابایت',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF7A879B)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _posting || _editing ? null : _publish,
              icon: _posting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_posting ? 'در حال انتشار...' : 'انتشار پست'),
            ),
          ],
        ),
      );
}
