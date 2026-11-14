import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';

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
  Uint8List? _coverBytes;
  bool _posting = false, _editing = false;
  bool get _isReel => _mediaType == 'video';

  @override
  void dispose() { _caption.dispose(); super.dispose(); }

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.center),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _chooseMedia(bool video) async {
    if (_editing || _posting) return;
    setState(() => _editing = true);
    try {
      final picked = video
          ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5))
          : await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
      if (picked == null || !mounted) return;
      final edited = video ? await _trimVideo(picked) : await _cropImage(picked);
      if (edited != null && mounted) await _acceptMedia(edited, video ? 'video' : 'image');
    } catch (error) {
      _notice('انتخاب رسانه انجام نشد: $error', error: true);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<XFile?> _cropImage(XFile file) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path, maxWidth: 1920, maxHeight: 1920,
      compressFormat: ImageCompressFormat.jpg, compressQuality: 88,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'تنظیم قاب تصویر', toolbarColor: HomaGramTheme.navy,
          toolbarWidgetColor: Colors.white, backgroundColor: Colors.black,
          activeControlsWidgetColor: HomaGramTheme.turquoise,
          initAspectRatio: CropAspectRatioPreset.original, lockAspectRatio: false,
          aspectRatioPresets: [CropAspectRatioPreset.original, CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2, CropAspectRatioPreset.ratio4x3, CropAspectRatioPreset.ratio16x9],
        ),
        IOSUiSettings(
          title: 'تنظیم قاب تصویر', doneButtonTitle: 'تأیید', cancelButtonTitle: 'لغو',
          aspectRatioPresets: [CropAspectRatioPreset.original, CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2, CropAspectRatioPreset.ratio4x3, CropAspectRatioPreset.ratio16x9],
        ),
      ],
    );
    return cropped == null ? null : XFile(cropped.path, mimeType: 'image/jpeg');
  }

  Future<XFile?> _trimVideo(XFile file) async {
    final path = await Navigator.of(context).push<String>(MaterialPageRoute<String>(
      builder: (_) => VideoTrimScreen(file: File(file.path)),
    ));
    return path == null ? null : XFile(path, mimeType: 'video/mp4');
  }

  Future<void> _acceptMedia(XFile file, String type) async {
    final name = file.name.toLowerCase(), mime = file.mimeType ?? '';
    final allowed = type == 'video'
        ? mime == 'video/mp4' || mime == 'video/quicktime' || name.endsWith('.mp4') || name.endsWith('.mov')
        : mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp' ||
            RegExp(r'\.(jpe?g|png|webp)$').hasMatch(name);
    if (!allowed) { _notice('فرمت این فایل پشتیبانی نمی‌شود.', error: true); return; }
    final size = await file.length();
    if (size > (type == 'video' ? 50 : 15) * 1024 * 1024) {
      _notice(type == 'video' ? 'حجم ویدئو حداکثر ۵۰ مگابایت است.' : 'حجم تصویر حداکثر ۱۵ مگابایت است.', error: true);
      return;
    }
    Uint8List? cover;
    if (type == 'video') {
      cover = await VideoThumbnail.thumbnailData(
        video: file.path, imageFormat: ImageFormat.JPEG, maxWidth: 900, quality: 88, timeMs: 1000,
      );
      if (cover == null) { _notice('ساخت پیش‌نمایش ویدئو ممکن نشد؛ دوباره انتخاب کنید.', error: true); return; }
    }
    if (mounted) setState(() { _media = file; _mediaType = type; _coverBytes = cover; });
  }

  Future<void> _editSelectedMedia() async {
    final current = _media, type = _mediaType;
    if (current == null || type == null || _editing || _posting) return;
    setState(() => _editing = true);
    try {
      final edited = type == 'image' ? await _cropImage(current) : await _trimVideo(current);
      if (edited != null && mounted) await _acceptMedia(edited, type);
    } catch (error) { _notice('ویرایش رسانه انجام نشد: $error', error: true); }
    finally { if (mounted) setState(() => _editing = false); }
  }

  Future<void> _chooseCoverFromGallery() async {
    if (!_isReel || _editing || _posting) return;
    setState(() => _editing = true);
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1800, maxHeight: 2400, imageQuality: 94);
      if (picked == null) return;
      final cropped = await _cropImage(picked);
      if (cropped == null) return;
      final bytes = await cropped.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) { _notice('حجم کاور باید کمتر از ۱۵ مگابایت باشد.', error: true); return; }
      if (mounted) setState(() => _coverBytes = bytes);
    } catch (error) { _notice('انتخاب کاور انجام نشد: $error', error: true); }
    finally { if (mounted) setState(() => _editing = false); }
  }

  Future<void> _chooseVideoFrame() async {
    final media = _media;
    if (media == null || !_isReel || _editing || _posting) return;
    setState(() => _editing = true);
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(media.path));
      await controller.initialize();
      final durationMs = controller.value.duration.inMilliseconds;
      if (durationMs <= 0 || !mounted) return;
      int selectedMs = (durationMs ~/ 10).clamp(0, durationMs), requestId = 0;
      Uint8List? preview;
      Future<void> render(int ms, StateSetter update) async {
        final token = ++requestId;
        try {
          final bytes = await VideoThumbnail.thumbnailData(
            video: media.path, imageFormat: ImageFormat.JPEG, maxWidth: 900, quality: 90, timeMs: ms,
          );
          if (bytes != null && token == requestId) update(() => preview = bytes);
        } catch (_) {}
      }
      preview = await VideoThumbnail.thumbnailData(
        video: media.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 900,
        quality: 90,
        timeMs: selectedMs,
      );
      final selected = await showModalBottomSheet<Uint8List>(
        context: context, isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (sheetContext) => StatefulBuilder(builder: (context, update) {
          return SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 42, height: 4, decoration: BoxDecoration(
                color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(9))),
              const SizedBox(height: 18),
              const Text('انتخاب فریم کاور', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(
                aspectRatio: 9 / 16,
                child: preview == null ? const Center(child: CircularProgressIndicator())
                    : Image.memory(preview!, fit: BoxFit.cover))),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.movie_outlined, size: 18),
                Expanded(child: Slider(
                  value: selectedMs.toDouble(), min: 0, max: durationMs.toDouble(),
                  onChanged: (value) { selectedMs = value.round(); update(() {}); render(selectedMs, update); },
                )),
                Text('${(selectedMs / 1000).toStringAsFixed(1)}s', style: const TextStyle(fontSize: 11)),
              ]),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: preview == null ? null : () => Navigator.pop(sheetContext, preview),
                child: const Text('انتخاب این فریم'))),
            ]),
          ));
        }),
      );
      requestId++;
      if (selected != null && mounted) setState(() => _coverBytes = selected);
    } catch (error) { _notice('استخراج فریم انجام نشد: $error', error: true); }
    finally {
      await controller?.dispose();
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _publish() async {
    final caption = _caption.text.trim();
    if (_isReel && _coverBytes == null) { _notice('برای ریلز یک کاور انتخاب کنید.', error: true); return; }
    if (caption.isEmpty && _media == null) { _notice('برای انتشار، متن یا رسانه اضافه کنید.', error: true); return; }
    if (caption.length > 2200) { _notice('متن پست حداکثر ۲۲۰۰ نویسه است.', error: true); return; }
    setState(() => _posting = true);
    String? uploadedPath, uploadedCoverPath;
    try {
      final client = AuthService.client, user = AuthService.client.auth.currentUser;
      if (user == null) throw StateError('نشست کاربری معتبر نیست؛ دوباره وارد شوید.');
      final profile = await client.from('profiles').select('username,display_name').eq('id', user.id).maybeSingle();
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final emailPrefix = user.email?.split('@').first;
      final username = (profile?['username'] as String?)?.trim().isNotEmpty == true
          ? (profile!['username'] as String).trim()
          : (metadata['username'] as String?)?.trim().isNotEmpty == true
              ? (metadata['username'] as String).trim()
              : (emailPrefix?.trim().isNotEmpty == true ? emailPrefix!.trim() : 'user_${user.id.substring(0, 8)}');
      final displayName = (profile?['display_name'] as String?)?.trim().isNotEmpty == true
          ? (profile!['display_name'] as String).trim()
          : (metadata['full_name'] as String?)?.trim().isNotEmpty == true
              ? (metadata['full_name'] as String).trim()
              : username;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      if (_media != null) {
        final mime = _media!.mimeType ?? _mimeFromName(_media!.name, _mediaType!);
        final ext = _media!.name.contains('.') ? _media!.name.split('.').last.toLowerCase() : (_isReel ? 'mp4' : 'jpg');
        uploadedPath = '${user.id}/$stamp.$ext';
        await client.storage.from('post-media').uploadBinary(uploadedPath, await _media!.readAsBytes(),
          fileOptions: FileOptions(contentType: mime, upsert: false));
      }
      if (_isReel && _coverBytes != null) {
        uploadedCoverPath = '${user.id}/${stamp}_cover.jpg';
        await client.storage.from('post-media').uploadBinary(uploadedCoverPath, _coverBytes!,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      }
      await client.from('posts').insert({
        'author_id': user.id, 'author_username': username,
        'author_display_name': displayName, 'caption': caption,
        'media_path': uploadedPath, 'media_type': uploadedPath == null ? null : _mediaType,
        'is_reel': _isReel, 'cover_path': uploadedCoverPath,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on StorageException catch (error) {
      await _removeUploaded(uploadedPath); await _removeUploaded(uploadedCoverPath);
      _notice('بارگذاری فایل انجام نشد: ${error.message}', error: true);
    } on PostgrestException catch (error) {
      await _removeUploaded(uploadedPath); await _removeUploaded(uploadedCoverPath);
      final detail = [error.message, if (error.code != null) 'کد: ${error.code}',
        if (error.details != null) error.details.toString()].join(' • ');
      _notice('ثبت محتوا انجام نشد: $detail', error: true);
    } catch (error) {
      await _removeUploaded(uploadedPath); await _removeUploaded(uploadedCoverPath);
      _notice('انتشار انجام نشد: $error', error: true);
    } finally { if (mounted) setState(() => _posting = false); }
  }

  Future<void> _removeUploaded(String? path) async {
    if (path == null) return;
    try { await AuthService.client.storage.from('post-media').remove([path]); } catch (_) {}
  }

  String _mimeFromName(String name, String type) {
    final ext = name.split('.').last.toLowerCase();
    if (type == 'video') return ext == 'mov' ? 'video/quicktime' : 'video/mp4';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Widget _mediaPreview() {
    final isVideo = _isReel;
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(aspectRatio: isVideo ? 9 / 13 : 4 / 5, child: Stack(fit: StackFit.expand, children: [
          if (isVideo && _coverBytes != null) Image.memory(_coverBytes!, fit: BoxFit.cover)
          else if (!isVideo) Image.file(File(_media!.path), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
          if (isVideo) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 58)),
          Positioned(right: 12, top: 12, child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .58), borderRadius: BorderRadius.circular(20)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Text(isVideo ? 'REEL' : 'POST', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))))),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 8, 10), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isVideo ? 'کاور ریلز آماده است' : 'تصویر آماده انتشار', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_media!.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
          ])),
          IconButton(onPressed: _posting || _editing ? null : _editSelectedMedia, icon: const Icon(Icons.tune_rounded)),
          IconButton(onPressed: _posting || _editing ? null : () => setState(() {
            _media = null; _mediaType = null; _coverBytes = null;
          }), icon: const Icon(Icons.close_rounded)),
        ])),
        if (isVideo) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _posting || _editing ? null : _chooseVideoFrame,
            icon: const Icon(Icons.video_camera_back_outlined, size: 18), label: const Text('انتخاب فریم'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: _posting || _editing ? null : _chooseCoverFromGallery,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: const Text('کاور از گالری'))),
        ])),
      ]),
    );
  }

  Widget _pickerTile({required IconData icon, required String title, required String subtitle,
    required VoidCallback onTap, required Color accent}) => InkWell(
    onTap: _editing || _posting ? null : onTap, borderRadius: BorderRadius.circular(20),
    child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .18))),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: accent, size: 25)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
        ])),
        const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFF8490A4)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text((widget.initialReel || _isReel) ? 'ساخت ریلز' : 'ایجاد پست',
        style: const TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
          gradient: LinearGradient(colors: [HomaGramTheme.navy, HomaGramTheme.royalPurple.withValues(alpha: .94)],
            begin: Alignment.topRight, end: Alignment.bottomLeft), borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30), const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('لحظه‌ات را به اشتراک بگذار',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text((widget.initialReel || _isReel) ? 'ویدئو به‌صورت خودکار به ریلز تبدیل می‌شود.'
                : 'متن یا تصویر منتشر کن؛ انتخاب ویدئو یعنی ساخت ریلز.',
                style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.6)),
            ])),
          ])),
        const SizedBox(height: 20),
        if (_media == null) ...[
          const Text('نوع محتوا را انتخاب کن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 11),
          if (!widget.initialReel) ...[
            _pickerTile(icon: Icons.photo_library_outlined, title: 'انتشار تصویر',
              subtitle: 'یک تصویر انتخاب و قاب آن را تنظیم کن',
              onTap: () => _chooseMedia(false), accent: HomaGramTheme.turquoise),
            const SizedBox(height: 10),
          ],
          _pickerTile(icon: Icons.movie_creation_outlined, title: 'ساخت ریلز',
            subtitle: 'ویدئو را انتخاب کن، کوتاه کن و کاور بساز',
            onTap: () => _chooseMedia(true), accent: HomaGramTheme.royalPurple),
          if (!widget.initialReel) ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(18)),
              child: const Row(children: [
                Icon(Icons.text_fields_rounded, color: HomaGramTheme.turquoise), SizedBox(width: 10),
                Expanded(child: Text('برای انتشار پست متنی، کافی است پایین همین صفحه کپشن بنویسی.',
                  style: TextStyle(fontSize: 11, height: 1.7))),
              ])),
          ],
        ] else _mediaPreview(),
        const SizedBox(height: 22),
        const Text('کپشن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 9),
        TextField(controller: _caption, maxLength: 2200, minLines: 4, maxLines: 8,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(hintText: 'داستان این تصویر یا ویدئو را بنویس...',
            filled: true, fillColor: colors.surfaceContainerHighest.withValues(alpha: .42),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            alignLabelWithHint: true)),
        if (_editing) ...[
          const SizedBox(height: 12), const LinearProgressIndicator(), const SizedBox(height: 7),
          const Text('در حال آماده‌سازی رسانه...', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF8490A4))),
        ],
        const SizedBox(height: 10),
        const Text('ویدئو همیشه به‌عنوان ریلز منتشر می‌شود. پست متنی و تصویری در فید نمایش داده می‌شود.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4))),
        const SizedBox(height: 18),
        SizedBox(height: 54, child: FilledButton.icon(
          onPressed: _posting || _editing ? null : _publish,
          icon: _posting ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.publish_rounded),
          label: Text(_posting ? 'در حال انتشار...' : _isReel ? 'انتشار ریلز' : 'انتشار پست',
            style: const TextStyle(fontWeight: FontWeight.w900)),
          style: FilledButton.styleFrom(backgroundColor: _isReel ? HomaGramTheme.royalPurple : HomaGramTheme.turquoise,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
        )),
      ]),
    );
  }
}
