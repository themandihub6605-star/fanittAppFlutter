import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/storage/onboarding_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/fanitt_logo.dart';

class _Page {
  const _Page({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.centerIcon,
    required this.chips,
    required this.imageUrl,
  });

  final String eyebrow;
  final String title;
  final String body;
  final IconData centerIcon;
  final List<(IconData, String)> chips;

  /// Full-screen background photo (Unsplash, free to use).
  final String imageUrl;
}


const _pages = [
  _Page(
    eyebrow: 'For creators',
    title: 'Get paid to\ncreate what you love',
    body: 'Discover campaigns from brands, send your proposal and turn your content into income.',
    centerIcon: AppIcons.creator,
    chips: [
      (AppIcons.campaigns, 'Brand campaigns'),
      (AppIcons.paperPlane, 'Send proposals'),
      (AppIcons.wallet, 'Get paid'),
    ],
    // Creator with a camera
    imageUrl: 'https://plus.unsplash.com/premium_photo-1679079456789-15b8e1deccee?q=80&w=688&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
  ),
  _Page(
    eyebrow: 'For brands',
    title: 'Find creators who\nfit your brand',
    body: 'Post a campaign in minutes, review proposals and hire the right creators for your audience.',
    centerIcon: AppIcons.brand,
    chips: [
      (AppIcons.megaphoneAlt, 'Post a campaign'),
      (AppIcons.users, 'Review proposals'),
      (AppIcons.handshake, 'Hire creators'),
    ],
    // Brand team planning a campaign
    imageUrl: 'https://images.unsplash.com/photo-1556761175-5973dc0f32e7?auto=format&fit=crop&w=1600&q=80',
  ),
  _Page(
    eyebrow: 'Built on trust',
    title: 'Every payment\nprotected in escrow',
    body: 'Money is locked before work starts and released when work is approved. Verified profiles, chat and delivery in one place.',
    centerIcon: AppIcons.shieldCheck,
    chips: [
      (AppIcons.lock, 'Escrow protected'),
      (AppIcons.sealCheck, 'Verified profiles'),
      (AppIcons.messages, 'Chat & deliver'),
    ],
    // Deal closed — handshake
    imageUrl: 'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?auto=format&fit=crop&w=1600&q=80',
  ),
];

/// Three intro screens shown once, after the splash, before sign-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load all three backgrounds up front so swiping never shows a blank.
    if (_precached) return;
    _precached = true;
    for (final page in _pages) {
      precacheImage(CachedNetworkImageProvider(page.imageUrl), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.lightImpact();
    await OnboardingStore.markSeen();
    if (mounted) context.go(AppRoutes.welcome);
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    HapticFeedback.selectionClick();
    _controller.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _Background(imageUrl: _pages[_index].imageUrl),
            SafeArea(
              child: Column(
                children: [
                  // Top bar: logo + skip
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.sm, 0),
                    child: Row(
                      children: [
                        const FanittLogo(size: 34),
                        const Spacer(),
                        AnimatedOpacity(
                          opacity: _isLast ? 0 : 1,
                          duration: AppDurations.normal,
                          child: TextButton(
                            onPressed: _isLast ? null : _finish,
                            style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.7)),
                            child: const Text('Skip'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Pages
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _OnboardingPage(page: _pages[i], active: i == _index),
                    ),
                  ),

                  // Dots + button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _pages.length; i++)
                              AnimatedContainer(
                                duration: AppDurations.normal,
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _index ? 24 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  gradient: i == _index ? AppColors.sunriseGradient : null,
                                  color: i == _index ? null : Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppButton(
                          label: _isLast ? 'Get started' : 'Next',
                          icon: _isLast ? null : AppIcons.arrowRightSimple,
                          onPressed: _next,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-bleed photo that cross-fades between pages, with a slow zoom and a
/// dark navy gradient on top so text stays readable.
class _Background extends StatelessWidget {
  const _Background({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
          child: CachedNetworkImage(
            key: ValueKey(imageUrl),
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 400),
            placeholder: (_, _) => const ColoredBox(color: AppColors.navy),
            errorWidget: (_, _, _) => const ColoredBox(color: AppColors.navy),
          )
              .animate(key: ValueKey('zoom-$imageUrl'))
              .scale(begin: const Offset(1.12, 1.12), end: const Offset(1, 1), duration: 9.seconds, curve: Curves.easeOut),
        ),
        // Readability gradient: lighter at the top, solid navy behind the text.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.navy.withValues(alpha: 0.55),
                AppColors.navy.withValues(alpha: 0.62),
                AppColors.navy.withValues(alpha: 0.9),
                AppColors.navy,
              ],
              stops: const [0, 0.35, 0.62, 0.85],
            ),
          ),
        ),
        // Brand glow rising from the bottom.
        Positioned(
          left: -120,
          right: -120,
          bottom: -280,
          height: 480,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.navy.withValues(alpha: 0),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.page, required this.active});

  final _Page page;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = (constraints.maxHeight * 0.42).clamp(180.0, 320.0).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: artSize,
                height: artSize,
                child: _Illustration(page: page, size: artSize, active: active),
              ),
              const Spacer(),
              if (active) ...[
                Text(
                  page.eyebrow.toUpperCase(),
                  style: context.text.labelMedium?.copyWith(color: AppColors.sunrise, letterSpacing: 1.4),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.4, curve: Curves.easeOutCubic),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: context.text.headlineLarge?.copyWith(color: Colors.white, height: 1.15),
                ).animate(delay: 80.ms).fadeIn(duration: 400.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic),
                const SizedBox(height: AppSpacing.md),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: context.text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                ).animate(delay: 160.ms).fadeIn(duration: 400.ms),
              ] else
                const SizedBox(height: 160),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }
}

/// Glowing badge in the centre with three feature chips floating around it.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.page, required this.size, required this.active});

  final _Page page;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.34;
    // Chip positions around the badge: top-left, right, bottom-left.
    final positions = [
      Offset(size * 0.02, size * 0.12),
      Offset(size * 0.46, size * 0.40),
      Offset(size * 0.06, size * 0.72),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Soft rings
        for (final (i, scale) in [1.0, 0.74, 0.5].indexed)
          Center(
            child: Container(
              width: size * scale,
              height: size * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06 + i * 0.03)),
              ),
            ),
          ),

        // Center badge
        Center(
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              gradient: AppColors.sunriseGradient,
              borderRadius: BorderRadius.circular(badge * 0.3),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: badge * 0.6, offset: Offset(0, badge * 0.12)),
              ],
            ),
            child: Icon(page.centerIcon, color: Colors.white, size: badge * 0.46),
          )
              .animate(target: active ? 1 : 0)
              .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1), duration: 550.ms, curve: Curves.easeOutBack)
              .fadeIn(duration: 350.ms),
        ),

        // Floating chips
        for (final (i, chip) in page.chips.indexed)
          Positioned(
            left: positions[i].dx,
            top: positions[i].dy,
            child: _FeatureChip(icon: chip.$1, label: chip.$2)
                .animate(target: active ? 1 : 0, delay: (200 + i * 120).ms)
                .fadeIn(duration: 400.ms)
                .slideX(begin: i.isEven ? -0.15 : 0.15, curve: Curves.easeOutCubic)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: -3, end: 3, duration: (1800 + i * 300).ms, curve: Curves.easeInOut),
          ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: AppColors.sunrise),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: context.text.labelMedium?.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}