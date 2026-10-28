// File: lib/features/store/presentation/call/call_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';

/// Creator: go online for 1:1 calls, set per-minute rates, see earnings
/// and recent calls. Calm look: white cards, orange only for small accents.
class CallSettingsScreen extends StatelessWidget {
  const CallSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<StoreRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => LoadCubit<CallSettings>(repo.callSettings)),
        BlocProvider(create: (_) => PagedCubit<CallSession>((page) => repo.myCalls(asHost: true, page: page))),
      ],
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<CallSettings>>();
          final calls = context.watch<PagedCubit<CallSession>>();
          final palette = context.palette;
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('1:1 Calls', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            ),
            body: AsyncView<CallSettings>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (settings) => AppRefresh(
                onRefresh: () async {
                  await Future.wait([cubit.refresh(), calls.refresh()]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
                  children: [
                    _OnlineCard(settings: settings).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
                    const SizedBox(height: 14),
                    _EarningsStrip(calls: calls.state.items),
                    const SizedBox(height: 20),
                    _SectionTitle('Rates'),
                    const SizedBox(height: 10),
                    _RatesCard(settings: settings),
                    const SizedBox(height: 22),
                    _SectionTitle('Recent calls', trailing: calls.state.items.isEmpty ? null : '${calls.state.items.length}${calls.state.hasMore ? '+' : ''}'),
                    const SizedBox(height: 10),
                    if (calls.state.items.isEmpty && !calls.state.isLoading)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                        child: Column(
                          children: [
                            Icon(AppIcons.phone, size: 28, color: palette.textTertiary),
                            const SizedBox(height: 8),
                            Text('No calls yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                            const SizedBox(height: 2),
                            Text('Go online — fans see you in “Talk 1:1 with experts”.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                        child: Column(
                          children: [
                            for (final (i, c) in calls.state.items.indexed) ...[
                              if (i > 0) Divider(height: 1, indent: 64, color: palette.border),
                              _CallRow(call: c),
                            ],
                          ],
                        ),
                      ),
                    if (calls.state.hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(child: TextButton(onPressed: calls.loadMore, child: const Text('Load more'))),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.messages, size: 14, color: palette.textTertiary),
                        const SizedBox(width: 6),
                        Text('Text chat with fans stays free in Messages.', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary))),
        if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
      ],
    );
  }
}

/// Online / offline: white card, green dot when online.
class _OnlineCard extends StatefulWidget {
  const _OnlineCard({required this.settings});

  final CallSettings settings;

