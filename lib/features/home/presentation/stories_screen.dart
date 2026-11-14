import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme/app_theme.dart';
import '../../auth/data/auth_service.dart';
import '../data/story_service.dart';
import 'story_image.dart';
import 'explore_screen.dart';
import 'public_profile_screen.dart';
import '../../../core/cache/story_video_cache.dart';
import '../../../core/utils/persian_date.dart';

const Map<String, List<Color>> storyTextGradients = {
  'aurora': [Color(0xFF173A70), Color(0xFF8056B8), Color(0xFFDA6F9D)],
  'sunset': [Color(0xFF8E3158), Color(0xFFE0784E), Color(0xFFF3B65B)],
  'ocean': [Color(0xFF063B55), Color(0xFF087E8B), Color(0xFF4CC9B0)],
  'forest': [Color(0xFF123B32), Color(0xFF28745A), Color(0xFF9AAE62)],
  'midnight': [Color(0xFF111827), Color(0xFF263B63), Color(0xFF485A86)],
  'rose': [Color(0xFF672D54), Color(0xFFB44C79), Color(0xFFE6A0A8)],
};

LinearGradient storyTextGradient(String? key) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: storyTextGradients[key] ?? storyTextGradients['aurora']!,
);

class StoryTextStoryView extends StatelessWidget {
  const StoryTextStoryView({
    required this.text,
    required this.backgroundKey,
    this.compact = false,
    super.key,
  });

  final String text;
  final String? backgroundKey;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: storyTextGradient(backgroundKey)),
    alignment: Alignment.center,
    padding: EdgeInsets.all(compact ? 8 : 34),
    child: StoryInteractiveText(
      text: text,
      textAlign: TextAlign.center,
      maxLines: compact ? 5 : 18,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 10 : 28,
        height: 1.55,
        fontWeight: FontWeight.w700,
        shadows: const [Shadow(color: Colors.black26, blurRadius: 10)],
      ),
    ),
  );
}

class StoryInteractiveText extends StatelessWidget {
  const StoryInteractiveText({
    required this.text,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  Future<void> _openMention(BuildContext context, String username) async {
    try {
      final user = await StoryService.findUserByUsername(username);
      if (!context.mounted || user == null) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(userId: user['id'] as String),
      ));
    } catch (_) {}
  }

  Future<void> _openLink(BuildContext context, String raw) async {
    final cleaned = raw.replaceFirst(RegExp(r'[.,!?،؛:]+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('بازکردن لینک ممکن نشد.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('بازکردن لینک ممکن نشد.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pattern = RegExp(
      r'https?://[^\s<>()]+|@[a-zA-Z0-9_]{3,24}|#[\p{L}\p{N}_]{2,}',
      unicode: true,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start)));
      final token = match.group(0)!;
      final isLink = token.startsWith('http://') || token.startsWith('https://');
      final isMention = token.startsWith('@');
      final tokenStyle = style.copyWith(
        color: isLink ? const Color(0xFF8DE4FF) : const Color(0xFF83F0D4),
        fontWeight: FontWeight.w900,
        decoration: isLink ? TextDecoration.underline : TextDecoration.none,
      );
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isLink) {
              _openLink(context, token);
            } else if (isMention) {
              _openMention(context, token.substring(1));
            } else {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ExploreScreen(initialQuery: token),
              ));
            }
          },
          child: Text(token, style: tokenStyle),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}



String? _storyOverlayFont(String? value) {
  switch (value) {
    case 'serif': return 'serif';
    case 'mono': return 'monospace';
    default: return null;
  }
}

Color storyOverlayColor(String? value) {
  const colors = {
    '#FFFFFF': Color(0xFFFFFFFF),
    '#111827': Color(0xFF111827),
    '#FFE082': Color(0xFFFFE082),
    '#FF6B6B': Color(0xFFFF6B6B),
    '#45D6C5': Color(0xFF45D6C5),
    '#A78BFA': Color(0xFFA78BFA),
    '#F9A8D4': Color(0xFFF9A8D4),
  };
  return colors[value] ?? Colors.white;
}


class _StoryDrawingPainter extends CustomPainter {
  const _StoryDrawingPainter(this.strokes);
  final List<dynamic> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final raw in strokes) {
      if (raw is! Map || raw['points'] is! List) continue;
      final points = <Offset>[];
      for (final point in raw['points'] as List) {
        if (point is List && point.length == 2 && point[0] is num && point[1] is num) {
          points.add(Offset((point[0] as num).toDouble() * size.width, (point[1] as num).toDouble() * size.height));
        }
      }
      if (points.isEmpty) continue;
      final erase = raw['erase'] == true;
      final color = storyOverlayColor(raw['color'] as String?);
      final width = ((raw['width'] as num?)?.toDouble() ?? 4).clamp(1.0, 24.0);
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver;
      if (points.length == 1) {
        canvas.drawCircle(points.first, width / 2, Paint()..color = color..blendMode = erase ? BlendMode.clear : BlendMode.srcOver);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _StoryDrawingPainter oldDelegate) => oldDelegate.strokes != strokes;
}

class _StoryDrawingView extends StatelessWidget {
  const _StoryDrawingView({required this.story});
  final Map<String, dynamic> story;
  @override
  Widget build(BuildContext context) {
    final raw = story['drawing_data'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _StoryDrawingPainter(raw))));
  }
}

class _StoryStickerView extends StatelessWidget {
  const _StoryStickerView({required this.story});
  final Map<String, dynamic> story;

  @override
  Widget build(BuildContext context) {
    final raw = story['sticker_data'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final stickers = raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    return Positioned.fill(
      child: IgnorePointer(child: _StoryStickerLayer(stickers: stickers)),
    );
  }
}

class _TransformableStoryElement extends StatefulWidget {
  const _TransformableStoryElement({
    required this.layout, required this.child, this.editing = false,
    this.selected = false, this.onChanged,
  });
  final Map<String, double> layout;
  final Widget child;
  final bool editing;
  final bool selected;
  final ValueChanged<Map<String, double>>? onChanged;
  @override
  State<_TransformableStoryElement> createState() => _TransformableStoryElementState();
}

class _TransformableStoryElementState extends State<_TransformableStoryElement> {
  late double _startScale;
  late double _startRotation;
  @override
  void initState() {
    super.initState();
    _startScale = widget.layout['scale'] ?? 1;
    _startRotation = widget.layout['rotation'] ?? 0;
  }
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final x = (widget.layout['x'] ?? .5).clamp(.03, .97).toDouble();
        final y = (widget.layout['y'] ?? .5).clamp(.05, .95).toDouble();
        final scale = (widget.layout['scale'] ?? 1).clamp(.55, 2.2).toDouble();
        final rotation = (widget.layout['rotation'] ?? 0).clamp(-3.14, 3.14).toDouble();
        Widget element = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size.width * .82, maxHeight: size.height * .58),
          child: widget.child,
        );
        if (widget.editing) {
          element = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (_) { _startScale = scale; _startRotation = rotation; },
            onScaleUpdate: (details) => widget.onChanged?.call({
              'x': (x + details.focalPointDelta.dx / size.width).clamp(.03, .97).toDouble(),
              'y': (y + details.focalPointDelta.dy / size.height).clamp(.05, .95).toDouble(),
              'scale': (_startScale * details.scale).clamp(.55, 2.2).toDouble(),
              'rotation': (_startRotation + details.rotation).clamp(-3.14, 3.14).toDouble(),
            }),
            child: element,
          );
        }
        if (widget.editing && widget.selected) {
          element = DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF62E5D0), width: 1.5), borderRadius: BorderRadius.circular(20)),
            child: Padding(padding: const EdgeInsets.all(3), child: element),
          );
        }
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: x * size.width, top: y * size.height,
            child: FractionalTranslation(
              translation: const Offset(-.5, -.5),
              child: Transform.rotate(angle: rotation,
                child: Transform.scale(scale: scale, alignment: Alignment.center, child: element)),
            ),
          ),
        ]);
      },
    ),
  );
}

class _StoryCountdownCard extends StatefulWidget {
  const _StoryCountdownCard({required this.countdown});
  final Map<String, dynamic> countdown;

  @override
  State<_StoryCountdownCard> createState() => _StoryCountdownCardState();
}

class _StoryCountdownCardState extends State<_StoryCountdownCard> {
  Timer? _ticker;
  DateTime? _target;

  @override
  void initState() {
    super.initState();
    _target = DateTime.tryParse(widget.countdown['target_at']?.toString() ?? '')?.toLocal();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _StoryCountdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countdown['target_at'] != widget.countdown['target_at']) {
      _target = DateTime.tryParse(widget.countdown['target_at']?.toString() ?? '')?.toLocal();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final remaining = target == null ? Duration.zero : target.difference(DateTime.now());
    final completed = target == null || remaining <= Duration.zero;
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    Widget unit(String value, String label) => Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    );

    return Material(
      color: const Color(0xE9161D2B),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.timer_rounded, color: Color(0xFF62E5D0), size: 18),
            const SizedBox(width: 7),
            Flexible(child: Text(
              widget.countdown['title'] as String? ?? 'شمارش معکوس',
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
            )),
          ]),
          const SizedBox(height: 9),
          if (completed)
            const Text('زمانش فرا رسیده!', style: TextStyle(color: Color(0xFF62E5D0), fontWeight: FontWeight.w900))
          else
            Row(children: [
              if (days > 0) unit('$days', 'روز'),
              unit(_two(hours), 'ساعت'),
              unit(_two(minutes), 'دقیقه'),
              unit(_two(seconds), 'ثانیه'),
            ]),
        ]),
      ),
    );
  }
}

class _StoryQuestionBoxCard extends StatelessWidget {
  const _StoryQuestionBoxCard({required this.question, required this.isOwner, this.onRespond, this.onViewResponses, this.busy = false});
  final Map<String, dynamic> question;
  final bool isOwner;
  final VoidCallback? onRespond;
  final VoidCallback? onViewResponses;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final count = (question['response_count'] as num?)?.toInt() ?? 0;
    return Material(
      color: const Color(0xE9161D2B), borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.question_answer_rounded, color: Color(0xFF62E5D0), size: 22),
          const SizedBox(height: 5),
          Text(question['prompt'] as String? ?? 'باکس پرسش', textAlign: TextAlign.center, maxLines: 3,
            overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton(
            onPressed: busy ? null : (isOwner ? onViewResponses : onRespond),
            child: Text(isOwner ? 'مشاهده پاسخ‌ها • $count' : 'نوشتن پاسخ'),
          )),
        ]),
      ),
    );
  }
}

class _StoryPollCard extends StatelessWidget {
  const _StoryPollCard({
    required this.poll,
    required this.isOwner,
    this.onVote,
    this.busy = false,
  });

