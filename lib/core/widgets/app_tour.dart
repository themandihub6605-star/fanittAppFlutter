// File: lib/core/widgets/app_tour.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/injection.dart';
import '../theme/app_colors.dart';

/// Things the first-time tour points at. Each key is put on one widget
/// (nav tabs in RoleShell, search + quick actions on the Home screens).
abstract final class TourTargets {
  static final List<GlobalKey> _tabs = List.generate(5, (i) => GlobalKey(debugLabel: 'tour-tab-$i'));

  /// Bottom bar tab [i].
  static GlobalKey tab(int i) => _tabs[i];

  /// Home → search bar.
  static final GlobalKey search = GlobalKey(debugLabel: 'tour-search');

  /// Home → Quick actions grid.
  static final GlobalKey quickActions = GlobalKey(debugLabel: 'tour-quick-actions');
}

/// One stop of the tour.
class TourStep {
  const TourStep({required this.target, required this.title, required this.body});

  final GlobalKey target;
  final String title;
  final String body;
}

/// First-time walkthrough: dims the screen, cuts a glowing hole around one
/// thing at a time, points at it with a curved arrow and explains it.
/// Previous / Next / Skip. Shown once per user per role (kept on the phone).
abstract final class AppTour {
  static bool _running = false;

  /// True while the tour is on screen (so other popups wait).
  static bool get isRunning => _running;

  static String _key(String id) => 'app_tour_seen_$id';

  /// Has this tour already been shown?
  static bool seen(String id) {
    try {
      return sl<SharedPreferences>().getBool(_key(id)) ?? false;
    } catch (_) {
      return true; // can't read → don't bother the user
    }
  }

  static Future<void> _markSeen(String id) async {
    try {
      await sl<SharedPreferences>().setBool(_key(id), true);
    } catch (_) {}
  }

  /// Shows the tour if it hasn't been seen. Steps whose target isn't on
  /// screen are skipped. Needs at least 2 visible steps.
  static Future<void> start(BuildContext context, {required String id, required List<TourStep> steps}) async {
    if (_running || seen(id)) return;
    // Home may still be loading — wait a little (up to ~4 s) for every target.
    for (var tries = 0; tries < 8; tries++) {
      if (steps.every((s) => _rectOf(s.target) != null)) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!context.mounted || _running) return;
    }
    final visible = [for (final s in steps) if (_rectOf(s.target) != null) s];
    if (visible.length < 2 || !context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _running = true;
    await _markSeen(id);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: visible,
        onDone: () {
          entry.remove();
          _running = false;
        },
      ),
    );
    overlay.insert(entry);
  }

  static Rect? _rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    final r = topLeft & box.size;
    if (r.width < 4 || r.height < 4) return null;
    return r;
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onDone});

  final List<TourStep> steps;
  final VoidCallback onDone;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
  int _index = 0;
  Rect _from = Rect.zero;
  Rect _to = Rect.zero;

  @override
  void initState() {
    super.initState();
    final r = _rect(0);
    // Start from a big soft circle and close in on the first target.
    _from = Rect.fromCenter(center: r.center, width: r.width * 2.4, height: r.height * 2.4);
    _to = r;
    _move.forward(from: 0);
  }

  @override
  void dispose() {
    _move.dispose();
    _fade.dispose();
    super.dispose();
  }

  Rect _rect(int i) => (AppTour._rectOf(widget.steps[i].target) ?? Rect.zero).inflate(8);

  Rect get _hole => Rect.lerp(_from, _to, Curves.easeInOutCubic.transform(_move.value)) ?? _to;

  Future<void> _goTo(int i) async {
    if (i < 0) return;
    if (i >= widget.steps.length) return _finish();
    HapticFeedback.selectionClick();
    await _fade.reverse();
    if (!mounted) return;
    setState(() {
      _from = _hole;
      _index = i;
      _to = _rect(i);
    });
    _move.forward(from: 0);
    _fade.forward();
  }

  Future<void> _finish() async {
    HapticFeedback.lightImpact();
    await _fade.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final step = widget.steps[_index];
    final last = _index == widget.steps.length - 1;
    final target = _to;
    // Text above the target when it's in the lower half, below otherwise.
    final above = target.center.dy > size.height * 0.5;
    const gap = 64.0;

    final text = FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: Tween(begin: Offset(0, above ? 0.06 : -0.06), end: Offset.zero).animate(CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_index + 1} of ${widget.steps.length}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            Text(step.title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, height: 1.18, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(step.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16, height: 1.4)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_index > 0) ...[
                  _TourButton(label: 'Previous', icon: Icons.chevron_left_rounded, leading: true, filled: false, onTap: () => _goTo(_index - 1)),
                  const SizedBox(width: 12),
                ],
                _TourButton(label: last ? 'Got it' : 'Next', icon: last ? Icons.check_rounded : Icons.chevron_right_rounded, filled: true, onTap: () => _goTo(_index + 1)),
              ],
            ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Dim + hole + ring + arrow
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // block taps on the app underneath
                child: AnimatedBuilder(
                  animation: Listenable.merge([_move, _fade]),
                  builder: (context, _) => CustomPaint(
                    painter: _SpotlightPainter(
                      hole: _hole,
                      arrowFrom: Offset(
                        target.center.dx > size.width / 2 ? size.width * 0.42 : size.width * 0.58,
                        above ? target.top - gap + 6 : target.bottom + gap - 6,
                      ),
                      arrowTo: Offset(target.center.dx, above ? target.top - 6 : target.bottom + 6),
                      arrowOpacity: _fade.value * _move.value,
                    ),
                  ),
                ),
              ),
            ),
            // Skip
            Positioned(
              top: pad.top + 8,
              right: 12,
              child: FadeTransition(
                opacity: _fade,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(foregroundColor: Colors.white, shape: const StadiumBorder(), backgroundColor: Colors.white.withValues(alpha: 0.12)),
                  child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            // Text block
            Positioned(
              left: 28,
              right: 28,
              top: above ? null : math.min(target.bottom + gap, size.height - 260),
              bottom: above ? math.min(size.height - target.top + gap, size.height - pad.top - 260) : null,
              child: text,
            ),
          ],
        ),
      ),
    );
  }
}