  @override
  State<_OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends State<_OnlineCard> {
  bool _busy = false;

  Future<void> _toggle(bool online) async {
    setState(() => _busy = true);
    try {
      final updated = await sl<StoreRepository>().setOnline(online);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      context.read<LoadCubit<CallSettings>>().replace(updated);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final s = widget.settings;
    final online = s.enabled && s.online;
    final rates = [
      if (s.audioEnabled) 'Audio ${s.audioRate == 0 ? 'free' : '${Fmt.money(s.audioRate)}/min'}',
      if (s.videoEnabled) 'Video ${s.videoRate == 0 ? 'free' : '${Fmt.money(s.videoRate)}/min'}',
    ].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: online ? AppColors.success.withValues(alpha: 0.45) : palette.border, width: online ? 1.4 : 1),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (online)
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.success.withValues(alpha: 0.15)),
                      ).animate(onPlay: (c) => c.repeat()).scaleXY(begin: 0.7, end: 1.15, duration: 1400.ms).fadeOut(duration: 1400.ms),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: online ? AppColors.success.withValues(alpha: 0.12) : palette.surfaceMuted),
                      child: Icon(AppIcons.phone, size: 18, color: online ? AppColors.success : palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(online ? 'You’re online' : 'You’re offline', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      !s.enabled ? 'Turn on “Take calls” below first' : (online ? 'Fans can call you right now' : 'Go online when you’re free to talk'),
                      style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              _busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : Switch.adaptive(value: online, onChanged: !s.enabled ? null : _toggle, activeTrackColor: AppColors.success),
            ],
          ),
          if (s.enabled && rates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(AppIcons.info, size: 14, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$rates. If you miss a call we switch you offline, and after 12 hours online too.',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Earned from the calls loaded, completed count, missed count.
class _EarningsStrip extends StatelessWidget {
  const _EarningsStrip({required this.calls});

  final List<CallSession> calls;

  @override
  Widget build(BuildContext context) {
    final earned = calls.fold<int>(0, (a, c) => a + c.creatorEarning);
    final done = calls.where((c) => c.status == CallStatus.completed && c.billedMinutes > 0).length;
    final minutes = calls.fold<int>(0, (a, c) => a + c.billedMinutes);
    final missed = calls.where((c) => c.status == CallStatus.missed).length;
    return Row(
      children: [
        _Stat(value: Fmt.money(earned), label: 'Earned'),
        const SizedBox(width: 8),
        _Stat(value: '$done', label: 'Calls'),
        const SizedBox(width: 8),
        _Stat(value: '$minutes', label: 'Minutes'),
        const SizedBox(width: 8),
        _Stat(value: '$missed', label: 'Missed', warn: missed > 0),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.warn = false});

  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: palette.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: warn ? AppColors.warning : palette.textPrimary)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _RatesCard extends StatefulWidget {
  const _RatesCard({required this.settings});

  final CallSettings settings;

  @override
  State<_RatesCard> createState() => _RatesCardState();
}

class _RatesCardState extends State<_RatesCard> {
  late bool _enabled = widget.settings.enabled;
  late bool _audio = widget.settings.audioEnabled;
  late bool _video = widget.settings.videoEnabled;
  late final _audioRate = TextEditingController(text: widget.settings.audioRate == 0 ? '' : Fmt.paiseToRupeesInput(widget.settings.audioRate));
  late final _videoRate = TextEditingController(text: widget.settings.videoRate == 0 ? '' : Fmt.paiseToRupeesInput(widget.settings.videoRate));
  bool _busy = false;

  @override
  void dispose() {
    _audioRate.dispose();
    _videoRate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_enabled && !_audio && !_video) {
      AppSnackbar.error(context, 'Turn on audio or video calls');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final updated = await sl<StoreRepository>().updateCallSettings(
        enabled: _enabled,
        audioEnabled: _audio,
        videoEnabled: _video,
        audioRate: Fmt.rupeesToPaise(_audioRate.text) ?? 0,
        videoRate: Fmt.rupeesToPaise(_videoRate.text) ?? 0,
      );
      if (!mounted) return;
      context.read<LoadCubit<CallSettings>>().replace(updated);
      AppSnackbar.success(context, 'Call settings saved');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ToggleRow(
            icon: AppIcons.phone,
            title: 'Take calls',
            subtitle: 'Fans pay up front · first 15 sec free · unused minutes go back to them',
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: !_enabled
                ? const SizedBox(width: double.infinity)
                : Column(
              children: [
                Divider(height: 18, color: palette.border),
                _ToggleRow(icon: AppIcons.speakerOn, title: 'Audio calls', value: _audio, onChanged: (v) => setState(() => _audio = v)),
                if (_audio) _RateField(controller: _audioRate, label: 'Audio'),
                Divider(height: 18, color: palette.border),
                _ToggleRow(icon: AppIcons.videoCamera, title: 'Video calls', value: _video, onChanged: (v) => setState(() => _video = v)),
                if (_video) _RateField(controller: _videoRate, label: 'Video'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppButton(label: 'Save', height: 48, isLoading: _busy, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.icon, required this.title, required this.value, required this.onChanged, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 17, color: palette.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 11.5, height: 1.3, color: palette.textSecondary)),
              ],
            ),
          ),
          Switch.adaptive(value: value, activeTrackColor: AppColors.primary, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// "₹ [ 20 ] / min" — empty means free.
class _RateField extends StatelessWidget {
  const _RateField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text('₹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Free',
                  hintStyle: TextStyle(fontSize: 15, color: palette.textTertiary),
                ),
              ),
            ),
            Text('per minute', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});

  final CallSession call;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = call;
    final (label, color) = switch (c.status) {
      CallStatus.completed => (c.billedMinutes > 0 ? '${c.billedMinutes} min' : 'Not connected', c.billedMinutes > 0 ? AppColors.success : palette.textSecondary),
      CallStatus.missed => ('Missed', AppColors.warning),
      CallStatus.declined => ('Declined', palette.textSecondary),
      CallStatus.active => ('On call', AppColors.success),
      CallStatus.requested => ('Ringing', AppColors.primary),
      _ => (c.status.label, palette.textSecondary),
    };
    return InkWell(
      onTap: () => context.push(AppRoutes.storeCall(c.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(initials: c.otherName.isEmpty ? '?' : c.otherName[0].toUpperCase(), imageUrl: c.otherAvatarUrl, size: 40),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
                    child: Icon(c.isVideo ? AppIcons.videoCamera : AppIcons.phone, size: 11, color: palette.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.otherName.isEmpty ? 'Fan' : c.otherName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                  const SizedBox(height: 1),
                  Text(
                    [
                      '${c.prepaidMinutes} min booked',
                      if (c.createdAt != null) Fmt.relative(c.createdAt!.toLocal()),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                if (c.creatorEarning > 0) ...[
                  const SizedBox(height: 2),
                  Text('+${Fmt.money(c.creatorEarning)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}