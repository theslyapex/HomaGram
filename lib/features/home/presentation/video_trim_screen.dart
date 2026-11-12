import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

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
  double _durationSeconds = 0;
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
        _durationSeconds = duration.inMilliseconds / 1000;
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

  String _formatTime(double milliseconds) {
    final totalSeconds = (milliseconds / 1000).floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _changeRange(RangeValues values) {
    final maxLength = 120.0;
    var start = values.start;
    var end = values.end;

    // Keep the selected segment at or below two minutes while dragging
    // either handle, including on videos longer than two minutes.
    if (end - start > maxLength) {
      if (start != _startValue / 1000) {
        end = (start + maxLength).clamp(0.0, _durationSeconds);
        start = end - maxLength;
      } else {
        start = (end - maxLength).clamp(0.0, _durationSeconds);
        end = start + maxLength;
      }
    }

    setState(() {
      _startValue = start * 1000;
      _endValue = end * 1000;
    });
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ویرایش ویدئو')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final previewHeight =
                          (constraints.maxHeight * 0.39).clamp(210.0, 330.0);
                      return Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
                            child: Text(
                              'دو دستگیره را جابه‌جا کنید تا ابتدا و انتهای بخش دلخواه ویدئو مشخص شود.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8490A4),
                                height: 1.7,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: previewHeight,
                            width: double.infinity,
                            child: ColoredBox(
                              color: Colors.black,
                              child: Center(child: VideoViewer(trimmer: _trimmer)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatTime(_startValue),
                                        textDirection: TextDirection.ltr,
                                        style: theme.textTheme.labelLarge,
                                      ),
                                      Text(
                                        'انتخاب بازه ویدئو',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      Text(
                                        _formatTime(_endValue),
                                        textDirection: TextDirection.ltr,
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ],
                                  ),
                                  Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: RangeSlider(
                                      min: 0,
                                      max: _durationSeconds,
                                      divisions: _durationSeconds.floor() > 1
                                          ? _durationSeconds.floor()
                                          : null,
                                      values: RangeValues(
                                        (_startValue / 1000).clamp(
                                          0.0,
                                          _durationSeconds,
                                        ).toDouble(),
                                        (_endValue / 1000).clamp(
                                          0.0,
                                          _durationSeconds,
                                        ).toDouble(),
                                      ),
                                      labels: RangeLabels(
                                        _formatTime(_startValue),
                                        _formatTime(_endValue),
                                      ),
                                      onChanged: _saving ? null : _changeRange,
                                    ),
                                  ),
                                  Text(
                                    'مدت انتخاب‌شده: ${_formatTime(_endValue - _startValue)}  •  حداکثر ۰۲:۰۰ دقیقه',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
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
                            icon: Icon(
                              _playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            iconSize: 30,
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded),
                                label: Text(
                                  _saving
                                      ? 'در حال آماده‌سازی...'
                                      : 'تأیید برش ویدئو',
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}
