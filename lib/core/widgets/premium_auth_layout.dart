import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/fanitt_logo.dart';

/// Shared premium layout for the auth screens (login, register, forgot /
/// reset password): a navy hero with drifting brand glows, logo and title,
/// and a rounded card that rises from the bottom holding the form.
///
/// [footer] sits at the bottom of the card on tall screens and scrolls with
/// the form on short ones or when the keyboard is open.
class PremiumAuthLayout extends StatelessWidget {
  const PremiumAuthLayout({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  /// Custom back action (e.g. go to the previous step). Defaults to popping.
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final heroHeight = (media.size.height * 0.32).clamp(220.0, 300.0).toDouble();
    final canGoBack = showBack && (onBack != null || Navigator.of(context).canPop());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          children: [
            const Positioned.fill(child: _HeroGlow()),
            CustomScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: heroHeight, child: _Hero(title: title, subtitle: subtitle)),
                      Expanded(
                        child: _Card(
                          bottomInset: media.padding.bottom,
                          footer: footer,
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (canGoBack)
              Positioned(
                top: media.padding.top + AppSpacing.xs,
                left: AppSpacing.sm,
                child: _GlassIconButton(
                  icon: AppIcons.back,
                  tooltip: 'Back',
                  onTap: onBack ?? () => Navigator.of(context).maybePop(),
                ).animate().fadeIn(duration: 300.ms),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fades and lifts form rows in one after another. Use [step] 0, 1, 2…
Widget authStagger(Widget child, int step) => child
    .animate(delay: (260 + step * 70).ms)
    .fadeIn(duration: 380.ms)
    .slideY(begin: 0.18, curve: Curves.easeOutCubic);

class _Hero extends StatelessWidget {
  const _Hero({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.huge, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FanittLogo(size: 40)
                .animate()
                .fadeIn(duration: 450.ms)
                .scale(begin: const Offset(0.85, 0.85), curve: Curves.easeOutBack, duration: 550.ms),
            const Spacer(),
            // Title/subtitle animate when they change (e.g. register steps).
            AnimatedSwitcher(
              duration: AppDurations.normal,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomLeft,
                children: [...previous, if (current != null) current],
              ),
              child: Column(
                key: ValueKey('$title|$subtitle'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.text.headlineLarge?.copyWith(color: Colors.white)),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: context.text.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
            ).animate(delay: 100.ms).fadeIn(duration: 450.ms).slideY(begin: 0.2, curve: Curves.easeOutCubic),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.bottomInset, required this.child, this.footer});

  final double bottomInset;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, -8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              width: 42,
              height: 5,
              decoration: BoxDecoration(color: palette.borderStrong, borderRadius: BorderRadius.circular(AppRadius.pill)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  if (footer != null) ...[
                    const Spacer(),
                    const SizedBox(height: AppSpacing.xl),
                    authStagger(footer!, 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.12, duration: 550.ms, curve: Curves.easeOutCubic);
  }
}

/// Two slowly drifting brand-colour glows behind the hero.
class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    Widget orb(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)]),
      ),
    );

    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -80,
          child: orb(AppColors.primary, 340)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .move(begin: Offset.zero, end: const Offset(-30, 24), duration: 6.seconds, curve: Curves.easeInOut),
        ),
        Positioned(
          top: 60,
          left: -120,
          child: orb(AppColors.sunrise, 260)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .move(begin: Offset.zero, end: const Offset(28, -18), duration: 7.seconds, curve: Curves.easeInOut)
              .fade(begin: 0.5, end: 0.8, duration: 7.seconds),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.1),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 20)),
        ),
      ),
    );
  }
}