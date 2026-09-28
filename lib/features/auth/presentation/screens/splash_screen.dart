import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/sunrise_backdrop.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SunriseBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                // Splash-only logo artwork (other screens use FanittLogo).
                Image.asset(
                  'assets/images/splash_screenlogo.png',
                  height: 160,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                )
                    .animate()
                    .fadeIn(duration: 500.ms)
                    .scale(begin: const Offset(0.82, 0.82), duration: 650.ms, curve: Curves.easeOutBack),
                const Spacer(),
                SizedBox(
                  height: 132,
                  child: BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) => AnimatedSwitcher(
                      duration: AppDurations.normal,
                      child: state is AuthUnreachable
                          ? _Unreachable(key: const ValueKey('offline'), message: state.message)
                          : const _Loader(key: ValueKey('loading')),
                    ),
                  ),
                ),
                const _VersionLabel(),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.7)),
        ),
      ).animate(delay: 700.ms).fadeIn(duration: 300.ms),
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
              Icon(AppIcons.wifiOff, size: 18, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
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
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
        );
      },
    );
  }
}