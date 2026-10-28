// File: lib/features/auth/presentation/screens/splash_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/fanitt_wordmark_path.dart';

/// true once "fanitt" has been written out. The router keeps the app on the
/// splash until then (see AppRouter: refreshListenable + _redirect).
final ValueNotifier<bool> splashDone = ValueNotifier<bool>(false);

const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4511E),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: _gradient),
          child: Stack(
            children: [
              // Two soft lights drifting slowly — gives the background depth.
              Positioned(
                left: -140,
                top: -170,
                child: IgnorePointer(
                  child: Container(
                    width: 440,
                    height: 440,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Color(0x45FFE0B0), Color(0x00FFE0B0)]),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).move(begin: Offset.zero, end: const Offset(40, 30), duration: 3200.ms, curve: Curves.easeInOutSine),
                ),
              ),
              Positioned(
                right: -160,
                bottom: -180,
                child: IgnorePointer(
                  child: Container(
                    width: 460,
                    height: 460,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Color(0x33FF8FB8), Color(0x00FF8FB8)]),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).move(begin: Offset.zero, end: const Offset(-36, -28), duration: 3600.ms, curve: Curves.easeInOutSine),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    const _WrittenWordmark(),
                    const Spacer(),
                    SizedBox(
                      height: 132,
                      child: BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) {
                          debugPrint('[Splash] auth state: ${state.runtimeType}');
                          return AnimatedSwitcher(
                            duration: AppDurations.normal,
                            child: state is AuthUnreachable
                                ? _Unreachable(key: const ValueKey('offline'), message: state.message)
                                : const _Loader(key: ValueKey('loading')),
                          );
                        },
                      ),
                    ),
                    const _VersionLabel(),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "fanitt" drawn in code (vector outlines of the logo lettering): a bright
/// pen traces each letter's outline, the letters fill in, then a soft glow
/// and a slow push-in. Vector + one painter = smooth at any refresh rate.
class _WrittenWordmark extends StatefulWidget {
  const _WrittenWordmark();

  @override
  State<_WrittenWordmark> createState() => _WrittenWordmarkState();
}

class _WrittenWordmarkState extends State<_WrittenWordmark> with SingleTickerProviderStateMixin {
  /// Full writing time. Slow enough to read every stroke.
  static const _duration = Duration(milliseconds: 3800);

  /// The finished word stays on screen a moment before the app moves on.
  static const _hold = Duration(milliseconds: 450);

  /// Longest step one frame may take. When the phone is busy starting up and
  /// frames drop, the drawing slows down a little instead of jumping ahead —
  /// so it never looks like it started from the middle.
  static const _maxStep = Duration(milliseconds: 34);

  final _progress = ValueNotifier<double>(0);
  late final _Wordmark _mark = _Wordmark();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  Timer? _fallback;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    // Measure the letters now (not on the first animated frame), then wait
    // for the screen to settle before the pen starts.
    if (_mark.metrics.isEmpty) debugPrint('[Splash] wordmark has no outlines');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        _last = Duration.zero;
        _ticker.start();
        // Safety net: never hold the app on the splash longer than this.
        _fallback = Timer(_duration * 2 + _hold, _finish);
      });
    });
  }

  void _onTick(Duration elapsed) {
    var step = elapsed - _last;
    _last = elapsed;
    if (step > _maxStep) step = _maxStep;
    final next = (_progress.value + step.inMicroseconds / _duration.inMicroseconds).clamp(0.0, 1.0);
    _progress.value = next;
    if (next >= 1) {
      _ticker.stop();
      _holdTimer = Timer(_hold, _finish);
    }
  }

  void _finish() {
    _fallback?.cancel();
    _holdTimer?.cancel();
    if (splashDone.value) return;
    debugPrint('[Splash] done → router may leave the splash');
    HapticFeedback.lightImpact();
    splashDone.value = true;
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _holdTimer?.cancel();
    _ticker.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * 0.70, 320.0);
    final height = width * kFanittWordmarkSize.height / kFanittWordmarkSize.width;
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _WordmarkPainter(_progress, _mark)),
      ),
    );
  }
}

/// Outlines + their lengths, measured once.
class _Wordmark {
  _Wordmark() {
    contours = fanittWordmarkContours();
    metrics = [for (final p in contours) p.computeMetrics().toList()];
    filled = Path()..fillType = PathFillType.evenOdd;
    for (final p in contours) {
      filled.addPath(p, Offset.zero);
    }
  }

