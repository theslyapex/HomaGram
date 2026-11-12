import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../../../app/theme/app_theme.dart';

class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({required this.file, super.key});

  final File file;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0;
  double _endValue = 0;
  bool _loading = true;
  bool _saving = false;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _trimmer.loadVideo(videoFile: widget.file);
      final duration = _trimmer.videoPlayerController?.value.duration;
      if (duration == null || duration.inMilliseconds <= 0) {
        throw Exception('Video duration unavailable');
      }
      if (!mounted) return;
      setState(() {
        _endValue = duration.inMilliseconds.toDouble();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'این ویدئو قابل ویرایش نیست.';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    setState(() => _saving = true);
    try {
      String? outputPath;
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (path) => outputPath = path,
      );
      if (outputPath == null || !await File(outputPath!).exists()) {
        throw Exception('Trim export failed');
      }
      if (!mounted) return;
      Navigator.of(context).pop(outputPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برش و ذخیره ویدئو انجام نشد. دوباره تلاش کنید.')),
      );
    }
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 32;
    return Scaffold(
      appBar: AppBar(title: const Text('ویرایش ویدئو')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
                        child: Text(
                          'با جابه‌جایی دو دستگیره، بخش دلخواه ویدئو را انتخاب کنید.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8490A4), height: 1.8),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: VideoViewer(trimmer: _trimmer),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
                        child: TrimViewer(
                          trimmer: _trimmer,
                          viewerHeight: 58,
                          viewerWidth: width,
                          maxVideoLength: const Duration(seconds: 120),
                          onChangeStart: (value) => _startValue = value,
                          onChangeEnd: (value) => _endValue = value,
                          onChangePlaybackState: (value) {
                            if (mounted) setState(() => _playing = value);
                          },
                        ),
                      ),
                      Text(
                        'بازه انتخابی حداکثر ۲ دقیقه است.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF8490A4),
                            ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _saving
                            ? null
                            : () async {
                                final state = await _trimmer.videoPlaybackControl(
                                  startValue: _startValue,
                                  endValue: _endValue,
                                );
                                if (mounted) setState(() => _playing = state);
                              },
                        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        iconSize: 30,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(_saving ? 'در حال آماده‌سازی...' : 'تأیید برش ویدئو'),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