  final Map<String, dynamic> poll;
  final bool isOwner;
  final ValueChanged<int>? onVote;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final options = (poll['options'] as List? ?? const [])
        .map((value) => value.toString()).toList();
    final counts = (poll['counts'] as List? ?? const [])
        .map((value) => value is num ? value.toInt() : 0).toList();
    final total = (poll['total_votes'] as num?)?.toInt() ??
        counts.fold<int>(0, (sum, value) => sum + value);
    final selected = (poll['my_option'] as num?)?.toInt();
    final showResults = isOwner || selected != null;

    if (options.length < 2 || options.length > 4) return const SizedBox.shrink();

    return Material(
      color: const Color(0xE9161D2B),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              poll['question'] as String? ?? 'نظرسنجی',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(height: 7),
              _buildOption(
                context,
                options[i],
                i,
                counts.length > i ? counts[i] : 0,
                total,
                selected,
                showResults,
              ),
            ],
            if (showResults) ...[
              const SizedBox(height: 8),
              Text(
                '$total رأی',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'برای ثبت رأی یکی از گزینه‌ها را انتخاب کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    String label,
    int index,
    int count,
    int total,
    int? selected,
    bool showResults,
  ) {
    final percent = total == 0 ? 0 : ((count / total) * 100).round();
    final direction = Directionality.of(context);
    final canVote = !isOwner && onVote != null && !busy;

    return Material(
      color: Colors.white.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: canVote ? () => onVote!(index) : null,
        child: SizedBox(
          height: 42,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                if (showResults && percent > 0)
                  Align(
                    alignment: direction == TextDirection.rtl
                        ? Alignment.centerRight : Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (percent / 100).clamp(0.0, 1.0).toDouble(),
                      child: Container(color: const Color(0xFF21B8A6).withValues(alpha: .42)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      if (selected == index)
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF62E5D0), size: 17)
                      else if (canVote)
                        const Icon(Icons.circle_outlined, color: Colors.white54, size: 17),
                      if (selected == index || canVote) const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (showResults)
                        Text(
                          '$percent%',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryOverlayTextView extends StatelessWidget {
  const _StoryOverlayTextView({required this.story});

  final Map<String, dynamic> story;

  @override
  Widget build(BuildContext context) {
    final text = (story['overlay_text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final allLayout = story['widget_layout'];
    final rawLayout = allLayout is Map ? allLayout['text'] : null;
    final layout = rawLayout is Map ? rawLayout : const <String, dynamic>{};
    final x = ((layout['x'] as num?)?.toDouble() ?? (story['overlay_x'] as num?)?.toDouble() ?? .5).clamp(.03, .97);
    final y = ((layout['y'] as num?)?.toDouble() ?? (story['overlay_y'] as num?)?.toDouble() ?? .5).clamp(.05, .95);
    final scale = ((layout['scale'] as num?)?.toDouble() ?? (story['overlay_scale'] as num?)?.toDouble() ?? 1).clamp(.55, 2.5);
    final rotation = ((layout['rotation'] as num?)?.toDouble() ?? 0).clamp(-3.14, 3.14);
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, constraints) => Stack(children: [
        Positioned(
          left: x * constraints.maxWidth, top: y * constraints.maxHeight,
          child: FractionalTranslation(
            translation: const Offset(-.5, -.5),
            child: Transform.rotate(angle: rotation,
              child: Transform.scale(scale: scale, child: Container(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * .82),
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: StoryInteractiveText(
                  text: text, textAlign: TextAlign.center, maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: storyOverlayColor(story['overlay_color'] as String?),
                    fontSize: 24, fontFamily: _storyOverlayFont(story['overlay_font'] as String?),
                    height: 1.35, fontWeight: FontWeight.w800,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              )),
            ),
          ),
        ),
      ])),
    );
  }
}


class _StoryStickerLayer extends StatelessWidget {
  const _StoryStickerLayer({
    required this.stickers,
    this.onChanged,
    this.interactive = false,
  });

  final List<Map<String, dynamic>> stickers;
  final ValueChanged<List<Map<String, dynamic>>>? onChanged;
  final bool interactive;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < stickers.length; i++)
          _buildSticker(i, constraints.biggest),
      ],
    ),
  );

  Widget _buildSticker(int index, Size size) {
    final sticker = stickers[index];
    final emoji = sticker['emoji'] as String? ?? '⭐';
    final x = ((sticker['x'] as num?)?.toDouble() ?? .5).clamp(.05, .95).toDouble();
    final y = ((sticker['y'] as num?)?.toDouble() ?? .5).clamp(.05, .95).toDouble();
    final scale = ((sticker['scale'] as num?)?.toDouble() ?? 1).clamp(.5, 3).toDouble();
    final rotation = (sticker['rotation'] as num?)?.toDouble() ?? 0;
    var startScale = scale;
    var startRotation = rotation;

    final isImage = sticker['type'] == 'image';
    final localPath = sticker['local_path'] as String?;
    final signedUrl = sticker['signed_url'] as String?;
    Widget stickerContent;
    if (isImage && localPath != null) {
      stickerContent = Image.file(
        File(localPath), width: 76, height: 76, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 42),
      );
    } else if (isImage && signedUrl != null) {
      stickerContent = Image.network(
        signedUrl, width: 76, height: 76, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 42, color: Colors.white),
      );
    } else if (isImage) {
      stickerContent = const Icon(Icons.image_not_supported_outlined, size: 42, color: Colors.white);
    } else {
      stickerContent = Text(emoji, style: const TextStyle(fontSize: 48, height: 1.1));
    }
    Widget child = Transform.rotate(
      angle: rotation,
      child: Transform.scale(scale: scale, child: stickerContent),
    );

    if (interactive && onChanged != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (_) {
          startScale = scale;
          startRotation = rotation;
        },
        onScaleUpdate: (details) {
          final next = stickers.map((item) => Map<String, dynamic>.from(item)).toList();
          next[index]['x'] = (x + details.focalPointDelta.dx / size.width).clamp(.05, .95);
          next[index]['y'] = (y + details.focalPointDelta.dy / size.height).clamp(.05, .95);
          next[index]['scale'] = (startScale * details.scale).clamp(.5, 3);
          next[index]['rotation'] = (startRotation + details.rotation).clamp(-3.14, 3.14);
          onChanged!(next);
        },
        onLongPress: () {
          final next = stickers.map((item) => Map<String, dynamic>.from(item)).toList();
          next.removeAt(index);
          onChanged!(next);
        },
        child: child,
      );
    }

    return Positioned(
      left: x * size.width - 30,
      top: y * size.height - 30,
      child: IgnorePointer(ignoring: !interactive, child: child),
    );
  }
}

class StoriesStrip extends StatefulWidget {
  const StoriesStrip({super.key});

  @override
  State<StoriesStrip> createState() => _StoriesStripState();
}