  late final List<Path> contours;
  late final List<List<PathMetric>> metrics;
  late final Path filled;
}

class _WordmarkPainter extends CustomPainter {
  _WordmarkPainter(this.anim, this.mark) : super(repaint: anim);

  final ValueListenable<double> anim;
  final _Wordmark mark;

  /// When each contour is drawn, as a share of the drawing phase:
  /// f, "anitt", hole in a, dot on i.
  static const _windows = [(0.00, 0.40), (0.14, 0.94), (0.30, 0.52), (0.74, 0.92)];

  static double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final v = anim.value;
    final draw = _seg(v, 0.0, 0.62); // pen phase
    // Ink fills in left → right, following the pens.
    final sweep = Curves.easeInOutCubic.transform(_seg(v, 0.30, 0.74));
    final glowIn = _seg(v, 0.66, 1.0);
    final glow = glowIn < 0.5 ? glowIn * 2 : 1 - (glowIn - 0.5) * 2 * 0.5;
    final push = 0.96 + 0.06 * Curves.easeOutQuad.transform(v);

    final ws = kFanittWordmarkSize;
    final k = size.width / ws.width;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k * push);
    canvas.translate(-ws.width / 2, -ws.height / 2);
    final box = Offset.zero & ws;

    // Soft warm glow behind the finished word.
    if (glow > 0.01) {
      canvas.drawPath(
        mark.filled,
        Paint()
          ..color = const Color(0xFFFFE6C7).withValues(alpha: 0.5 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );
    }

    // Fill, revealed by a soft left → right edge.
    if (sweep > 0) {
      final edge = -0.08 + sweep * 1.16;
      canvas.drawPath(
        mark.filled,
        Paint()
          ..shader = LinearGradient(
            colors: const [Colors.white, Colors.white, Color(0x00FFFFFF)],
            stops: [0, (edge - 0.08).clamp(0.0, 1.0), edge.clamp(0.0, 1.0)],
          ).createShader(box),
      );
    }

    // Pen strokes fade once the ink has filled.
    final strokeAlpha = 1 - Curves.easeIn.transform(_seg(v, 0.62, 0.80));
    if (strokeAlpha > 0.02) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: strokeAlpha);
      final dust = Paint();
      final tipGlow = Paint();
      for (var i = 0; i < mark.metrics.length; i++) {
        final (a, b) = _windows[i];
        final p = Curves.easeInOutSine.transform(_seg(draw, a, b));
        if (p <= 0) continue;
        for (final m in mark.metrics[i]) {
          final len = m.length * p;
          canvas.drawPath(m.extractPath(0, len), stroke);
          if (p >= 1) continue;
          // Sparkle dust trailing the pen tip.
          for (var j = 1; j <= 10; j++) {
            final t = m.getTangentForOffset(math.max(0, len - j * 14.0));
            if (t == null) continue;
            final jitter = math.sin((len + j * 37) * 0.07) * 9;
            final normal = Offset(-t.vector.dy, t.vector.dx);
            final pos = t.position + normal * jitter;
            dust.color = const Color(0xFFFFF4E6).withValues(alpha: (1 - j / 11) * 0.85 * strokeAlpha);
            canvas.drawCircle(pos, 3.2 * (1 - j / 13), dust);
          }
          // Glowing tip.
          final tip = m.getTangentForOffset(len);
          if (tip != null) {
            final h = tip.position;
            tipGlow.shader = const RadialGradient(colors: [Color(0xDDFFF1DC), Color(0x00FFF1DC)]).createShader(Rect.fromCircle(center: h, radius: 30));
            canvas.drawCircle(h, 30, tipGlow);
            canvas.drawCircle(h, 6.5, Paint()..color = Colors.white);
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter old) => old.mark != mark;
}

/// Small spinner — only once "fanitt" is fully written and the app is still
/// waiting (e.g. slow network). Never on top of the animation.
class _Loader extends StatelessWidget {
  const _Loader({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ValueListenableBuilder<bool>(
        valueListenable: splashDone,
        builder: (context, done, _) => AnimatedOpacity(
          opacity: done ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.75)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.wifiOff, size: 18, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Try again',
            icon: AppIcons.refresh,
            onDark: true,
            onPressed: () => context.read<AuthBloc>().add(const AuthStarted()),
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final info = snapshot.data!;
        return Text(
          'v${info.version} (${info.buildNumber})',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
        );
      },
    );
  }
}