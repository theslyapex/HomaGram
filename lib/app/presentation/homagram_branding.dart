import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';

class HomaGramLogo extends StatelessWidget {
  const HomaGramLogo({super.key, this.size = 88, this.fit = BoxFit.contain});

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/homagram_brand_logo.png',
        width: size,
        height: size,
        fit: fit,
        semanticLabel: 'لوگوی هماگرام',
        errorBuilder: (_, __, ___) => Icon(
          Icons.hub_rounded,
          size: size * .68,
          color: HomaGramTheme.turquoise,
        ),
      );
}

class HomaGramLaunchScreen extends StatefulWidget {
  const HomaGramLaunchScreen({required this.child, super.key});

  final Widget child;

  @override
  State<HomaGramLaunchScreen> createState() => _HomaGramLaunchScreenState();
}

class _HomaGramLaunchScreenState extends State<HomaGramLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _glow;
  late final Animation<double> _wordmarkOpacity;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .48, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: .78, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .72, curve: Curves.elasticOut),
      ),
    );
    _glow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.12, .72, curve: Curves.easeOutCubic),
    );
    _wordmarkOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.42, .88, curve: Curves.easeOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        setState(() => _finished = true);
        return;
      }
      _controller.forward().whenComplete(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) setState(() => _finished = true);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return Scaffold(
      backgroundColor: HomaGramTheme.darkCanvas,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.2),
            radius: 1.15,
            colors: [Color(0xFF1B3150), Color(0xFF101B35), Color(0xFF090F1E)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: HomaGramTheme.turquoise.withValues(
                              alpha: .25 * _glow.value,
                            ),
                            blurRadius: 48 * _glow.value,
                            spreadRadius: 8 * _glow.value,
                          ),
                          BoxShadow(
                            color: HomaGramTheme.royalPurple.withValues(
                              alpha: .18 * _glow.value,
                            ),
                            blurRadius: 72 * _glow.value,
                            spreadRadius: 4 * _glow.value,
                          ),
                        ],
                      ),
                      child: const HomaGramLogo(size: 172),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: _wordmarkOpacity.value,
                  child: Column(
                    children: const [
                      Text(
                        'HomaGram',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Connection Beyond Boundaries',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFB8C9DF),
                          fontSize: 11,
                          letterSpacing: 1.05,
                          fontWeight: FontWeight.w500,
                        ),
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


class HomaGramEntrance extends StatefulWidget {
  const HomaGramEntrance({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  State<HomaGramEntrance> createState() => _HomaGramEntranceState();
}

class _HomaGramEntranceState extends State<HomaGramEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        _delayTimer = Timer(widget.delay, () {
          if (mounted) _controller.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(_controller.value);
          return Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, 15 * (1 - progress)),
              child: child,
            ),
          );
        },
      );
}

class HomaGramSpringPress extends StatefulWidget {
  const HomaGramSpringPress({required this.child, super.key});

  final Widget child;

  @override
  State<HomaGramSpringPress> createState() => _HomaGramSpringPressState();
}

class _HomaGramSpringPressState extends State<HomaGramSpringPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, lowerBound: 0, upperBound: 1);
  }

  void _press() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.animateTo(
      1,
      duration: const Duration(milliseconds: 85),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _controller.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 360, damping: 18),
        _controller.value,
        0,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => Transform.scale(
            scale: 1 - (_controller.value * .035),
            child: child,
          ),
        ),
      );
}