class _StoriesStripState extends State<StoriesStrip> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = StoryService.loadActiveStories();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final next = StoryService.loadActiveStories();
    setState(() => _future = next);
    await next;
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateStoryScreen()),
    );
    if (created == true && mounted) await _refresh();
  }

  Future<void> _archive() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StoryArchiveScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _future,
    builder: (context, snapshot) {
      final stories = snapshot.data ?? [];
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final story in stories) {
        (groups[story['author_id'] as String] ??= []).add(story);
      }
      // Keep each user's stories in chronological order (oldest first),
      // so the viewer advances through that user's story sequence naturally.
      for (final items in groups.values) {
        items.sort((a, b) {
          final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return aTime.compareTo(bTime);
        });
      }

      final uid = AuthService.client.auth.currentUser?.id;
      final own = uid == null ? null : groups.remove(uid);

      // Unseen story groups appear first; within each group, the newest
      // activity determines its position. Viewed groups follow afterward.
      final ordered = groups.entries.toList()
        ..sort((a, b) {
          final aViewed = a.value.every((story) => story['is_viewed'] == true);
          final bViewed = b.value.every((story) => story['is_viewed'] == true);
          if (aViewed != bViewed) return aViewed ? 1 : -1;

          final aLatest = DateTime.tryParse(
                a.value.last['created_at']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final bLatest = DateTime.tryParse(
                b.value.last['created_at']?.toString() ?? '',
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          return bLatest.compareTo(aLatest);
        });
      return Container(
        height: 132,
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(
                children: [
                  const Text('استوری‌ها', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const Spacer(),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  TextButton(
                    onPressed: _archive,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('آرشیو', style: TextStyle(fontSize: 11)),
                  ),
                  IconButton(
                    tooltip: 'تازه‌سازی استوری‌ها',
                    visualDensity: VisualDensity.compact,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                children: [
                  _StoryAvatar(
                    title: own == null ? 'استوری شما' : 'استوری من',
                    imageUrl: own?.last['avatar_url'] as String?,
                    imageCacheKey: own?.last['avatar_path'] as String?,
                    hasStory: own != null,
                    viewed: own != null && own.every((s) => s['is_viewed'] == true),
                    add: own == null,
                    onTap: own == null ? _create : () => _open(own),
                  ),
                  ...ordered.map((entry) => _StoryAvatar(
                    title: entry.value.first['display_name'] as String,
                    imageUrl: entry.value.first['avatar_url'] as String?,
                    imageCacheKey: entry.value.first['avatar_path'] as String?,
                    hasStory: true,
                    viewed: entry.value.every((s) => s['is_viewed'] == true),
                    onTap: () => _open(entry.value),
                  )),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  void _open(List<Map<String, dynamic>> items) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerScreen(stories: items),
    )).then((_) => _refresh());
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.title,
    required this.imageUrl,
    this.imageCacheKey,
    required this.hasStory,
    required this.viewed,
    required this.onTap,
    this.add = false,
  });

  final String title;
  final String? imageUrl;
  final String? imageCacheKey;
  final bool hasStory;
  final bool viewed;
  final bool add;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasStory && !viewed
                  ? const LinearGradient(colors: [Color(0xFF20B8B0), Color(0xFF7356C8), Color(0xFFE35D9A)])
                  : null,
              border: hasStory && viewed ? Border.all(color: Colors.grey, width: 2) : null,
            ),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .14),
              backgroundImage: imageUrl == null ? null : StoryImageProvider(imageUrl!, cacheKey: 'avatar:${imageCacheKey ?? imageUrl!}'),
              child: imageUrl == null
                  ? const Icon(Icons.person_outline_rounded, color: HomaGramTheme.turquoise)
                  : null,
            ),
          ),
          const SizedBox(height: 5),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          if (add)
            const Text('افزودن', style: TextStyle(fontSize: 9, color: HomaGramTheme.turquoise)),
        ],
      ),
    ),
  );
}

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  final _overlayText = TextEditingController();
  final _pollQuestion = TextEditingController();
  final List<TextEditingController> _pollOptions = [
    TextEditingController(), TextEditingController(),
  ];
  bool _pollEnabled = false;
  final _questionBoxPrompt = TextEditingController();
  bool _questionBoxEnabled = false;
  final _countdownTitle = TextEditingController();
  bool _countdownEnabled = false;
  DateTime _countdownTarget = DateTime.now().add(const Duration(days: 1));
  XFile? _file;
  String? _type;
  bool _textMode = false;
  String _audience = 'everyone';
  String _backgroundKey = 'aurora';
  double _overlayX = 0.5;
  double _overlayY = 0.5;
  double _overlayScale = 1.0;
  String _overlayColor = '#FFFFFF';
  String _overlayFont = 'estedad';
  final List<Map<String, dynamic>> _drawingStrokes = [];
  final List<Map<String, dynamic>> _stickers = [];
  final Map<String, Map<String, double>> _widgetLayout = {
    'text': {'x': .5, 'y': .5, 'scale': 1, 'rotation': 0},
    'poll': {'x': .5, 'y': .58, 'scale': 1, 'rotation': 0},
    'question': {'x': .5, 'y': .76, 'scale': 1, 'rotation': 0},
    'countdown': {'x': .5, 'y': .38, 'scale': 1, 'rotation': 0},
  };
  String? _selectedWidget;
  File? _musicFile;
  String? _musicFileName;
  String? _musicMimeType;
  VideoPlayerController? _musicPreview;
  Duration _musicDuration = Duration.zero;
  int _musicStartMs = 0;
  double _musicVolume = 0.75;
  bool _drawingMode = false;
  bool _eraserMode = false;
  String _drawingColor = '#FFFFFF';
  double _drawingWidth = 5;
  bool _busy = false;
  Timer? _mentionTimer;
  TextEditingController? _mentionTargetController;
  List<Map<String, dynamic>> _mentionSuggestions = [];
  int _mentionStart = 0;
  String _mentionQuery = '';

  @override
  void dispose() {
    _mentionTimer?.cancel();
    _caption.dispose();
    _overlayText.dispose();
    _pollQuestion.dispose();
    _questionBoxPrompt.dispose();
    _countdownTitle.dispose();
    for (final option in _pollOptions) { option.dispose(); }
    _musicPreview?.dispose();
    super.dispose();
  }

  void _updateMentionSuggestions(TextEditingController controller) {
    _mentionTimer?.cancel();
    final caret = controller.selection.baseOffset;
    if (caret < 0 || caret > controller.text.length) {
      setState(() { _mentionTargetController = null; _mentionSuggestions = []; });
      return;
    }
    final beforeCaret = controller.text.substring(0, caret);
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]{1,24})$').firstMatch(beforeCaret);
    if (match == null) {
      if (_mentionTargetController != null || _mentionSuggestions.isNotEmpty) {
        setState(() { _mentionTargetController = null; _mentionSuggestions = []; _mentionQuery = ''; });
      }
      return;
    }
    final query = match.group(1)!;
    _mentionTargetController = controller;
    _mentionStart = caret - query.length - 1;
    _mentionQuery = query;
    _mentionTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final users = await StoryService.searchMentionUsers(query);
        if (!mounted || _mentionTargetController != controller || _mentionQuery != query) return;
        setState(() => _mentionSuggestions = users);
      } catch (_) {
        if (mounted && _mentionTargetController == controller) {
          setState(() => _mentionSuggestions = []);
        }
      }
    });
  }

  void _insertMention(String username) {
    final controller = _mentionTargetController;
    if (controller == null) return;
    final caret = controller.selection.baseOffset;
    if (caret < 0) return;
    final start = _mentionStart.clamp(0, caret).toInt();
    final nextText = controller.text.replaceRange(start, caret, '@$username ');
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + username.length + 2),
    );
    _mentionTimer?.cancel();
    setState(() {
      _mentionTargetController = null;
      _mentionSuggestions = [];
      _mentionQuery = '';
    });
  }

  Widget _mentionSuggestionPanel(TextEditingController controller) {
    if (_mentionTargetController != controller || _mentionSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _mentionSuggestions.map((user) => ListTile(
          dense: true,
          leading: const CircleAvatar(radius: 15, child: Icon(Icons.person_outline, size: 17)),
          title: Text(user['display_name'] as String? ?? user['username'] as String),
          subtitle: Text('@' + (user['username'] as String)),
          onTap: () => _insertMention(user['username'] as String),
        )).toList(),
      ),
    );
  }

  Future<void> _pick(bool video) async {
    try {
      final picked = video
          ? await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60))
          : await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
      if (picked == null || !mounted) return;
      final name = picked.name.toLowerCase();
      final mime = picked.mimeType ?? '';
      final valid = video
          ? mime == 'video/mp4' || mime == 'video/quicktime' || name.endsWith('.mp4') || name.endsWith('.mov')
          : mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp' ||
              RegExp(r'\.(jpe?g|png|webp)$').hasMatch(name);
      if (!valid) {
        _notice('فرمت این رسانه پشتیبانی نمی‌شود.', true);
        return;
      }
      final size = await picked.length();
      if (size == 0 || size > 50 * 1024 * 1024) {
        _notice('حجم رسانه باید حداکثر ۵۰ مگابایت باشد.', true);
        return;
      }
      setState(() { _file = picked; _type = video ? 'video' : 'image'; _textMode = false; });
    } catch (_) {
      _notice('انتخاب رسانه انجام نشد.', true);
    }
  }


  Future<void> _pickImageSticker() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gif', 'jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        _notice('دسترسی به فایل انتخاب‌شده ممکن نشد.', true);
        return;
      }
      if (picked.size <= 0 || picked.size > 5 * 1024 * 1024) {
        _notice('حجم استیکر باید حداکثر ۵ مگابایت باشد.', true);
        return;
      }
      final ext = picked.extension?.toLowerCase() ?? '';
      const mimeByExt = {
        'gif': 'image/gif', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'png': 'image/png', 'webp': 'image/webp',
      };
      final mime = mimeByExt[ext];
      if (mime == null) {
        _notice('فقط فایل‌های GIF، JPG، PNG و WebP پشتیبانی می‌شوند.', true);
        return;
      }
      if (_stickers.length >= 20) {
        _notice('حداکثر ۲۰ استیکر می‌توانید اضافه کنید.', true);
        return;
      }
      setState(() {
        _stickers.add({
          'type': 'image',
          'local_path': path,
          'file_name': picked.name,
          'mime_type': mime,
          'x': .5, 'y': .5, 'scale': 1.0, 'rotation': 0.0,
        });
      });
    } catch (_) {
      _notice('انتخاب استیکر انجام نشد.', true);
    }
  }

  Future<void> _pickMusic() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'aac', 'wav'], allowMultiple: false, withData: false);
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) { _notice('دسترسی به فایل موسیقی ممکن نشد.', true); return; }
      if (picked.size <= 0 || picked.size > 15 * 1024 * 1024) { _notice('حجم موسیقی باید حداکثر ۱۵ مگابایت باشد.', true); return; }
      final ext = picked.extension?.toLowerCase() ?? '';
      const mimeByExt = {'mp3':'audio/mpeg','m4a':'audio/mp4','aac':'audio/aac','wav':'audio/wav'};
      final mime = mimeByExt[ext];
      if (mime == null) { _notice('فقط فایل‌های MP3، M4A، AAC و WAV پشتیبانی می‌شوند.', true); return; }
      final preview = VideoPlayerController.file(File(path));
      await preview.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) { await preview.dispose(); return; }
      await preview.setLooping(false);
      await preview.setVolume(_musicVolume);
      await _musicPreview?.dispose();
      setState(() { _musicFile = File(path); _musicFileName = picked.name; _musicMimeType = mime; _musicPreview = preview; _musicDuration = preview.value.duration; _musicStartMs = 0; });
    } catch (_) { _notice('بارگذاری یا پیش‌نمایش موسیقی انجام نشد. فایل دیگری انتخاب کنید.', true); }
  }

  Future<void> _toggleMusicPreview() async {
    final preview = _musicPreview;
    if (preview == null || !preview.value.isInitialized) return;
    try {
      if (preview.value.isPlaying) { await preview.pause(); }
      else { await preview.seekTo(Duration(milliseconds: _musicStartMs)); await preview.setVolume(_musicVolume); await preview.play(); }
      if (mounted) setState(() {});
    } catch (_) { _notice('پخش پیش‌نمایش موسیقی انجام نشد.', true); }
  }

  Future<void> _removeMusic() async {
    final preview = _musicPreview; _musicPreview = null;
    await preview?.pause(); await preview?.dispose();
    if (!mounted) return;
    setState(() { _musicFile = null; _musicFileName = null; _musicMimeType = null; _musicDuration = Duration.zero; _musicStartMs = 0; });
  }

  void _startDrawing(Offset point, Size size) {
    setState(() {
      _drawingStrokes.add({
        'color': _drawingColor,
        'width': _drawingWidth,
        'erase': _eraserMode,
        'points': [[
          (point.dx / size.width).clamp(0.0, 1.0),
          (point.dy / size.height).clamp(0.0, 1.0),
        ]],
      });
    });
  }

  void _continueDrawing(Offset point, Size size) {
    if (_drawingStrokes.isEmpty) return;
    setState(() {
      final points = _drawingStrokes.last['points'] as List;
      if (points.length >= 300) return;
      points.add([
        (point.dx / size.width).clamp(0.0, 1.0),
        (point.dy / size.height).clamp(0.0, 1.0),
      ]);
    });
  }

  void _notice(String message, [bool error = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _pickCountdownTarget() async {
    final now = DateTime.now();
    final initial = _countdownTarget.isAfter(now) ? _countdownTarget : now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'تاریخ پایان شمارش معکوس',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'ساعت پایان',
    );
    if (time == null || !mounted) return;
    final target = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!target.isAfter(DateTime.now().add(const Duration(seconds: 10)))) {
      _notice('زمان پایان باید در آینده باشد.', true);
      return;
    }
    setState(() => _countdownTarget = target);
  }


  Map<String, double> _widgetTransform(String key) => Map<String, double>.from(
    _widgetLayout[key] ?? const {'x': .5, 'y': .5, 'scale': 1.0, 'rotation': 0.0},
  );

  void _updateWidgetTransform(String key, Map<String, double> value) {
    setState(() { _widgetLayout[key] = value; _selectedWidget = key; });
  }

  Future<void> _saveDraft() async {
    if (_busy) return;
    if (_textMode && _caption.text.trim().isEmpty) {
      _notice('برای ذخیره پیش‌نویس، ابتدا متن استوری را وارد کنید.', true);
      return;
    }
    if (!_textMode && _file == null) {
      _notice('ابتدا یک تصویر یا ویدئو انتخاب کنید.', true);
      return;
    }
    setState(() => _busy = true);
    try {
      final file = _file;
      final mime = file == null ? null : (file.mimeType ??
          (_type == 'video'
            ? (file.name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
            : _imageMime(file.name)));
      final data = <String, dynamic>{
        'text_mode': _textMode,
        'media_type': _type,
        'media_name': file?.name,
        'media_mime': mime,
        'caption': _caption.text,
        'overlay_text': _overlayText.text,
        'overlay_x': _overlayX,
        'overlay_y': _overlayY,
        'overlay_scale': _overlayScale,
        'overlay_color': _overlayColor,
        'overlay_font': _overlayFont,
        'drawing_data': _drawingStrokes,
        'widget_layout': _widgetLayout,
        'audience': _audience,
        'background_key': _backgroundKey,
        'music_name': _musicFileName,
        'music_mime': _musicMimeType,
        'music_start_ms': _musicStartMs,
        'music_volume': _musicVolume,
        'poll_enabled': _pollEnabled,
        'poll_question': _pollQuestion.text,
        'poll_options': _pollOptions.map((item) => item.text).toList(),
        'question_box_enabled': _questionBoxEnabled,
        'question_box_prompt': _questionBoxPrompt.text,
        'countdown_enabled': _countdownEnabled,
        'countdown_title': _countdownTitle.text,
        'countdown_target': _countdownTarget.toIso8601String(),
        'drawing_mode': _drawingMode,
        'eraser_mode': _eraserMode,
        'drawing_color': _drawingColor,
        'drawing_width': _drawingWidth,
      };
      await StoryService.saveDraft(
        draftData: data,
        mediaFile: file == null ? null : File(file.path),
        mediaFileName: file?.name,
        mediaMimeType: mime,
        musicFile: _musicFile,
        musicFileName: _musicFileName,
        musicMimeType: _musicMimeType,
        stickers: _stickers,
      );
      _notice('پیش‌نویس با موفقیت ذخیره شد.');
    } catch (_) {
      _notice('ذخیره پیش‌نویس انجام نشد. فضای ذخیره‌سازی یا اتصال را بررسی کنید.', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDrafts() async {
    if (_busy) return;
    List<Map<String, dynamic>> drafts;
    try {
      drafts = await StoryService.loadDrafts();
    } catch (_) {
      _notice('دریافت پیش‌نویس‌ها انجام نشد.', true);
      return;
    }
    if (!mounted) return;
    if (drafts.isEmpty) {
      _notice('هنوز پیش‌نویسی ذخیره نکرده‌ای.');
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refresh) => SizedBox(
          height: MediaQuery.of(context).size.height * .65,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(child: Text('پیش‌نویس‌های من',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  Text('${drafts.length} مورد',
                    style: const TextStyle(color: HomaGramTheme.turquoise)),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: drafts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final data = Map<String, dynamic>.from(draft['draft_data'] as Map);
                      final textMode = data['text_mode'] == true;
                      final title = (data['caption'] as String? ?? '').trim();
                      final type = data['media_type'] == 'video' ? 'ویدئو' :
                        data['media_type'] == 'image' ? 'تصویر' : 'متنی';
                      final date = DateTime.tryParse(draft['updated_at'] as String? ?? '');
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: HomaGramTheme.turquoise.withValues(alpha: .12),
                          child: Icon(textMode ? Icons.text_fields_rounded :
                            (data['media_type'] == 'video' ? Icons.videocam_outlined : Icons.image_outlined),
                            color: HomaGramTheme.turquoise),
                        ),
                        title: Text(title.isEmpty ? 'پیش‌نویس $type' : title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(date == null ? type :
                          '$type • ${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')}'),
                        onTap: () => Navigator.pop(sheetContext, draft['id'] as String),
                        trailing: IconButton(
                          tooltip: 'حذف پیش‌نویس',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            try {
                              await StoryService.deleteDraft(draft['id'] as String);
                              refresh(() => drafts.removeAt(index));
                              if (drafts.isEmpty && sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            } catch (_) {
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('حذف پیش‌نویس انجام نشد.')),
                                );
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selectedId != null && mounted) await _restoreDraft(selectedId);
  }

  Future<void> _restoreDraft(String draftId) async {
    setState(() => _busy = true);
    try {
      final data = await StoryService.loadDraft(draftId);
      if (data == null) throw StateError('Draft not found');
      final value = (String key, [String fallback = '']) => data[key]?.toString() ?? fallback;
      _caption.text = value('caption');
      _overlayText.text = value('overlay_text');
      _overlayX = (data['overlay_x'] as num?)?.toDouble() ?? .5;
      _overlayY = (data['overlay_y'] as num?)?.toDouble() ?? .5;
      _overlayScale = (data['overlay_scale'] as num?)?.toDouble() ?? 1;
      _overlayColor = value('overlay_color', '#FFFFFF');
      _overlayFont = value('overlay_font', 'estedad');
      _audience = value('audience', 'everyone');
      _backgroundKey = value('background_key', 'aurora');
      _textMode = data['text_mode'] == true;
      _type = data['media_type'] as String?;
      final mediaPath = data['_media_file_path'] as String?;
      _file = mediaPath == null ? null : XFile(mediaPath, name: value('media_name', 'story_media'));
      _drawingStrokes
        ..clear()
        ..addAll((data['drawing_data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
      _stickers
        ..clear()
        ..addAll((data['stickers'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
      final savedLayout = data['widget_layout'];
      if (savedLayout is Map) {
        for (final key in const ['text', 'poll', 'question', 'countdown']) {
          final raw = savedLayout[key];
          if (raw is Map) _widgetLayout[key] = {
            'x': ((raw['x'] as num?)?.toDouble() ?? .5).clamp(.05, .95).toDouble(),
            'y': ((raw['y'] as num?)?.toDouble() ?? .5).clamp(.08, .92).toDouble(),
            'scale': ((raw['scale'] as num?)?.toDouble() ?? 1).clamp(.55, 2.2).toDouble(),
            'rotation': ((raw['rotation'] as num?)?.toDouble() ?? 0).clamp(-3.14, 3.14).toDouble(),
          };
        }
      }
      if (!_widgetLayout.containsKey('text')) _widgetLayout['text'] = {
        'x': _overlayX, 'y': _overlayY, 'scale': _overlayScale, 'rotation': 0,
      };
      _selectedWidget = null;
      _pollEnabled = data['poll_enabled'] == true;
      _pollQuestion.text = value('poll_question');
      final options = (data['poll_options'] as List? ?? []).map((e) => e.toString()).toList();
      for (final item in _pollOptions) { item.dispose(); }
      _pollOptions
        ..clear()
        ..addAll((options.isEmpty ? ['', ''] : options).map((e) => TextEditingController(text: e)));
      _questionBoxEnabled = data['question_box_enabled'] == true;
      _questionBoxPrompt.text = value('question_box_prompt');
      _countdownEnabled = data['countdown_enabled'] == true;
      _countdownTitle.text = value('countdown_title');
      _countdownTarget = DateTime.tryParse(value('countdown_target')) ??
        DateTime.now().add(const Duration(days: 1));
      _drawingMode = data['drawing_mode'] == true;
      _eraserMode = data['eraser_mode'] == true;
      _drawingColor = value('drawing_color', '#FFFFFF');
      _drawingWidth = (data['drawing_width'] as num?)?.toDouble() ?? 5;
      _musicFileName = data['music_name'] as String?;
      _musicMimeType = data['music_mime'] as String?;
      _musicStartMs = (data['music_start_ms'] as num?)?.toInt() ?? 0;
      _musicVolume = (data['music_volume'] as num?)?.toDouble() ?? .75;
      final musicPath = data['_music_file_path'] as String?;
      await _musicPreview?.dispose();
      _musicPreview = null;
      _musicFile = musicPath == null ? null : File(musicPath);
      _musicDuration = Duration.zero;
      if (musicPath != null) {
        final preview = VideoPlayerController.file(File(musicPath));
        await preview.initialize().timeout(const Duration(seconds: 20));
        await preview.setVolume(_musicVolume);
        _musicDuration = preview.value.duration;
        _musicPreview = preview;
      }
      if (mounted) {
        setState(() {});
        _notice('پیش‌نویس بازیابی شد؛ می‌توانی ویرایش را ادامه بدهی.');
      }
    } catch (_) {
      _notice('بازیابی پیش‌نویس انجام نشد.', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final file = _file;
    final type = _type;
    if (_busy) return;
    if (_textMode) {
      if (_caption.text.trim().isEmpty || _caption.text.trim().length > 1000) {
        _notice('متن استوری باید بین ۱ تا ۱۰۰۰ نویسه باشد.', true);
        return;
      }
    } else {
      if (file == null || type == null) {
        _notice('ابتدا تصویر یا ویدئو انتخاب کنید.', true);
        return;
      }
      if (_caption.text.trim().length > 500) {
        _notice('متن استوری حداکثر ۵۰۰ نویسه است.', true);
        return;
      }
      if (_questionBoxEnabled && (_questionBoxPrompt.text.trim().isEmpty || _questionBoxPrompt.text.trim().length > 180)) {
        _notice('متن باکس پرسش را بین ۱ تا ۱۸۰ نویسه وارد کنید.', true);
        return;
      }
      if (_countdownEnabled && (_countdownTitle.text.trim().isEmpty || _countdownTitle.text.trim().length > 100 ||
          !_countdownTarget.isAfter(DateTime.now().add(const Duration(seconds: 10))))) {
        _notice('عنوان و زمان شمارش معکوس را درست وارد کنید.', true);
        return;
      }
      if (_pollEnabled) {
        final question = _pollQuestion.text.trim();
        final options = _pollOptions.map((item) => item.text.trim()).toList();
        if (question.isEmpty || question.length > 160 || options.any((item) => item.isEmpty || item.length > 60) ||
            options.map((item) => item.toLowerCase()).toSet().length != options.length) {
          _notice('سؤال و گزینه‌های نظرسنجی را کامل و بدون تکرار وارد کنید.', true);
          return;
        }
      }
    }
    setState(() => _busy = true);
    try {
      if (_textMode) {
        await StoryService.publishText(
          textContent: _caption.text,
          backgroundKey: _backgroundKey,
          audience: _audience,
        );
      } else {
        final mime = file!.mimeType ?? (type == 'video'
            ? (file.name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4')
            : _imageMime(file.name));
        await StoryService.publish(
          file: File(file.path),
          mediaType: type!,
          fileName: file.name,
          mimeType: mime,
          caption: _caption.text,
          overlayText: _overlayText.text,
          overlayX: _overlayX,
          overlayY: _overlayY,
          overlayScale: _overlayScale,
          overlayColor: _overlayColor,
          overlayFont: _overlayFont,
          drawingData: _drawingStrokes,
          stickerData: _stickers,
          widgetLayout: _widgetLayout,
          musicFile: _musicFile,
          musicFileName: _musicFileName,
          musicMimeType: _musicMimeType,
          musicStartMs: _musicStartMs,
          musicVolume: _musicVolume,
          pollQuestion: _pollEnabled ? _pollQuestion.text : null,
          pollOptions: _pollEnabled ? _pollOptions.map((item) => item.text).toList() : null,
          questionBoxPrompt: _questionBoxEnabled ? _questionBoxPrompt.text : null,
          countdownTitle: _countdownEnabled ? _countdownTitle.text : null,
          countdownTargetAt: _countdownEnabled ? _countdownTarget : null,
          audience: _audience,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      _notice('انتشار استوری انجام نشد. اتصال یا فرمت رسانه را بررسی کنید.', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _imageMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ساخت استوری')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_textMode)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 330,
              child: StoryTextStoryView(
                text: _caption.text.isEmpty ? 'متن استوری شما اینجا نمایش داده می‌شود' : _caption.text,
                backgroundKey: _backgroundKey,
              ),
            ),
          )
        else if (_file == null)
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2)),
            ),
            child: const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 58, color: HomaGramTheme.turquoise)),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 300,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    _type == 'image'
                        ? Image.file(File(_file!.path), fit: BoxFit.contain)
                        : Container(
                            color: Colors.black87,
                            child: const Center(child: Icon(Icons.play_circle_outline, size: 70, color: Colors.white)),
                          ),
                    if (_pollEnabled)
                      _TransformableStoryElement(
                        layout: _widgetTransform('poll'), editing: true,
                        selected: _selectedWidget == 'poll',
                        onChanged: (value) => _updateWidgetTransform('poll', value),
                        child: _StoryPollCard(
                          poll: {
                            'question': _pollQuestion.text.trim().isEmpty ? 'سؤال نظرسنجی' : _pollQuestion.text.trim(),
                            'options': _pollOptions.map((item) => item.text.trim().isEmpty ? 'گزینه' : item.text.trim()).toList(),
                            'counts': List<int>.filled(_pollOptions.length, 0), 'total_votes': 0,
                          }, isOwner: true,
                        ),
                      ),
                    if (_questionBoxEnabled)
                      _TransformableStoryElement(
                        layout: _widgetTransform('question'), editing: true,
                        selected: _selectedWidget == 'question',
                        onChanged: (value) => _updateWidgetTransform('question', value),
                        child: _StoryQuestionBoxCard(
                          question: {'prompt': _questionBoxPrompt.text.trim().isEmpty ? 'باکس پرسش' : _questionBoxPrompt.text.trim(), 'response_count': 0},
                          isOwner: true,
                        ),
                      ),
                    if (_countdownEnabled)
                      _TransformableStoryElement(
                        layout: _widgetTransform('countdown'), editing: true,
                        selected: _selectedWidget == 'countdown',
                        onChanged: (value) => _updateWidgetTransform('countdown', value),
                        child: _StoryCountdownCard(
                          countdown: {
                            'title': _countdownTitle.text.trim().isEmpty ? 'شمارش معکوس' : _countdownTitle.text.trim(),
                            'target_at': _countdownTarget.toIso8601String(),
                          },
                        ),
                      ),
                    if (_stickers.isNotEmpty)
                      Positioned.fill(child: _StoryStickerLayer(
                        stickers: _stickers,
                        interactive: true,
                        onChanged: (value) => setState(() { _stickers..clear()..addAll(value); }),
                      )),
                    if (_drawingStrokes.isNotEmpty)
                      Positioned.fill(child: IgnorePointer(
                        child: CustomPaint(painter: _StoryDrawingPainter(_drawingStrokes)),
                      )),
                    if (_drawingMode)
                      Positioned.fill(child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) => _startDrawing(details.localPosition, constraints.biggest),
                        onPanUpdate: (details) => _continueDrawing(details.localPosition, constraints.biggest),
                        child: const SizedBox.expand(),
                      )),
                    if (_overlayText.text.trim().isNotEmpty)
                      _TransformableStoryElement(
                        layout: _widgetTransform('text'), editing: true,
                        selected: _selectedWidget == 'text',
                        onChanged: (value) {
                          _updateWidgetTransform('text', value);
                          _overlayX = value['x']!;
                          _overlayY = value['y']!;
                          _overlayScale = value['scale']!;
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _overlayText.text, textAlign: TextAlign.center,
                            maxLines: 5, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: storyOverlayColor(_overlayColor), fontSize: 24,
                              fontFamily: _storyOverlayFont(_overlayFont), height: 1.35,
                              fontWeight: FontWeight.w800,
                              shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => setState(() {
            _textMode = true;
            _file = null;
            _type = 'text';
            _caption.clear();
          }),
          icon: const Icon(Icons.text_fields_rounded),
          label: const Text('ساخت استوری متنی'),
        ),
        if (!_textMode) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : () => _pick(false),
            icon: const Icon(Icons.image_outlined), label: const Text('انتخاب تصویر')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : () => _pick(true),
            icon: const Icon(Icons.video_library_outlined), label: const Text('انتخاب ویدئو (حداکثر ۶۰ ثانیه)')),
        ] else ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : () => setState(() {
                _textMode = false;
                _type = null;
                _caption.clear();
              }),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('بازگشت به استوری تصویری'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: storyTextGradients.entries.map((entry) => InkWell(
              onTap: _busy ? null : () => setState(() => _backgroundKey = entry.key),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: entry.value),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _backgroundKey == entry.key ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
        if (!_textMode && _file != null) ...[

          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: Text('موسیقی استوری', style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height: 7),
          if (_musicFile == null)
            OutlinedButton.icon(onPressed: _busy ? null : _pickMusic, icon: const Icon(Icons.music_note_rounded), label: const Text('افزودن موسیقی از دستگاه'))
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).cardTheme.color, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .2))),
              child: Row(children: [
                const Icon(Icons.audio_file_rounded, color: HomaGramTheme.turquoise), const SizedBox(width: 9),
                Expanded(child: Text(_musicFileName ?? 'موسیقی انتخاب‌شده', maxLines: 1, overflow: TextOverflow.ellipsis)),
                ValueListenableBuilder<VideoPlayerValue>(valueListenable: _musicPreview!, builder: (context, value, _) => IconButton(tooltip: value.isPlaying ? 'توقف پیش‌نمایش' : 'پخش پیش‌نمایش', onPressed: _busy ? null : _toggleMusicPreview, icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill))),
                IconButton(tooltip: 'حذف موسیقی', onPressed: _busy ? null : _removeMusic, icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            if (_musicDuration.inMilliseconds > 5000)
              Row(children: [const Text('شروع از'), Expanded(child: Slider(min: 0, max: (_musicDuration.inMilliseconds - 5000).toDouble(), value: _musicStartMs.clamp(0, _musicDuration.inMilliseconds - 5000).toDouble(), onChanged: _busy ? null : (value) async { setState(() => _musicStartMs = value.round()); await _musicPreview?.pause(); await _musicPreview?.seekTo(Duration(milliseconds: _musicStartMs)); })), Text('${(_musicStartMs / 1000).toStringAsFixed(0)}ث')]),
            Row(children: [const Icon(Icons.volume_down_rounded, size: 19), Expanded(child: Slider(min: 0, max: 1, value: _musicVolume, onChanged: _busy ? null : (value) async { setState(() => _musicVolume = value); await _musicPreview?.setVolume(value); })), const Icon(Icons.volume_up_rounded, size: 19)]),
            const Text('موسیقی همراه استوری پخش می‌شود؛ هنگام پخش موسیقی روی ویدئو، صدای اصلی ویدئو قطع می‌شود.', style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4))),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text('استیکرها', style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 7),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _busy || _stickers.length >= 20 ? null : _pickImageSticker,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('تصویر یا GIF'),
            ),
            for (final emoji in ['❤️', '😍', '😂', '🔥', '✨', '⭐', '🌈', '🌸', '🦋', '🎉', '☀️', '🌙', '💯', '👏', '🎈', '🍀', '☕', '🎧'])
              ActionChip(
                label: Text(emoji, style: const TextStyle(fontSize: 22)),
                onPressed: _busy || _stickers.length >= 20 ? null : () => setState(() {
                  _stickers.add({'emoji': emoji, 'x': .5, 'y': .5, 'scale': 1.0, 'rotation': 0.0});
                }),
              ),
            ActionChip(
              avatar: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('حذف همه'),
              onPressed: _stickers.isEmpty ? null : () => setState(_stickers.clear),
            ),
          ]),
          const Text('استیکر را روی پیش‌نمایش بکشید؛ با دو انگشت اندازه و زاویه را تغییر دهید. برای حذف یک استیکر، آن را چند لحظه نگه دارید.',
            style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4))),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _pollEnabled,
            onChanged: _busy ? null : (value) => setState(() => _pollEnabled = value),
            title: const Text('افزودن نظرسنجی'),
            subtitle: const Text('مخاطبان استوری می‌توانند رأی بدهند.'),
            secondary: const Icon(Icons.poll_outlined),
          ),
          if (_pollEnabled) ...[
            TextField(
              controller: _pollQuestion,
              maxLength: 160,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'سؤال نظرسنجی',
                hintText: 'مثلاً کدام طرح را بیشتر می‌پسندید؟',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 5),
            for (var i = 0; i < _pollOptions.length; i++) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pollOptions[i],
                      maxLength: 60,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'گزینه ${i + 1}',
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_pollOptions.length > 2)
                    IconButton(
                      tooltip: 'حذف گزینه',
                      onPressed: _busy ? null : () {
                        setState(() {
                          _pollOptions.removeAt(i).dispose();
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                ],
              ),
              const SizedBox(height: 7),
            ],
            if (_pollOptions.length < 4)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => setState(() {
                    _pollOptions.add(TextEditingController());
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('افزودن گزینه'),
                ),
              ),
            const Text(
              'هر نظرسنجی بین ۲ تا ۴ گزینه دارد. هر کاربر یک رأی ثبت می‌کند و پس از رأی دادن نیز می‌تواند انتخابش را تغییر دهد.',
              style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4)),
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _questionBoxEnabled,
            onChanged: _busy ? null : (value) => setState(() => _questionBoxEnabled = value),
            title: const Text('افزودن باکس پرسش و پاسخ'),
            subtitle: const Text('مخاطبان می‌توانند پاسخ متنی خصوصی برای شما بفرستند.'),
            secondary: const Icon(Icons.question_answer_outlined),
          ),
          if (_questionBoxEnabled)
            TextField(
              controller: _questionBoxPrompt,
              maxLength: 180,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'متن باکس پرسش',
                hintText: 'مثلاً دوست دارید درباره چه چیزی بدانید؟',
                border: OutlineInputBorder(),
              ),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _countdownEnabled,
            onChanged: _busy ? null : (value) => setState(() => _countdownEnabled = value),
            title: const Text('افزودن شمارش معکوس'),
            subtitle: const Text('برای یک رویداد یا زمان مهم، شمارش معکوس نمایش دهید.'),
            secondary: const Icon(Icons.timer_outlined),
          ),
          if (_countdownEnabled) ...[
            TextField(
              controller: _countdownTitle,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'عنوان شمارش معکوس',
                hintText: 'مثلاً شروع یک رویداد',
                border: OutlineInputBorder(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickCountdownTarget,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                'تاریخ و ساعت: ${_countdownTarget.year}/${_countdownTarget.month.toString().padLeft(2, '0')}/${_countdownTarget.day.toString().padLeft(2, '0')}  •  ${_countdownTarget.hour.toString().padLeft(2, '0')}:${_countdownTarget.minute.toString().padLeft(2, '0')}',
              ),
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _drawingMode,
            onChanged: _busy ? null : (value) => setState(() => _drawingMode = value),
            title: const Text('ابزار نقاشی آزاد'),
            subtitle: Text(_drawingMode ? 'روی رسانه بکشید' : 'برای طراحی فعال کنید'),
            secondary: const Icon(Icons.draw_rounded),
          ),
          if (_drawingMode) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final color in ['#FFFFFF', '#111827', '#FFE082', '#FF6B6B', '#45D6C5', '#A78BFA', '#F9A8D4'])
                InkWell(
                  onTap: () => setState(() { _drawingColor = color; _eraserMode = false; }),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: storyOverlayColor(color), shape: BoxShape.circle,
                      border: Border.all(color: _drawingColor == color && !_eraserMode ? HomaGramTheme.turquoise : Colors.grey, width: 3),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _eraserMode = !_eraserMode),
                icon: Icon(_eraserMode ? Icons.brush_rounded : Icons.auto_fix_high_outlined),
                label: Text(_eraserMode ? 'قلم' : 'پاک‌کن'),
              ),
              IconButton(
                tooltip: 'بازگشت',
                onPressed: _drawingStrokes.isEmpty ? null : () => setState(() => _drawingStrokes.removeLast()),
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton(
                tooltip: 'پاک‌کردن همه',
                onPressed: _drawingStrokes.isEmpty ? null : () => setState(() => _drawingStrokes.clear()),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ]),
            Row(children: [
              const Text('ضخامت'),
              Expanded(child: Slider(value: _drawingWidth, min: 1, max: 24, onChanged: (v) => setState(() => _drawingWidth = v))),
            ]),
          ],

          const SizedBox(height: 14),
          TextField(
            controller: _overlayText,
            maxLength: 180,
            maxLines: 2,
            onChanged: (_) {
              _updateMentionSuggestions(_overlayText);
              if (mounted) setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'متن روی تصویر یا ویدئو',
              hintText: 'متن را بنویسید، سپس روی پیش‌نمایش جابه‌جا یا بزرگ‌نمایی کنید',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.text_fields_rounded),
            ),
          ),
          _mentionSuggestionPanel(_overlayText),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text('رنگ متن', style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: const [
              ('#FFFFFF', Color(0xFFFFFFFF)),
              ('#111827', Color(0xFF111827)),
              ('#FFE082', Color(0xFFFFE082)),
              ('#FF6B6B', Color(0xFFFF6B6B)),
              ('#45D6C5', Color(0xFF45D6C5)),
              ('#A78BFA', Color(0xFFA78BFA)),
              ('#F9A8D4', Color(0xFFF9A8D4)),
            ].map((entry) => InkWell(
              onTap: _busy ? null : () => setState(() => _overlayColor = entry.$1),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: entry.$2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _overlayColor == entry.$1 ? HomaGramTheme.turquoise : Colors.grey,
                    width: _overlayColor == entry.$1 ? 3 : 1,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 12),
          Text('قلم متن', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 7),
          Wrap(spacing: 8, children: [
            ('estedad', 'پیش‌فرض'),
            ('serif', 'کلاسیک'),
            ('mono', 'فنی'),
          ].map((item) => ChoiceChip(
            label: Text(item.$2, style: TextStyle(fontFamily: _storyOverlayFont(item.$1))),
            selected: _overlayFont == item.$1,
            onSelected: _busy ? null : (_) => setState(() => _overlayFont = item.$1),
          )).toList()),
          const SizedBox(height: 8),
          const Text('برای جابه‌جایی، متن را روی پیش‌نمایش بکشید؛ برای تغییر اندازه از دو انگشت استفاده کنید.',
            style: TextStyle(fontSize: 11, height: 1.7, color: Color(0xFF8490A4))),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(children: [
                  Icon(Icons.visibility_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('مخاطبان استوری', style: TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _audience,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'everyone', child: Text('همه افراد مجاز')),
                    DropdownMenuItem(value: 'followers', child: Text('فقط دنبال‌کنندگان')),
                    DropdownMenuItem(value: 'close_friends', child: Text('فقط دوستان نزدیک')),
                  ],
                  onChanged: _busy ? null : (value) {
                    if (value != null) setState(() => _audience = value);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _audience == 'everyone'
                    ? 'حریم خصوصی حساب و مسدودسازی کاربران همچنان رعایت می‌شود.'
                    : _audience == 'followers'
                      ? 'فقط افرادی که شما را دنبال می‌کنند و مجاز به دیدن حساب هستند.'
                      : 'فقط افرادی که در فهرست دوستان نزدیکت قرار دارند؛ این فهرست خصوصی است.',
                  style: const TextStyle(fontSize: 11, height: 1.6, color: Color(0xFF8490A4)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(height: 14),
        TextField(
          controller: _caption,
          maxLength: _textMode ? 1000 : 500,
          maxLines: _textMode ? 6 : 3,
          onChanged: (_) {
            _updateMentionSuggestions(_caption);
            if (mounted) setState(() {});
          },
          decoration: InputDecoration(
            labelText: _textMode ? 'متن استوری' : 'توضیح تصویر یا ویدئو (اختیاری)',
            border: const OutlineInputBorder(),
          ),
        ),
        _mentionSuggestionPanel(_caption),
        const SizedBox(height: 10),
        const Text('استوری پس از ۲۴ ساعت از نمایش عمومی خارج می‌شود و در آرشیو شخصی شما باقی می‌ماند.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.8, color: Color(0xFF8490A4))),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _openDrafts,
                icon: const Icon(Icons.drafts_outlined),
                label: const Text('پیش‌نویس‌ها'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text('ذخیره پیش‌نویس'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(_busy ? 'در حال انتشار...' : 'انتشار استوری'),
        ),
      ],
    ),
  );
}

class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({required this.stories, super.key});
  final List<Map<String, dynamic>> stories;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _progress;
  int _index = 0;
  int _replayNonce = 0;
  bool _busy = false;
  bool _paused = false;
  bool _userPaused = false;
  bool _lifecyclePaused = false;
  bool _advancing = false;
  bool _routeVisible = true;
  double _horizontalDragDistance = 0;
  final Stopwatch _storyWatch = Stopwatch();
  bool _viewRecorded = false;

  Map<String, dynamic> get _story => widget.stories[_index];
  bool get _isMine => _story['author_id'] == AuthService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener(_onProgressStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markViewed();
      if (_story['media_type'] != 'video') _startProgress();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    _routeVisible = active;
    _lifecyclePaused = !active;
    _syncPauseState();
  }

  @override
  void dispose() {
    _flushStoryWatch();
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _nextStory();
  }

  void _startProgress({Duration? duration}) {
    if (!mounted) return;
    _progress.stop();
    _progress.duration = duration ?? (_story['music_path'] != null ? const Duration(seconds: 15) : const Duration(seconds: 5));
    _progress.value = 0;
    if (!_paused) _progress.forward();
  }

  void _onVideoReady(String storyId, Duration duration) {
    if (!mounted || _story['id'] != storyId || _story['media_type'] != 'video') return;
    _progress.stop();
    _progress.value = 0;
  }

  void _onVideoProgress(String storyId, Duration position, Duration duration, bool completed) {
    if (!mounted || _story['id'] != storyId || _story['media_type'] != 'video') return;
    if (duration > Duration.zero) {
      final value = (position.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0).toDouble();
      // Keep the animation controller as a display value only for video.
      _progress.value = completed ? .999 : value.clamp(0.0, .999).toDouble();
    }
    if (completed && !_advancing) _nextStory();
  }

  void _nextStory() {
    if (!mounted || _advancing) return;
    _advancing = true;
    _flushStoryWatch();
    if (_index < widget.stories.length - 1) {
      _progress.stop();
      setState(() {
        _index++;
        _paused = _userPaused || _lifecyclePaused || !_routeVisible;
      });
      _markViewed();
      if (_story['media_type'] != 'video') _startProgress();
    } else {
      Navigator.of(context).pop();
    }
    _advancing = false;
  }

  void _previousStory() {
    if (!mounted) return;
    if (_index > 0) {
      _flushStoryWatch();
      _progress.stop();
      setState(() {
        _index--;
        _paused = _userPaused || _lifecyclePaused || !_routeVisible;
      });
      _markViewed();
      if (_story['media_type'] != 'video') _startProgress();
    } else {
      _startProgress();
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _horizontalDragDistance = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDistance += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final distance = _horizontalDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _horizontalDragDistance = 0;

    // A deliberate swipe needs either a clear horizontal travel distance
    // or a sufficiently strong horizontal fling.
    if (distance <= -70 || velocity <= -500) {
      _nextStory();
    } else if (distance >= 70 || velocity >= 500) {
      _previousStory();
    }
  }

  void _setUserPaused(bool pause) {
    _userPaused = pause;
    _syncPauseState();
  }

  void _syncPauseState() {
    if (!mounted) return;
    final shouldPause = _userPaused || _lifecyclePaused || !_routeVisible;
    if (_paused == shouldPause) return;
    setState(() => _paused = shouldPause);
    if (shouldPause) {
      _progress.stop();
      if (_storyWatch.isRunning) _storyWatch.stop();
    } else {
      if (_viewRecorded && !_isMine) _storyWatch.start();
      if (_story['media_type'] != 'video') _progress.forward();
    }
  }

  Future<void> _markViewed() async {
    if (_isMine) return;
    final storyId = _story['id'] as String;
    _storyWatch
      ..stop()
      ..reset();
    _viewRecorded = false;
    try {
      await StoryService.recordView(storyId);
      if (!mounted || _story['id'] != storyId) return;
      _viewRecorded = true;
      if (!_paused) _storyWatch.start();
    } catch (_) {}
  }

  void _flushStoryWatch() {
    if (_isMine) return;
    if (_storyWatch.isRunning) _storyWatch.stop();
    final storyId = _story['id'] as String;
    final elapsedSeconds = _storyWatch.elapsed.inSeconds;
    final seconds = elapsedSeconds > 600 ? 600 : elapsedSeconds;
    _storyWatch.reset();
    _viewRecorded = false;
    if (seconds > 0) {
      unawaited(StoryService.recordViewDuration(storyId, seconds).catchError((_) => 0));
    }
  }

  Future<void> _votePoll(int optionIndex) async {
    final poll = _story['poll_data'];
    if (poll is! Map || _busy || _isMine) return;
    setState(() => _busy = true);
    try {
      final updated = await StoryService.voteStoryPoll(poll['id'] as String, optionIndex);
      if (mounted && _story['id'] == updated['story_id']) {
        setState(() => _story['poll_data'] = updated);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ثبت رأی انجام نشد؛ ممکن است مهلت نظرسنجی تمام شده باشد.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respondToStoryQuestion() async {
    final question = _story['question_box_data'];
    if (question is! Map || _busy || _isMine) return;
    final controller = TextEditingController(text: question['my_response'] as String? ?? '');
    final response = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پاسخ به پرسش'),
      content: TextField(controller: controller, autofocus: true, maxLength: 1000, minLines: 2, maxLines: 5,
        decoration: const InputDecoration(hintText: 'پاسخ شما', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ارسال')),
      ],
    ));
    controller.dispose();
    if (response == null || response.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = await StoryService.submitStoryQuestionResponse(question['id'] as String, response);
      if (mounted && updated['story_id'] == _story['id']) {
        setState(() => _story['question_box_data'] = updated);
        _notice('پاسخ شما ثبت شد.');
      }
    } catch (_) {
      if (mounted) _notice('ثبت پاسخ انجام نشد؛ ممکن است مهلت استوری تمام شده باشد.', error: true);
    } finally { if (mounted) setState(() => _busy = false); }
  }

  void _showStoryQuestionResponses() {
    final question = _story['question_box_data'];
    if (question is! Map || !_isMine) return;
    final responses = (question['responses'] as List? ?? const [])
        .whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * .65,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16),
            child: Text('پاسخ‌های مخاطبان • ${responses.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Expanded(child: responses.isEmpty
            ? const Center(child: Text('هنوز پاسخی دریافت نشده است.'))
            : ListView.separated(
                itemCount: responses.length, separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = responses[i];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(item['display_name'] as String? ?? 'کاربر'),
                    subtitle: Text(item['response'] as String? ?? ''),
                    trailing: IconButton(
                      tooltip: 'پاسخ خصوصی', icon: const Icon(Icons.reply_rounded),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await StoryService.replyToStory(item['user_id'] as String, 'پاسخ به باکس پرسش استوری: ${item['response']}');
                          if (mounted) _notice('پاسخ خصوصی ارسال شد.');
                        } catch (_) { if (mounted) _notice('ارسال پیام انجام نشد.', error: true); }
                      },
                    ),
                  );
                },
              )),
        ]),
      )));
  }

  Future<void> _react(String emoji) async {
    if (_busy || _isMine) return;
    setState(() => _busy = true);
    try {
      await StoryService.react(_story['id'] as String, emoji);
      if (mounted) _notice('واکنش شما ثبت شد.');
    } catch (_) {
      if (mounted) _notice('ثبت واکنش انجام نشد.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reply() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پاسخ به استوری'),
      content: TextField(controller: controller, autofocus: true, maxLength: 1000,
        minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'پیام شما')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ارسال')),
      ],
    ));
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await StoryService.replyToStory(_story['author_id'] as String, 'پاسخ به استوری: $text');
      if (mounted) _notice('پاسخ از طریق پیام خصوصی ارسال شد.');
    } catch (_) {
      if (mounted) _notice('ارسال پاسخ انجام نشد.', error: true);
    }
  }

  String _formatWatchTime(int seconds) {
    if (seconds < 60) return '${seconds} ثانیه';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes} دقیقه' : '${minutes} دقیقه و ${remainder} ثانیه';
  }

  Future<void> _showViewers() async {
    try {
      final analytics = await StoryService.loadStoryAnalytics(_story['id'] as String);
      if (!mounted) return;
      final viewers = (analytics['viewers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map)).toList();
      final reactionCounts = Map<String, int>.from(analytics['reaction_counts'] as Map);
      showModalBottomSheet<void>(
        context: context, showDragHandle: true, isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .78,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(children: [
                  const Text('آمار و تحلیل استوری', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Row(children: [
                    _analyticsMetric('بازدید', '${analytics['view_count']}', Icons.visibility_outlined),
                    const SizedBox(width: 8),
                    _analyticsMetric('واکنش', '${analytics['reaction_count']}', Icons.favorite_border_rounded),
                    const SizedBox(width: 8),
                    _analyticsMetric('میانگین تماشا', _formatWatchTime(analytics['average_watch_seconds'] as int), Icons.timer_outlined),
                  ]),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('مجموع زمان تماشا: ${_formatWatchTime(analytics['total_watch_seconds'] as int)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  if (reactionCounts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: reactionCounts.entries.map((entry) =>
                      Chip(visualDensity: VisualDensity.compact, label: Text('${entry.key}  ${entry.value}'))
                    ).toList()),
                  ],
                  const Divider(height: 18),
                  Align(alignment: Alignment.centerRight,
                    child: Text('فهرست بازدیدکنندگان • ${viewers.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
              ),
              Expanded(child: viewers.isEmpty
                  ? const Center(child: Text('هنوز بازدیدی ثبت نشده است.'))
                  : ListView.separated(
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final viewer = viewers[i];
                        final viewedAt = DateTime.tryParse(viewer['viewed_at']?.toString() ?? '')?.toLocal();
                        final time = viewedAt == null ? 'زمان نامشخص' :
                          '${viewedAt.hour.toString().padLeft(2, '0')}:${viewedAt.minute.toString().padLeft(2, '0')}';
                        final reaction = viewer['reaction'];
                        final watch = (viewer['duration_seconds'] as num?)?.toInt() ?? 0;
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(viewer['display_name'] as String),
                          subtitle: Text('@${viewer['username']} • ${time} • تماشا: ${_formatWatchTime(watch)}${reaction == null ? '' : ' • ${reaction}'}'),
                          isThreeLine: true,
                        );
                      },
                    )),
            ]),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _notice('آمار استوری بارگذاری نشد.', error: true);
    }
  }

  Widget _analyticsMetric(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: HomaGramTheme.turquoise.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: HomaGramTheme.turquoise.withValues(alpha: .2)),
      ),
      child: Column(children: [
        Icon(icon, size: 17, color: HomaGramTheme.turquoise),
        const SizedBox(height: 5),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ),
  );

  Future<void> _delete() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف استوری'),
      content: const Text('این استوری حذف شود؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    ));
    if (yes != true) return;
    try {
      final mediaPath = _story['media_path'] as String?;
      final mediaUrl = _story['media_url'] as String?;
      if (mediaPath != null && mediaUrl != null) {
        await imageCache.evict(StoryImageProvider(mediaUrl, cacheKey: 'story-media:$mediaPath'));
      }
      await StoryService.deleteStory(_story);
      final userId = AuthService.client.auth.currentUser?.id;
      if (userId != null && mediaPath != null) {
        await StoryVideoCache.evict(userId: userId, storagePath: mediaPath);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) _notice('حذف استوری انجام نشد.', error: true);
    }
  }

  void _notice(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: error ? Colors.red : null,
    ));
  }

  String _storyTimestamp(dynamic rawValue) {
    final date = DateTime.tryParse(rawValue?.toString() ?? '')?.toLocal();
    if (date == null) return 'زمان انتشار نامشخص';
    final time = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    const latin = '0123456789';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final localizedTime = time.split('').map((char) {
      final index = latin.indexOf(char);
      return index < 0 ? char : persian[index];
    }).join();
    return 'ارسال‌شده در ${persianDate(date)}  $localizedTime';
  }

  Map<String, double> _storyWidgetLayout(String key) {
    final all = _story['widget_layout'];
    final raw = all is Map ? all[key] : null;
    if (raw is Map) return {
      'x': ((raw['x'] as num?)?.toDouble() ?? .5).clamp(.05, .95).toDouble(),
      'y': ((raw['y'] as num?)?.toDouble() ?? .5).clamp(.08, .92).toDouble(),
      'scale': ((raw['scale'] as num?)?.toDouble() ?? 1).clamp(.55, 2.2).toDouble(),
      'rotation': ((raw['rotation'] as num?)?.toDouble() ?? 0).clamp(-3.14, 3.14).toDouble(),
    };
    const defaults = {
      'poll': {'x': .5, 'y': .58, 'scale': 1.0, 'rotation': 0.0},
      'question': {'x': .5, 'y': .76, 'scale': 1.0, 'rotation': 0.0},
      'countdown': {'x': .5, 'y': .38, 'scale': 1.0, 'rotation': 0.0},
    };
    return Map<String, double>.from(defaults[key]!);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        onHorizontalDragCancel: () => _horizontalDragDistance = 0,
        child: Stack(children: [
        _StoryMedia(
          key: ValueKey('${_story['id']}-$_replayNonce'),
          story: _story,
          paused: _paused,
          onVideoReady: _onVideoReady,
          onVideoProgress: _onVideoProgress,
        ),
        if (_story['media_type'] == 'image' || _story['media_type'] == 'video') ...[
          _StoryDrawingView(story: _story),
          _StoryStickerView(story: _story),
          _StoryOverlayTextView(story: _story),
        ],
        Positioned.fill(
          child: Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _previousStory,
              onLongPressStart: (_) => _setUserPaused(true),
              onLongPressEnd: (_) => _setUserPaused(false),
            )),
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _nextStory,
              onLongPressStart: (_) => _setUserPaused(true),
              onLongPressEnd: (_) => _setUserPaused(false),
            )),
          ]),
        ),
        if (_story['countdown_data'] is Map)
          _TransformableStoryElement(
            layout: _storyWidgetLayout('countdown'), child: _StoryCountdownCard(
              countdown: Map<String, dynamic>.from(_story['countdown_data'] as Map),
            ),
          ),
        if (_story['question_box_data'] is Map)
          _TransformableStoryElement(
            layout: _storyWidgetLayout('question'), child: _StoryQuestionBoxCard(
              question: Map<String, dynamic>.from(_story['question_box_data'] as Map),
              isOwner: _isMine, onRespond: _respondToStoryQuestion,
              onViewResponses: _showStoryQuestionResponses, busy: _busy,
            ),
          ),
        if (_story['poll_data'] is Map)
          _TransformableStoryElement(
            layout: _storyWidgetLayout('poll'), child: _StoryPollCard(
              poll: Map<String, dynamic>.from(_story['poll_data'] as Map),
              isOwner: _isMine, onVote: _isMine ? null : _votePoll, busy: _busy,
            ),
          ),
        Positioned(
          top: 10, left: 12, right: 12,
          child: Column(children: [
            Row(children: List.generate(widget.stories.length, (i) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 3,
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (_, __) => LinearProgressIndicator(
                        value: i < _index ? 1 : i > _index ? 0 : _progress.value,
                        backgroundColor: Colors.white38,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ))),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: _story['avatar_url'] == null ? null : StoryImageProvider(
                  _story['avatar_url'] as String,
                  cacheKey: 'avatar:${(_story['avatar_path'] as String?) ?? (_story['avatar_url'] as String)}',
                ),
                child: _story['avatar_url'] == null ? const Icon(Icons.person_outline) : null,
              ),
              const SizedBox(width: 9),
              Expanded(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_story['display_name'] as String,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_storyTimestamp(_story['created_at']),
                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              )),
              if (_isMine)
                IconButton(onPressed: _showViewers, icon: const Icon(Icons.visibility_outlined, color: Colors.white)),
              if (_isMine)
                IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: Colors.white)),
              IconButton(onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ]),
        ),
        if ((_story['caption'] as String).isNotEmpty)
          Positioned(left: 22, right: 22, bottom: 94,
            child: StoryInteractiveText(
              text: _story['caption'] as String,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            )),
        Positioned(
          left: 12, right: 12, bottom: 12,
          child: _isMine
              ? Align(alignment: Alignment.center, child: OutlinedButton.icon(
                  onPressed: _showViewers,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  icon: const Icon(Icons.visibility_outlined), label: const Text('مشاهده بازدیدکنندگان')))
              : Row(children: [
                  ...['❤️','🔥','👏','😂','😮'].map((e) => IconButton(
                    onPressed: _busy ? null : () => _react(e),
                    icon: Text(e, style: const TextStyle(fontSize: 23)),
                  )),
                  const Spacer(),
                  IconButton(onPressed: _reply, icon: const Icon(Icons.send_rounded, color: Colors.white)),
                ]),
        ),
        ]),
      ),
    ),
  );
}

