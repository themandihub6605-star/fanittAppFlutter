import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
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
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';
import 'live_room_screen.dart';

/// Creator's lives: go live, schedule, invite codes, history.
class MyLivesScreen extends StatelessWidget {
  const MyLivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<LiveStream>>(sl<StoreRepository>().myLives),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<LiveStream>>>();
          return Scaffold(
            appBar: AppBar(title: const Text('Stream Live')),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'new-live',
              backgroundColor: AppColors.error,
              onPressed: () async {
                await context.push(AppRoutes.storeLiveNew);
                if (context.mounted) cubit.refresh();
              },
              icon: const Icon(AppIcons.broadcast, color: Colors.white),
              label: const Text('Go live', style: TextStyle(color: Colors.white)),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.04, duration: 1100.ms),
            body: AsyncView<List<LiveStream>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (lives) => AppRefresh(
                onRefresh: cubit.refresh,
                child: lives.isEmpty
                    ? const ScrollableMessage(
                        child: MessageView(icon: AppIcons.broadcast, title: 'No lives yet', message: 'Go live now or schedule one. Make it free, ticketed, invite-only or for your community.'),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 100),
                        itemCount: lives.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _LiveTile(live: lives[i]).animate(delay: (40 * i.clamp(0, 10)).ms).fadeIn(duration: 250.ms),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Starts (or rejoins) a live as host and opens the room.
Future<void> goLiveAsHost(BuildContext context, LiveStream live) async {
  try {
    final started = await sl<StoreRepository>().startLive(live.id);
    if (!context.mounted) return;
    HapticFeedback.heavyImpact();
    await context.push(
      AppRoutes.liveRoom,
      extra: LiveRoomArgs(liveId: live.id, title: live.title, connection: started.connection, isHost: true, chatEnabled: live.chatEnabled),
    );
  } on ApiException catch (e) {
    if (context.mounted) AppSnackbar.error(context, e.displayMessage);
  }
}

class _LiveTile extends StatelessWidget {
  const _LiveTile({required this.live});

  final LiveStream live;

  Color _statusColor(BuildContext context) => switch (live.status) {
        LiveStatus.live => AppColors.error,
        LiveStatus.scheduled => AppColors.info,
        _ => context.palette.textSecondary,
      };

  Future<void> _cancel(BuildContext context) async {
    final reason = await showAppSheet<String>(context, builder: (_) => const _CancelSheet());
    if (reason == null || !context.mounted) return;
    try {
      await sl<StoreRepository>().cancelLive(live.id, reason);
      if (!context.mounted) return;
      AppSnackbar.success(context, live.ticketsSold > 0 ? 'Cancelled — tickets refunded' : 'Live cancelled');
      context.read<LoadCubit<List<LiveStream>>>().refresh();
    } on ApiException catch (e) {
      if (context.mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final when = live.status == LiveStatus.scheduled
        ? (live.scheduledAt == null ? 'Ready to start' : Fmt.weekdayDateTime(live.scheduledAt!.toLocal()))
        : (live.startedAt == null ? '' : Fmt.dateTime(live.startedAt!.toLocal()));
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox(width: 72, height: 54, child: StoreImage(url: live.coverUrl, icon: AppIcons.broadcast)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(live.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        [when, live.isFree ? 'Free' : Fmt.money(live.price), if (live.isPrivate) 'Private'].where((s) => s.isNotEmpty).join(' · '),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusChip(label: live.status.label, color: _statusColor(context)),
              ],
            ),
          ),
          if (live.status == LiveStatus.ended)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Text(
                'Peak ${live.peakViewers} watching · ${live.totalJoins} joins${live.ticketsSold > 0 ? ' · ${live.ticketsSold} tickets (${Fmt.money(live.revenue)})' : ''}',
                style: context.text.bodySmall,
              ),
            ),
          if (live.status == LiveStatus.scheduled || live.status == LiveStatus.live)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: live.status == LiveStatus.live ? 'Return to live' : 'Start now',
                      icon: AppIcons.broadcast,
                      height: 42,
                      onPressed: () async {
                        await goLiveAsHost(context, live);
                        if (context.mounted) context.read<LoadCubit<List<LiveStream>>>().refresh();
                      },
                    ),
                  ),
                  if (live.inviteCode.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IconButton.filledTonal(
                      tooltip: 'Copy invite code',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: 'Join my private live “${live.title}” on Fanitt. Invite code: ${live.inviteCode}'));
                        if (context.mounted) AppSnackbar.success(context, 'Invite copied — share it with your guests');
                      },
                      icon: const Icon(AppIcons.copy),
                    ),
                  ],
                  if (live.status == LiveStatus.scheduled) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(tooltip: 'Cancel live', onPressed: () => _cancel(context), icon: Icon(AppIcons.trash, color: palette.textSecondary)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Cancel this live?',
      subtitle: 'Everyone with a ticket gets a full refund.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _reason, maxLines: 3, maxLength: 300, decoration: const InputDecoration(hintText: 'Tell your audience why (they’ll see this)')),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Cancel live',
            variant: AppButtonVariant.danger,
            onPressed: () {
              if (_reason.text.trim().length < 5) {
                AppSnackbar.error(context, 'Write at least 5 characters');
                return;
              }
              Navigator.of(context).pop(_reason.text.trim());
            },
          ),
        ],
      ),
    );
  }
}
