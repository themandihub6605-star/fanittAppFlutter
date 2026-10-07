import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../profile/presentation/edit_profile_screen.dart';
import '../bloc/auth_bloc.dart';

/// Shown while a creator / brand / agency profile waits for admin review,
/// or after the admin rejected it. Rejected: the admin's note plus
/// "Edit & resubmit", which opens the profile form; saving it with
/// "Save & submit for review" sends it back to the admin.
class VerificationStatusScreen extends StatefulWidget {
  const VerificationStatusScreen({super.key});

  @override
  State<VerificationStatusScreen> createState() => _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends State<VerificationStatusScreen> {
  String _reason = '';
  bool _checking = false;
  Route<void>? _editRoute;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadReason();
    // While under review, quietly check every 60s so approval opens the app.
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _status == VerificationStatus.pending && _editRoute == null) {
        context.read<AuthBloc>().add(const AuthRefreshRequested());
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  AuthAuthenticated? get _auth {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s : null;
  }

  VerificationStatus? get _status => _auth?.user.profileStatus;

  /// The admin's note comes from the role's own profile.
  Future<void> _loadReason() async {
    final role = _auth?.user.role;
    final path = switch (role) {
      UserRole.creator => '/creators/me',
      UserRole.brand => '/brands/me',
      UserRole.agency => '/agency/me',
      _ => null,
    };
    if (path == null) return;
    try {
      final reason = (await sl<ApiClient>().get(path, parser: (d) => J.str(J.asMap(d), 'rejectionReason'))).data;
      if (mounted) setState(() => _reason = reason.trim());
    } catch (_) {
      // Reason is optional — the screen still works without it.
    }
  }

  Future<void> _checkStatus() async {
    HapticFeedback.selectionClick();
    setState(() => _checking = true);
    context.read<AuthBloc>().add(const AuthRefreshRequested());
    await _loadReason();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _checking = false);
    final status = _status;
    if (status == VerificationStatus.pending) AppSnackbar.info(context, 'Still under review — we’ll notify you as soon as it’s done.');
  }

  /// Opens the profile form on top of this screen (the router keeps
  /// unapproved accounts here, so it isn't a normal route push).
  Future<void> _editAndResubmit() async {
    HapticFeedback.selectionClick();
    final route = MaterialPageRoute<void>(builder: (_) => const EditProfileScreen());
    _editRoute = route;
    await Navigator.of(context).push(route);
    _editRoute = null;
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthRefreshRequested());
    _loadReason();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        // Submitted from the form → close it and show "under review".
        if (state is AuthAuthenticated && state.user.profileStatus == VerificationStatus.pending) {
          final route = _editRoute;
          if (route != null && route.isActive) {
            Navigator.of(context).removeRoute(route);
            _editRoute = null;
            AppSnackbar.success(context, 'Submitted — our team will review it again.');
          }
        }
      },
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        final rejected = user?.profileStatus == VerificationStatus.rejected;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xxl, AppSpacing.gutter, AppSpacing.xl),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: rejected
                      ? _Rejected(key: const ValueKey('rejected'), reason: _reason, name: user?.firstName ?? '')
                      : _Pending(key: const ValueKey('pending'), name: user?.firstName ?? '', role: user?.role),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (rejected) ...[
                  AppButton(label: 'Edit & resubmit', icon: AppIcons.pencil, onPressed: _editAndResubmit),
                  const SizedBox(height: AppSpacing.sm),
                ],
                AppButton.secondary(
                  label: 'Check status',
                  icon: AppIcons.refresh,
                  isLoading: _checking,
                  onPressed: _checking ? null : _checkStatus,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => LinkOpener.email('info@fanitt.com').catchError((_) {}),
                      child: const Text('Contact support'),
                    ),
                    Text('·', style: context.text.bodySmall),
                    TextButton(
                      onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
                      child: Text('Log out', style: TextStyle(color: context.palette.textSecondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending({super.key, required this.name, required this.role});

  final String name;
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    final what = switch (role) {
      UserRole.brand => 'brand profile',
      UserRole.agency => 'agency profile',
      _ => 'creator profile',
    };
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
          ),
          child: const Icon(AppIcons.hourglass, size: 42, color: Colors.white),
        ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.05, duration: 1400.ms, curve: Curves.easeInOut),
        const SizedBox(height: AppSpacing.lg),
        Text('Profile under review', textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${name.isEmpty ? 'Thanks' : 'Thanks, $name'}! Our team is checking your $what. This usually takes less than 24 hours — we’ll notify you by app and email.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Steps(rejected: false),
      ],
    );
  }
}

class _Rejected extends StatelessWidget {
  const _Rejected({super.key, required this.reason, required this.name});

  final String reason;
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.error.withValues(alpha: 0.12)),
          child: const Icon(AppIcons.warning, size: 42, color: AppColors.error),
        ).animate().scaleXY(begin: 0.8, curve: Curves.easeOutBack, duration: 400.ms),
        const SizedBox(height: AppSpacing.lg),
        Text('Your profile needs a few changes', textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${name.isEmpty ? '' : '$name, '}our team reviewed your profile and couldn’t approve it yet. Fix the points below and submit it again.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.info, size: 16, color: AppColors.error),
                  const SizedBox(width: 6),
                  Text('Note from Fanitt', style: context.text.labelLarge?.copyWith(color: AppColors.error, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                reason.isEmpty ? 'Please check that your details are complete and correct, then submit again.' : reason,
                style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Steps(rejected: true),
      ],
    );
  }
}

/// Signed up → Review → Approved, with the current step highlighted.
class _Steps extends StatelessWidget {
  const _Steps({required this.rejected});

  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget step(IconData icon, String label, {required bool done, bool current = false, bool bad = false}) {
      final color = bad ? AppColors.error : (done || current ? AppColors.primary : palette.textSecondary);
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.success : (current || bad ? color.withValues(alpha: 0.12) : palette.surfaceMuted),
              ),
              child: Icon(done ? AppIcons.check : icon, size: 16, color: done ? Colors.white : color),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: color, fontWeight: current || bad ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
      child: Row(
        children: [
          step(AppIcons.user, 'Signed up', done: true),
          step(rejected ? AppIcons.warning : AppIcons.hourglass, rejected ? 'Changes needed' : 'In review', done: false, current: !rejected, bad: rejected),
          step(AppIcons.sealCheck, 'Approved', done: false),
        ],
      ),
    );
  }
}