class _StoryMedia extends StatefulWidget {
  const _StoryMedia({
    required this.story,
    required this.paused,
    required this.onVideoReady,
    required this.onVideoProgress,
    super.key,
  });
  final Map<String, dynamic> story;
  final bool paused;
  final void Function(String storyId, Duration duration) onVideoReady;
  final void Function(String storyId, Duration position, Duration duration, bool completed) onVideoProgress;

  @override
  State<_StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends State<_StoryMedia> {
  VideoPlayerController? _video;
  VideoPlayerController? _music;
  bool _loading = true;
  bool _hasError = false;
  bool _completionReported = false;
  bool _playbackErrorReported = false;

  @override
  void initState() {
    super.initState();
    if (widget.story['media_type'] == 'video' && widget.story['media_url'] != null) {
      _loadVideo();
    } else {
      _loading = false;
    }
    if (widget.story['music_url'] is String && (widget.story['music_url'] as String).isNotEmpty) _loadMusic();
  }

  Future<void> _loadMusic() async {
    final url = widget.story['music_url'] as String?;
    if (url == null || url.isEmpty) return;
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _music = controller;
      await controller.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || !identical(_music, controller)) { await controller.dispose(); return; }
      await controller.setLooping(false);
      final startMs = (widget.story['music_start_ms'] as num?)?.toInt() ?? 0;
      await controller.seekTo(Duration(milliseconds: startMs.clamp(0, controller.value.duration.inMilliseconds).toInt()));
      final volume = ((widget.story['music_volume'] as num?)?.toDouble() ?? .75).clamp(0.0, 1.0).toDouble();
      await controller.setVolume(volume);
      if (widget.story['media_type'] == 'video' && _video?.value.isInitialized == true) await _video?.setVolume(0);
      if (!widget.paused) await controller.play();
    } catch (_) {
      if (controller != null) { if (identical(_music, controller)) _music = null; await controller.dispose(); }
      if (mounted && widget.story['media_type'] == 'video') await _video?.setVolume(1);
    }
  }

  Future<void> _loadVideo() async {
    final url = widget.story['media_url'] as String?;
    if (url == null || url.trim().isEmpty) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
      return;
    }

    final previous = _video;
    if (previous != null) {
      previous.removeListener(_handleVideoUpdate);
      _video = null;
      await previous.dispose();
    }
    if (!mounted) return;

    setState(() {
      _loading = true;
      _hasError = false;
      _completionReported = false;
      _playbackErrorReported = false;
    });

    VideoPlayerController? controller;
    try {
      // Cache private media briefly in this account's app-private temp area.
      // Keep network playback as a fallback if the download/cache is unavailable.
      final userId = AuthService.client.auth.currentUser?.id;
      File? cachedFile;
      if (userId != null) {
        try {
          cachedFile = await StoryVideoCache.getOrDownload(
            url: url,
            storagePath: widget.story['media_path'] as String? ?? widget.story['id'].toString(),
            userId: userId,
          );
          if (!mounted) return;
        } catch (_) {
          cachedFile = null;
        }
      }

      controller = cachedFile != null
          ? VideoPlayerController.file(cachedFile)
          : VideoPlayerController.networkUrl(Uri.parse(url));
      _video = controller;
      await controller.initialize().timeout(const Duration(seconds: 30));

      if (!mounted || !identical(_video, controller)) {
        await controller.dispose();
        return;
      }

      await controller.setLooping(false);
      await controller.setVolume(_music?.value.isInitialized == true ? 0 : 1);
      controller.addListener(_handleVideoUpdate);
      setState(() => _loading = false);
      widget.onVideoReady(widget.story['id'] as String, controller.value.duration);
      if (!widget.paused) await controller.play();
    } catch (_) {
      if (controller != null) {
        controller.removeListener(_handleVideoUpdate);
        if (identical(_video, controller)) _video = null;
        await controller.dispose();
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  void _handleVideoUpdate() {
    final video = _video;
    if (!mounted || video == null || !video.value.isInitialized) return;
    final value = video.value;

    if (value.hasError) {
      if (!_playbackErrorReported) {
        _playbackErrorReported = true;
        setState(() => _hasError = true);
      }
      return;
    }

    final duration = value.duration;
    final completed = duration > Duration.zero && value.position >= duration;
    widget.onVideoProgress(
      widget.story['id'] as String,
      value.position,
      duration,
      completed && !_completionReported,
    );
    if (completed) _completionReported = true;
  }

  @override
  void didUpdateWidget(covariant _StoryMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _video?.pause();
        _music?.pause();
      } else {
        if (_video?.value.isInitialized == true && !_hasError) _video?.play();
        if (_music?.value.isInitialized == true) _music?.play();
      }
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_handleVideoUpdate);
    _video?.dispose();
    _music?.dispose();
    super.dispose();
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 42),
          const SizedBox(height: 12),
          const Text(
            'پخش ویدئو انجام نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, height: 1.7),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _loadVideo,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تلاش دوباره'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.story['media_type'] == 'text') {
      return Positioned.fill(
        child: StoryTextStoryView(
          text: widget.story['text_content'] as String? ?? '',
          backgroundKey: widget.story['background_key'] as String?,
        ),
      );
    }
    final url = widget.story['media_url'] as String?;
    if (url == null || url.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
      );
    }

    if (widget.story['media_type'] == 'video') {
      if (_hasError) return _errorView();
      if (_loading || _video?.value.isInitialized != true) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text('در حال بارگذاری ویدئو…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      }
      final video = _video!;
      return Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio > 0 ? video.value.aspectRatio : 9 / 16,
          child: VideoPlayer(video),
        ),
      );
    }

    return Center(
      child: Image(
        image: StoryImageProvider(
          url,
          cacheKey: 'story-media:${widget.story['media_path']}',
        ),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }
}