class _TourButton extends StatelessWidget {
  const _TourButton({required this.label, required this.icon, required this.filled, required this.onTap, this.leading = false});

  final String label;
  final IconData icon;
  final bool filled;
  final bool leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.primary;
    final iconW = Icon(icon, size: 20, color: fg);
    final textW = Text(label, style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w800));
    return Material(
      color: filled ? AppColors.primary : Colors.white,
      shape: const StadiumBorder(),
      elevation: 3,
      shadowColor: const Color(0x55101828),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leading ? 14 : 22, 13, leading ? 22 : 16, 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: leading ? [iconW, const SizedBox(width: 4), textW] : [textW, const SizedBox(width: 4), iconW],
          ),
        ),
      ),
    );
  }
}

/// Dark veil with a rounded hole, a glowing white ring and a curved arrow.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.arrowFrom, required this.arrowTo, required this.arrowOpacity});

  final Rect hole;
  final Offset arrowFrom;
  final Offset arrowTo;
  final double arrowOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(math.min(26, math.min(hole.width, hole.height) / 2));
    final rrect = RRect.fromRectAndRadius(hole, radius);

    // Veil with the hole cut out (deep navy, never black).
    final veil = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rrect));
    canvas.drawPath(veil, Paint()..color = const Color(0xD90A1325));

    // Soft glow + white ring around the hole.
    canvas.drawRRect(
      rrect.inflate(4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      rrect.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.95),
    );

    // Curved arrow from the text to the hole.
    if (arrowOpacity <= 0.02) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: arrowOpacity);
    final mid = Offset((arrowFrom.dx + arrowTo.dx) / 2, (arrowFrom.dy + arrowTo.dy) / 2);
    final bend = (arrowTo.dx - arrowFrom.dx).sign == 0 ? 1.0 : (arrowTo.dx - arrowFrom.dx).sign;
    final control = mid + Offset(28 * bend, -(arrowTo.dy - arrowFrom.dy).sign * 18);
    final path = Path()
      ..moveTo(arrowFrom.dx, arrowFrom.dy)
      ..quadraticBezierTo(control.dx, control.dy, arrowTo.dx, arrowTo.dy);
    canvas.drawPath(path, paint);
    // Arrow head along the curve's end direction.
    final dir = (arrowTo - control);
    final len = dir.distance == 0 ? 1.0 : dir.distance;
    final u = Offset(dir.dx / len, dir.dy / len);
    final n = Offset(-u.dy, u.dx);
    const head = 12.0;
    canvas.drawLine(arrowTo, arrowTo - u * head + n * head * 0.7, paint);
    canvas.drawLine(arrowTo, arrowTo - u * head - n * head * 0.7, paint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.arrowOpacity != arrowOpacity || old.arrowFrom != arrowFrom || old.arrowTo != arrowTo;
}