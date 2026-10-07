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
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';

/// Creator: go online for calls, set per-minute rates, see call history.
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
          return Scaffold(
            appBar: AppBar(title: const Text('Live Chat & Calls')),
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
                    _OnlineCard(settings: settings),
                    const SizedBox(height: AppSpacing.lg),
                    _RatesCard(settings: settings),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Recent calls', style: context.text.titleLarge),
                    const SizedBox(height: AppSpacing.sm),
                    if (calls.state.items.isEmpty && !calls.state.isLoading)
                      Text('No calls yet.', style: context.text.bodySmall)
                    else
                      for (final c in calls.state.items) _CallTile(call: c),
                    if (calls.state.hasMore)
                      TextButton(onPressed: calls.loadMore, child: const Text('Load more')),
                    const SizedBox(height: AppSpacing.md),
                    Text('Text chat with fans stays free in Messages.', textAlign: TextAlign.center, style: context.text.bodySmall),
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
    final s = widget.settings;
    final online = s.enabled && s.online;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          colors: online ? const [Color(0xFF12A150), Color(0xFF0E7A3D)] : [context.palette.surfaceMuted, context.palette.surfaceMuted],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(shape: BoxShape.circle, color: online ? Colors.white : context.palette.textTertiary),
          ).animate(target: online ? 1 : 0, onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.4, duration: 800.ms),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(online ? 'You’re online' : 'You’re offline', style: context.text.titleMedium?.copyWith(color: online ? Colors.white : null)),
                Text(
                  !s.enabled ? 'Turn on calls below first' : (online ? 'Fans can call you now' : 'Go online to take calls'),
                  style: context.text.bodySmall?.copyWith(color: online ? Colors.white70 : null),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: online, onChanged: _busy || !s.enabled ? null : _toggle, activeTrackColor: Colors.white54),
        ],
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
    if (!_audio && !_video) {
      AppSnackbar.error(context, 'Turn on audio or video calls');
      return;
    }
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
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _enabled = v),
            title: Text('Take calls', style: context.text.titleSmall),
            subtitle: Text('Fans pay per minute up front; unused minutes go back to them', style: context.text.bodySmall),
          ),
          const Divider(),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _audio,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _audio = v),
            title: Text('Audio calls', style: context.text.titleSmall),
          ),
          if (_audio)
            AppTextField(label: 'Audio rate (₹ per minute, empty = free)', controller: _audioRate, prefixIcon: AppIcons.rupee, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: formatters),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _video,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _video = v),
            title: Text('Video calls', style: context.text.titleSmall),
          ),
          if (_video)
            AppTextField(label: 'Video rate (₹ per minute, empty = free)', controller: _videoRate, prefixIcon: AppIcons.rupee, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: formatters),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Save', isLoading: _busy, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});

  final CallSession call;

  @override
  Widget build(BuildContext context) {
    final color = switch (call.status) {
      CallStatus.completed => AppColors.success,
      CallStatus.active || CallStatus.requested => AppColors.primary,
      _ => context.palette.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        onTap: () => context.push(AppRoutes.storeCall(call.id)),
        child: Row(
          children: [
            UserAvatar(initials: call.otherName.isEmpty ? '?' : call.otherName[0].toUpperCase(), imageUrl: call.otherAvatarUrl, size: 40),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.otherName, style: context.text.titleSmall),
                  Text(
                    '${call.isVideo ? 'Video' : 'Audio'} · ${call.billedMinutes > 0 ? '${call.billedMinutes} min' : '${call.prepaidMinutes} min booked'}${call.createdAt == null ? '' : ' · ${Fmt.relative(call.createdAt!)}'}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(label: call.status.label, color: color),
                if (call.creatorEarning > 0) ...[
                  const SizedBox(height: 4),
                  Text('+${Fmt.money(call.creatorEarning)}', style: context.text.labelMedium?.copyWith(color: AppColors.success)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