class StoryArchiveScreen extends StatefulWidget {
  const StoryArchiveScreen({super.key});

  @override
  State<StoryArchiveScreen> createState() => _StoryArchiveScreenState();
}

class _StoryArchiveScreenState extends State<StoryArchiveScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) return;
    if (_scrollController.position.extentAfter < 500) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _failed = false;
      _loadingMore = false;
      _hasMore = true;
      _offset = 0;
      _items.clear();
    });
    try {
      final page = await StoryService.loadArchivePage(offset: 0);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset = page.length;
        _hasMore = page.length == StoryService.archivePageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _failed = false;
    });
    try {
      final page = await StoryService.loadArchivePage(offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += page.length;
        _hasMore = page.length == StoryService.archivePageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _failed = true;
      });
    }
  }

  Future<void> _openStory(Map<String, dynamic> story) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StoryViewerScreen(stories: [story]),
      ),
    );
    if (deleted == true && mounted) await _loadFirstPage();
  }

  Widget _storyTile(Map<String, dynamic> story) {
    final createdAt = DateTime.tryParse(story['created_at'].toString())?.toLocal();
    return InkWell(
      onTap: () => _openStory(story),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          story['media_type'] == 'text'
              ? StoryTextStoryView(
                  text: story['text_content'] as String? ?? '',
                  backgroundKey: story['background_key'] as String?,
                  compact: true,
                )
              : story['media_type'] == 'image' && story['media_url'] != null
                  ? Image(
                      image: StoryImageProvider(
                        story['media_url'] as String,
                        cacheKey: 'story-media:${story['media_path']}',
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black87,
                        child: const Icon(Icons.broken_image_outlined, color: Colors.white70),
                      ),
                    )
                  : Container(
                      color: Colors.black87,
                      child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 34),
                    ),
          Positioned(
            bottom: 5, left: 5, right: 5,
            child: Text(
              createdAt == null
                  ? 'تاریخ نامشخص'
                  : persianDate(createdAt),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white, fontSize: 9,
                shadows: [Shadow(blurRadius: 5, color: Colors.black)],
              ),
            ),
          ),
          if (story['media_type'] == 'video')
            const Positioned(
              top: 6, right: 6,
              child: Icon(Icons.play_circle_fill, color: Colors.white, size: 20),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('آرشیو استوری‌ها'),
      actions: [
        IconButton(
          tooltip: 'بارگذاری دوباره',
          onPressed: _loading ? null : _loadFirstPage,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed && _items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('آرشیو بارگذاری نشد.'),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _loadFirstPage,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تلاش دوباره'),
                    ),
                  ],
                ),
              )
            : _items.isEmpty
                ? const Center(child: Text('هنوز استوری منقضی‌شده‌ای ندارید.'))
                : RefreshIndicator(
                    onRefresh: _loadFirstPage,
                    child: GridView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: .68,
                      ),
                      itemCount: _items.length + (_loadingMore || _failed ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          if (_failed) {
                            return Center(
                              child: IconButton(
                                tooltip: 'تلاش دوباره',
                                onPressed: _loadNextPage,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            );
                          }
                          return const Center(
                            child: SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return _storyTile(_items[index]);
                      },
                    ),
                  ),
  );
}
