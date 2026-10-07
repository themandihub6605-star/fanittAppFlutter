import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/request_state.dart';
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
import '../../data/store_repository.dart';
import '../widgets/store_checkout.dart';
import '../widgets/store_widgets.dart';
import 'live_room_screen.dart';

/// A live's page: details, ticket, join. `invite` comes from an invite code.
class LiveDetailScreen extends StatefulWidget {
  const LiveDetailScreen({super.key, required this.liveId, this.invite});

  final String liveId;
  final String? invite;

  @override
  State<LiveDetailScreen> createState() => _LiveDetailScreenState();
}

class _LiveDetailScreenState extends State<LiveDetailScreen> {
  late String? _invite = widget.invite;
  late final LoadCubit<LiveDetail> _cubit = LoadCubit<LiveDetail>(() => sl<StoreRepository>().liveDetail(widget.liveId, invite: _invite));
  bool _busy = false;
  final _code = TextEditingController();

  @override
  void dispose() {
    _cubit.close();
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(LiveDetail d) async {
    setState(() => _busy = true);
    try {
      final joined = await sl<StoreRepository>().joinLive(d.live.id, invite: _invite);
      if (!mounted) return;
      await context.push(
        AppRoutes.liveRoom,
        extra: LiveRoomArgs(
          liveId: d.live.id,
          title: d.live.title,
          connection: joined.connection,
          isHost: joined.isHost,
          chatEnabled: d.live.chatEnabled,
          storeId: d.live.storeId,
          hostName: d.storeName,
        ),
      );
      if (mounted) _cubit.refresh();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(LiveDetail d) async {
    setState(() => _busy = true);
    final order = await payForStoreItem(
      context,
      amount: d.live.price,
      title: 'Ticket · ${d.live.title}',
      start: (payWith) => sl<StoreRepository>().buyLiveTicket(d.live.id, payWith: payWith, invite: _invite),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order != null) {
      AppSnackbar.success(context, 'Ticket confirmed 🎟️');
      _cubit.refresh();
    }
  }

  void _useCode() {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _invite = code);
    _cubit.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<LoadCubit<LiveDetail>, RequestState<LiveDetail>>(
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Live')),
          body: AsyncView<LiveDetail>(
            state: _cubit.state,
            onRetry: _cubit.load,
            builder: (d) => AppRefresh(onRefresh: _cubit.refresh, child: _body(context, d)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, LiveDetail d) {
    final live = d.live;
    final access = d.access;
    final palette = context.palette;

    Widget action;
    if (access.isPrivateBlocked) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This is a private live. Enter the invite code the creator shared with you.', style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _code, decoration: const InputDecoration(hintText: 'Invite code', prefixIcon: Icon(AppIcons.lock, size: 20))),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Unlock', onPressed: _useCode),
        ],
      );
    } else if (live.status == LiveStatus.ended || live.status == LiveStatus.cancelled) {
      action = Text(live.status == LiveStatus.cancelled ? 'This live was cancelled. Tickets were refunded.' : 'This live has ended.', style: context.text.bodyMedium);
    } else if (access.needsTicket) {
      action = AppButton(label: 'Get ticket · ${Fmt.money(live.price)}', icon: AppIcons.lightning, isLoading: _busy, onPressed: _busy ? null : () => _buy(d));
    } else if (live.isLive) {
      action = AppButton(label: access.isHost ? 'Go back on air' : 'Join live', icon: AppIcons.broadcast, isLoading: _busy, onPressed: _busy ? null : () => _join(d));
    } else {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                const Icon(AppIcons.checkCircle, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    live.scheduledAt == null ? 'You’re in. Join as soon as it starts.' : 'You’re in. Starts ${Fmt.weekdayDateTime(live.scheduledAt!.toLocal())}.',
                    style: context.text.bodyMedium?.copyWith(color: palette.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Pull down to refresh when it’s time.', textAlign: TextAlign.center, style: context.text.bodySmall),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoreImage(url: live.coverUrl, icon: AppIcons.broadcast),
                if (live.isLive)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
                      child: Text('LIVE · ${live.viewers} watching', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.7, duration: 900.ms),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(live.title, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: d.storeSlug.isEmpty ? null : () => context.push(AppRoutes.storePage(d.storeSlug)),
          child: Row(
            children: [
              StoreLogo(name: d.storeName, url: d.storeLogoUrl, size: 28),
              const SizedBox(width: AppSpacing.xs),
              Text(d.storeName, style: context.text.titleSmall),
              const Spacer(),
              PriceTag(price: live.price, owned: !live.isFree && access.allowed && !access.isHost),
            ],
          ),
        ),
        if (live.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(live.description, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.5)),
        ],
        const SizedBox(height: AppSpacing.xl),
        action,
      ],
    );
  }
}
