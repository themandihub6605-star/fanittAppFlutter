import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../di/injection.dart';
import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';

/// "Update available" card for the home screens.
///
/// Only rendered while Google Play has a newer build — once the app is up
/// to date (or the user taps "Later") it returns an empty widget, so it
/// takes no space at all. While shown it keeps gently drawing attention:
/// a light sweep across the card, a breathing glow, a bouncing icon, a
/// pulsing "NEW" tag and a softly pulsing button.
class AppUpdateBanner extends StatefulWidget {
  const AppUpdateBanner({super.key});

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner> {
  final AppUpdateService _service = sl<AppUpdateService>();
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _service.check();
  }

  Future<void> _update() async {
    HapticFeedback.mediumImpact();
    setState(() => _updating = true);
    await _service.update();
    if (mounted) setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_service.updateAvailable, _service.dismissed]),
      builder: (context, _) {
        // Up to date or dismissed: nothing rendered, no space taken.
        if (!_service.updateAvailable.value || _service.dismissed.value) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _card(context),
        );
      },
    );
  }

  Widget _card(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);

    final content = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4511E), Color(0xFFEC2A78)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon: gentle bounce + a ring that keeps pulsing outward.
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2)),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(begin: 0.8, end: 1.35, duration: 1600.ms, curve: Curves.easeOut)
                    .fadeOut(duration: 1600.ms, curve: Curves.easeOut),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: const Icon(AppIcons.arrowCircleUp, color: Colors.white, size: 26),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(begin: 2, end: -3, duration: 900.ms, curve: Curves.easeInOut),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('Update available', style: context.text.titleSmall?.copyWith(color: Colors.white))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Text(
                        'NEW',
                        style: context.text.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(begin: 1, end: 1.12, duration: 700.ms, curve: Curves.easeInOut),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'A new version of Fanitt is ready with fixes and new features.',
                  style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    SizedBox(
                      height: 36,
                      child: FilledButton.icon(
                        onPressed: _updating ? null : _update,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                          disabledBackgroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                        ),
                        icon: _updating
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                            : const Icon(AppIcons.arrowCircleUp, size: 16),
                        label: Text('Update now', style: context.text.labelLarge?.copyWith(color: AppColors.primary)),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(begin: 1, end: 1.05, duration: 800.ms, curve: Curves.easeInOut),
                    const SizedBox(width: AppSpacing.xs),
                    TextButton(
                      onPressed: _service.dismiss,
                      style: TextButton.styleFrom(foregroundColor: Colors.white.withValues(alpha: 0.9)),
                      child: const Text('Later'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
    // Light sweep across the card every few seconds.
        .animate(onPlay: (c) => c.repeat())
        .shimmer(delay: 1800.ms, duration: 1400.ms, color: Colors.white.withValues(alpha: 0.35), angle: 0.5);

    // Breathing glow behind the card.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(borderRadius: radius, child: content),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1, end: 1.012, duration: 1500.ms, curve: Curves.easeInOut)
    // Entrance: drop in with a little bounce.
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.25, curve: Curves.easeOutBack, duration: 550.ms)
        .then(delay: 150.ms)
        .shake(hz: 3, rotation: 0.02, duration: 500.ms);
  }
}