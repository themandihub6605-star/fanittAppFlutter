// File: lib/features/auth/presentation/screens/welcome_screen.dart
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../legal/presentation/privacy_policy_screen.dart';
import '../widgets/fanitt_wordmark_path.dart';

const _liveRed = Color(0xFFFF3B5C);

/// Same background as the splash: orange → pink.
const _splashGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Pictures for the show (Unsplash, free to use). Each one falls back to a
/// grey icon if it can't load.
String _img(String id, {int w = 400}) => 'https://images.unsplash.com/photo-$id?auto=format&fit=crop&w=$w&q=70';
final _brandPic = _img('1556761175-5973dc0f32e7');
final _creatorPic = _img('1494790108377-be9c29b29330');
final _fanPics = [_img('1507003211169-0a1dd7228f2d'), _img('1438761681033-6461ffad8d80'), _img('1500648767791-00dcc994a43e'), _img('1534528741775-53994a69daeb')];
final _merchPic = _img('1521572163474-6864f9cf17ab');
final _digitalPic = _img('1544716278-ca5e3f4abd8c');
final _callPic = _img('1505740420928-5e560c06d30e');
List<String> get _allPics => [_brandPic, _creatorPic, ..._fanPics, _merchPic, _digitalPic, _callPic];

/// One scene of the welcome show.
class _Scene {
  const _Scene(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

const _scenes = [
  _Scene('Brands × Creators', 'Team up on campaigns — payment stays safe in escrow'),
  _Scene('Go live with fans', 'Fans join live streams, chat and send love'),
  _Scene('Sell to your fans', 'Merch, digital products and paid calls'),
  _Scene('Build a community', 'Posts, group chat and members-only lives'),
];

/// After onboarding: an auto-playing show of what Fanitt does (brand ×
/// creator deal, a live with fans, a store, a community), then
/// Log in | Create account side by side. Calm white look like the app.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  /// Time per scene.
  static const _sceneTime = Duration(milliseconds: 4200);

  late final AnimationController _c = AnimationController(vsync: this, duration: _sceneTime)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(_index + 1);
    });
  int _index = 0;

  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load every picture up front so scenes never show blanks.
    if (_precached) return;
    _precached = true;
    for (final url in _allPics) {
      precacheImage(CachedNetworkImageProvider(url), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (!mounted) return;
    setState(() => _index = i % _scenes.length);
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scene = _scenes[_index];
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4511E),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: _splashGradient),
          child: Stack(
            children: [
              // Two soft lights drifting slowly — same as the splash.
              Positioned(
                left: -140,
                top: -170,
                child: IgnorePointer(
                  child: Container(
                    width: 440,
                    height: 440,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x45FFE0B0), Color(0x00FFE0B0)])),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).move(begin: Offset.zero, end: const Offset(40, 30), duration: 3200.ms, curve: Curves.easeInOutSine),
                ),
              ),
              Positioned(
                right: -160,
                top: 160,
                child: IgnorePointer(
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x33FF8FB8), Color(0x00FF8FB8)])),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).move(begin: Offset.zero, end: const Offset(-36, -28), duration: 3600.ms, curve: Curves.easeInOutSine),
                ),
              ),
              Column(
                children: [
                  // ── Top: the same white "fanitt" as the splash ──
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: const _Wordmark(height: 30).animate().fadeIn(duration: 500.ms).slideY(begin: -0.3, curve: Curves.easeOutCubic),
                    ),
                  ),

                  // ── The show, on a soft glowing stage ──
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _go(_index + 1);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Stage: a big soft light and a slowly turning ring.
                          IgnorePointer(
                            child: Container(
                              width: 330,
                              height: 330,
                              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)])),
                            ),
                          ),
                          IgnorePointer(
                            child: const SizedBox(width: 300, height: 300, child: CustomPaint(painter: _RingPainter()))
                                .animate(onPlay: (c) => c.repeat())
                                .rotate(duration: 24.seconds),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 450),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: child),
                            ),
                            child: KeyedSubtree(
                              key: ValueKey(_index),
                              child: AnimatedBuilder(
                                animation: _c,
                                // Each scene is laid out on a fixed 320×340 canvas and
                                // scaled down on small phones — never overlaps or overflows.
                                builder: (context, _) => Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: SizedBox(
                                        width: 320,
                                        height: 340,
                                        child: switch (_index) {
                                          0 => _CollabScene(t: _c.value),
                                          1 => _LiveScene(t: _c.value),
                                          2 => _StoreScene(t: _c.value),
                                          _ => _CommunityScene(t: _c.value),
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom sheet: progress, caption, buttons ──
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(AppSpacing.gutter + 2, 18, AppSpacing.gutter + 2, 14 + bottomInset),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: const [BoxShadow(color: Color(0x33101828), blurRadius: 30, offset: Offset(0, -8))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Scene pills — the current one fills up in orange.
                        AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _scenes.length; i++)
                                GestureDetector(
                                  onTap: () => _go(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    width: i == _index ? 34 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: i < _index ? AppColors.primary.withValues(alpha: 0.35) : palette.border,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    child: i == _index
                                        ? FractionallySizedBox(
                                      widthFactor: _c.value.clamp(0.08, 1.0),
                                      child: Container(decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99))),
                                    )
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Caption for the scene
                        SizedBox(
                          height: 82,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
                            ),
                            child: Column(
                              key: ValueKey(scene.title),
                              children: [
                                Text(scene.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.7, height: 1.15, color: palette.textPrimary)),
                                const SizedBox(height: 6),
                                Text(scene.subtitle, maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.45, color: palette.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Log in | Create account — same row
                        Row(
                          children: [
                            Expanded(child: AppButton.secondary(label: 'Log in', height: 52, onPressed: () => context.push(AppRoutes.login))),
                            const SizedBox(width: 10),
                            Expanded(child: AppButton(label: 'Create account', height: 52, onPressed: () => context.push(AppRoutes.register))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const _LegalLine(),
                      ],
                    ),
                  ).animate().slideY(begin: 0.25, duration: 500.ms, curve: Curves.easeOutCubic).fadeIn(duration: 350.ms),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White "fanitt" from the splash's vector outlines.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final width = height * kFanittWordmarkSize.width / kFanittWordmarkSize.height;
    return SizedBox(width: width, height: height, child: const CustomPaint(painter: _WordmarkPainter()));
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter();

  static final Path _path = () {
    final p = Path()..fillType = PathFillType.evenOdd;
    for (final c in fanittWordmarkContours()) {
      p.addPath(c, Offset.zero);
    }
    return p;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / kFanittWordmarkSize.width;
    canvas.save();
    canvas.scale(k);
    canvas.drawPath(_path, Paint()..color = const Color(0x33101828)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawPath(_path, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) => false;
}

/// Thin dashed ring for the stage (it turns slowly).
class _RingPainter extends CustomPainter {
  const _RingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.32);
    const dashes = 48;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi / dashes * 0.9, false, paint);
    }
    // A small dot riding on the ring.
    canvas.drawCircle(c + Offset(r, 0), 4, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Helpers for the scenes
// ---------------------------------------------------------------------------

/// 0 → 1 inside [a, b] of the scene time, eased.
double _p(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// Round photo (or grey icon if there's no picture / it can't load).
class _Face extends StatelessWidget {
  const _Face({required this.icon, this.size = 56, this.ring, this.url});

  final IconData icon;
  final double size;
  final Color? ring;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fallback = ColoredBox(color: palette.surfaceMuted, child: Center(child: Icon(icon, size: size * 0.42, color: palette.textPrimary)));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: ring ?? palette.surface, width: ring == null ? 3 : 2.5),
        boxShadow: const [BoxShadow(color: Color(0x14101828), blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: ClipOval(
        child: url == null
            ? fallback
            : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 200), placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback),
      ),
    );
  }
}

/// Rounded photo tile (products).
class _Tile extends StatelessWidget {
  const _Tile({required this.url, required this.icon, this.size = 64});

  final String url;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fallback = ColoredBox(color: palette.surfaceMuted, child: Center(child: Icon(icon, size: 22, color: palette.textPrimary)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, fadeInDuration: const Duration(milliseconds: 200), placeholder: (_, _) => fallback, errorWidget: (_, _, _) => fallback),
      ),
    );
  }
}

/// White pill with an icon — the "status" bubbles in the scenes.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.icon, required this.text, this.iconColor, this.show = 1});

  final IconData icon;
  final String text;
  final Color? iconColor;

  /// 0 hidden → 1 shown (fades and rises in).
  final double show;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: show,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - show)),
        child: Transform.scale(
          scale: 0.92 + 0.08 * show,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: palette.border.withValues(alpha: 0.8)),
              boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: (iconColor ?? AppColors.primary).withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 14, color: iconColor ?? AppColors.primary),
                ),
                const SizedBox(width: 7),
                Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small labelled card (Brand / Creator) for the collab scene.
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.label, required this.hint, this.url});

  final IconData icon;
  final String label;
  final String hint;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 118,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
        boxShadow: const [BoxShadow(color: Color(0x14101828), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Face(icon: icon, size: 56, url: url),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
          Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 1 — a brand and a creator meet, shake hands, escrow, delivery
// ---------------------------------------------------------------------------

class _CollabScene extends StatelessWidget {
  const _CollabScene({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final slide = _p(t, 0.0, 0.28);
    final line = _p(t, 0.22, 0.42);
    final shake = _p(t, 0.40, 0.55, Curves.easeOutBack);
    return LayoutBuilder(
      builder: (context, box) {
        final gap = (box.maxWidth - 2 * 118 - 40).clamp(20.0, 120.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Brand ← → Creator
            Positioned(
              top: box.maxHeight * 0.06,
              child: SizedBox(
                width: 236 + gap,
                child: Row(
                  children: [
                    Transform.translate(
                      offset: Offset(-60 * (1 - slide), 0),
                      child: Opacity(opacity: slide, child: _RoleCard(icon: AppIcons.brand, label: 'Brand', hint: 'Posts a campaign', url: _brandPic)),
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Dotted link growing from both sides
                          FractionallySizedBox(
                            widthFactor: line,
                            child: Row(
                              children: [
                                for (var i = 0; i < 8; i++) Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 2), color: Colors.white.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          // Handshake pops in the middle
                          Transform.scale(
                            scale: shake,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.surface, width: 3),
                                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
                              ),
                              child: const Icon(AppIcons.handshake, size: 19, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(60 * (1 - slide), 0),
                      child: Opacity(opacity: slide, child: _RoleCard(icon: AppIcons.creator, label: 'Creator', hint: 'Sends a proposal', url: _creatorPic)),
                    ),
                  ],
                ),
              ),
            ),
            // The deal, step by step
            Positioned(
              bottom: box.maxHeight * 0.06,
              child: Column(
                children: [
                  _Bubble(icon: AppIcons.paperPlane, text: 'Proposal accepted', show: _p(t, 0.52, 0.62)),
                  const SizedBox(height: 8),
                  _Bubble(icon: AppIcons.lock, text: 'Payment locked in escrow', show: _p(t, 0.62, 0.72)),
                  const SizedBox(height: 8),
                  _Bubble(icon: AppIcons.checkCircle, text: 'Content delivered · Paid', iconColor: AppColors.success, show: _p(t, 0.74, 0.84)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 2 — a creator is live, fans join, hearts float up
// ---------------------------------------------------------------------------

class _LiveScene extends StatelessWidget {
  const _LiveScene({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final open = _p(t, 0.0, 0.22);
    return LayoutBuilder(
      builder: (context, box) {
        final screenW = math.min(box.maxWidth * 0.62, 230.0);
        final screenH = math.min(box.maxHeight * 0.78, screenW * 1.35);
        return Stack(
          alignment: Alignment.center,
          children: [
            // The "stream"
            Transform.scale(
              scale: 0.9 + 0.1 * open,
              child: Opacity(
                opacity: open,
                child: Container(
                  width: screenW,
                  height: screenH,
                  // Brand orange — the "stream" in the app's own colour.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF7A45), AppColors.primary, Color(0xFFD9420F)]),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
                    boxShadow: const [BoxShadow(color: Color(0x40101828), blurRadius: 28, offset: Offset(0, 12))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Two soft lights drifting — gives the orange some depth.
                      Positioned(
                        left: -60 + 20 * math.sin(t * math.pi),
                        top: -70,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFE0B0), Color(0x00FFE0B0)])),
                        ),
                      ),
                      Positioned(
                        right: -70,
                        bottom: -60 + 20 * math.sin(t * math.pi),
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)])),
                        ),
                      ),
                      // Pulse rings around the creator
                      for (var k = 0; k < 2; k++)
                        Builder(builder: (_) {
                          final ph = (t * 1.5 + k * 0.5) % 1;
                          return Container(
                            width: 70 + 80 * ph,
                            height: 70 + 80 * ph,
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.35 * (1 - ph)), width: 2)),
                          );
                        }),
                      _Face(icon: AppIcons.creator, size: 76, ring: Colors.white, url: _creatorPic),
                      // LIVE
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 8)),
                                child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle)),
                              ),
                              const SizedBox(width: 5),
                              const Text('LIVE', style: TextStyle(color: _liveRed, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                      ),
                      // Hearts floating up on the right
                      for (var k = 0; k < 5; k++)
                        Builder(builder: (_) {
                          final ph = (t * 1.4 + k * 0.2) % 1;
                          final visible = t > 0.25 ? 1.0 : 0.0;
                          return Positioned(
                            right: 16 + 10 * math.sin((ph + k) * math.pi * 2),
                            bottom: 20 + (screenH * 0.6) * ph,
                            child: Opacity(
                              opacity: visible * (1 - ph),
                              child: Icon(AppIcons.heartFilled, size: 16 + (k % 3) * 4.0, color: k.isEven ? Colors.white : const Color(0xFFFFD1DC)),
                            ),
                          );
                        }),
                      // Chat lines at the bottom
                      Positioned(
                        left: 12,
                        bottom: 14,
                        right: 48,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ChatLine(text: 'A fan joined 👋', show: _p(t, 0.30, 0.40)),
                            const SizedBox(height: 6),
                            _ChatLine(text: 'Love this! ❤️', show: _p(t, 0.48, 0.58)),
                            const SizedBox(height: 6),
                            _ChatLine(text: 'Sent a gift 🎁', show: _p(t, 0.66, 0.76)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Fans hopping in from the left
            Positioned(
              left: math.max(8, (box.maxWidth - screenW) / 2 - 34),
              top: box.maxHeight * 0.22,
              child: Column(
                children: [
                  for (var k = 0; k < 3; k++) ...[
                    Builder(builder: (_) {
                      final s = _p(t, 0.28 + k * 0.12, 0.40 + k * 0.12, Curves.easeOutBack);
                      return Transform.scale(scale: s, child: _Face(icon: AppIcons.user, size: 40, ring: palette.surface, url: _fanPics[k]));
                    }),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.text, required this.show});

  final String text;
  final double show;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: show,
      child: Transform.translate(
        offset: Offset(-12 * (1 - show), 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 3 — a creator's store: product, buy, order placed
// ---------------------------------------------------------------------------

class _StoreScene extends StatelessWidget {
  const _StoreScene({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = [
      (AppIcons.package, 'Merch', _merchPic),
      (AppIcons.download, 'Digital', _digitalPic),
      (AppIcons.phone, 'Paid call', _callPic),
    ];
    final picked = t < 0.45 ? -1 : 0;
    return LayoutBuilder(
      builder: (context, box) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: box.maxHeight * 0.04,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  // Store header
                  Opacity(
                    opacity: _p(t, 0, 0.18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Face(icon: AppIcons.storeFilled, size: 44, url: _creatorPic),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Creator’s store', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                            Text('Open · taking orders', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Three products pop in
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final (i, it) in items.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Builder(builder: (_) {
                          final s = _p(t, 0.10 + i * 0.08, 0.28 + i * 0.08, Curves.easeOutBack);
                          final selected = picked == i;
                          return Transform.scale(
                            scale: s * (selected ? 1.06 : 1),
                            child: Container(
                              width: 88,
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: selected ? AppColors.primary : palette.border.withValues(alpha: 0.8), width: selected ? 1.8 : 1),
                                boxShadow: const [BoxShadow(color: Color(0x12101828), blurRadius: 14, offset: Offset(0, 6))],
                              ),
                              child: Column(
                                children: [
                                  _Tile(url: it.$3, icon: it.$1, size: 68),
                                  const SizedBox(height: 8),
                                  Text(it.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // A fan's tap, then the order
            Positioned(
              bottom: box.maxHeight * 0.04,
              child: Column(
                children: [
                  _Bubble(icon: AppIcons.user, text: 'A fan is buying', show: _p(t, 0.40, 0.50)),
                  const SizedBox(height: 8),
                  _Bubble(icon: AppIcons.wallet, text: 'Paid securely', show: _p(t, 0.56, 0.66)),
                  const SizedBox(height: 8),
                  _Bubble(icon: AppIcons.checkCircle, text: 'Order placed · You earned', iconColor: AppColors.success, show: _p(t, 0.72, 0.82)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Scene 4 — a community: members join, chat messages come in
// ---------------------------------------------------------------------------

class _CommunityScene extends StatelessWidget {
  const _CommunityScene({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final messages = [
      (_creatorPic, 'Welcome to the community! 🎉', true),
      (_fanPics[1], 'So happy to be here', false),
      (_fanPics[0], 'When is the next live?', false),
      (_creatorPic, 'Members-only live on Sunday 🔒', true),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            children: [
              // Header: icon, name, members joining
              Opacity(
                opacity: _p(t, 0, 0.18),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x26101828), blurRadius: 12, offset: Offset(0, 4))]),
                      child: const Icon(AppIcons.users, size: 20, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your community', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('Posts · Group chat · Lives', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                    // Members stacking up
                    SizedBox(
                      width: 26 + 18.0 * 3,
                      height: 26,
                      child: Stack(
                        children: [
                          for (var k = 0; k < 4; k++)
                            Positioned(
                              left: 18.0 * k,
                              child: Transform.scale(
                                scale: _p(t, 0.08 + k * 0.07, 0.2 + k * 0.07, Curves.easeOutBack),
                                child: _Face(icon: AppIcons.user, size: 26, url: _fanPics[k]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              // Messages
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final (i, m) in messages.indexed) ...[
                      Builder(builder: (_) {
                        final s = _p(t, 0.22 + i * 0.14, 0.32 + i * 0.14);
                        final mine = m.$3;
                        return Opacity(
                          opacity: s,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - s)),
                            child: Row(
                              mainAxisAlignment: mine ? MainAxisAlignment.start : MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (mine) ...[_Face(icon: AppIcons.creator, size: 28, url: m.$1), const SizedBox(width: 6)],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: mine ? Colors.white : Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(mine ? 4 : 16),
                                        bottomRight: Radius.circular(mine ? 16 : 4),
                                      ),
                                      border: mine ? null : Border.all(color: Colors.white.withValues(alpha: 0.45)),
                                    ),
                                    child: Text(m.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: mine ? palette.textPrimary : Colors.white)),
                                  ),
                                ),
                                if (!mine) ...[const SizedBox(width: 6), _Face(icon: AppIcons.user, size: 28, url: m.$1)],
                              ],
                            ),
                          ),
                        );
                      }),
                      if (i < messages.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Legal line
// ---------------------------------------------------------------------------

/// "By continuing you agree to the Terms of use and Privacy policy."
class _LegalLine extends StatefulWidget {
  const _LegalLine();

  @override
  State<_LegalLine> createState() => _LegalLineState();
}

class _LegalLineState extends State<_LegalLine> {
  // Opened directly (not through the router) so they work before log-in too.
  late final _terms = TapGestureRecognizer()..onTap = () => _open(const TermsOfUseScreen());
  late final _privacy = TapGestureRecognizer()..onTap = () => _open(const PrivacyPolicyScreen());

  void _open(Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final link = TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: palette.border);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 11.5, height: 1.45, color: palette.textSecondary),
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'Terms of use', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}