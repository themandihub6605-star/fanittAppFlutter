// File: lib/features/store/presentation/live/live_detail_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/request_state.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/purchase_policy.dart';
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

const _liveRed = Color(0xFFFF3B5C);

/// One live's page: big cover, host, key facts, countdown, about, and one
/// clear action pinned at the bottom (Join / Get ticket / Unlock).
/// `invite` comes from an invite link or code.
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
    HapticFeedback.mediumImpact();
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
      HapticFeedback.heavyImpact();
      AppSnackbar.success(context, 'Ticket confirmed 🎟️');
      _cubit.refresh();
    }
  }

  void _useCode() {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _invite = code);
    _cubit.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<LoadCubit<LiveDetail>, RequestState<LiveDetail>>(
        builder: (context, _) {
          final d = _cubit.state.data;
          if (d == null) {
            return Scaffold(
              appBar: AppBar(leading: const BackButton()),
              body: AsyncView<LiveDetail>(state: _cubit.state, onRetry: _cubit.load, builder: (_) => const SizedBox.shrink()),
            );
          }
          return Scaffold(
            bottomNavigationBar: _ActionBar(child: _action(context, d)),
            body: RefreshIndicator.adaptive(
              color: AppColors.primary,
              onRefresh: _cubit.refresh,
              child: _body(context, d),
            ),
          );
        },
      ),
    );
  }

  /// The one main action for this viewer.
  Widget _action(BuildContext context, LiveDetail d) {
    final live = d.live;
    final access = d.access;
    final palette = context.palette;

    if (access.isPrivateBlocked) {
      return AppButton(label: 'Unlock with code', icon: AppIcons.lock, height: 52, onPressed: _useCode);
    }
    if (live.status == LiveStatus.ended || live.status == LiveStatus.cancelled) {
      return _Note(
        icon: live.status == LiveStatus.cancelled ? AppIcons.xCircle : AppIcons.checkCircle,
        text: live.status == LiveStatus.cancelled ? 'This live was cancelled. Tickets were refunded.' : 'This live has ended.',
        color: palette.textSecondary,
      );
    }
    if (access.needsTicket && live.price > 0 && !PurchasePolicy.canBuyDigital) {
      return _Note(icon: AppIcons.lock, text: 'This live is for ticket holders.', color: palette.textSecondary);
    }
    if (access.needsTicket) {
      return AppButton(label: 'Get ticket · ${Fmt.money(live.price)}', icon: AppIcons.receipt, height: 52, isLoading: _busy, onPressed: _busy ? null : () => _buy(d));
    }
    if (live.isLive) {
      return _JoinButton(label: access.isHost ? 'Go back on air' : 'Join live', busy: _busy, onTap: _busy ? null : () => _join(d));
    }
    return _Note(
      icon: AppIcons.checkCircle,
      text: live.scheduledAt == null ? 'You’re in — join as soon as it starts.' : 'You’re in — we’ll remind you before it starts.',
      color: AppColors.success,
    );
  }

  Widget _body(BuildContext context, LiveDetail d) {
    final live = d.live;
    final access = d.access;
    final palette = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final when = live.scheduledAt?.toLocal();
    final upcoming = !live.isLive && live.status == LiveStatus.scheduled;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          stretch: true,
          expandedHeight: width * 10 / 16,
          backgroundColor: palette.background,
          surfaceTintColor: Colors.transparent,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: _CircleButton(icon: AppIcons.back, onTap: () => Navigator.of(context).maybePop()),
          ),
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(
              fit: StackFit.expand,
              children: [
                StoreImage(url: live.coverUrl, icon: AppIcons.broadcast),
                // Soft fade into the page (no dark overlay).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 70,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [palette.background.withValues(alpha: 0), palette.background]),
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.gutter,
                  bottom: 18,
                  child: Row(
                    children: [
                      if (live.isLive) const _LiveBadge() else if (upcoming) _Chip(icon: AppIcons.calendar, label: when == null ? 'Coming soon' : Fmt.weekdayDateTime(when)),
                      if (live.isLive && live.viewers > 0) ...[
                        const SizedBox(width: 8),
                        _Chip(icon: AppIcons.eye, label: '${Fmt.compact(live.viewers)} watching'),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, AppSpacing.xxl),
          sliver: SliverList.list(
            children: [
              Text(live.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.2, color: palette.textPrimary)),
              const SizedBox(height: 14),

              // Host
              Material(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: d.storeSlug.isEmpty ? null : () => context.push(AppRoutes.storePage(d.storeSlug)),
                  child: Ink(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                    child: Row(
                      children: [
                        StoreLogo(name: d.storeName, url: d.storeLogoUrl, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                              Text(access.isHost ? 'Your live' : 'Host · tap to see their store', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                            ],
                          ),
                        ),
                        Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
              const SizedBox(height: 12),

              // Key facts
              Row(
                children: [
                  _Fact(
                    icon: live.isLive ? AppIcons.broadcast : AppIcons.calendar,
                    label: 'When',
                    value: live.isLive
                        ? (live.startedAt == null ? 'Live now' : 'Since ${Fmt.time(live.startedAt!.toLocal())}')
                        : (when == null ? 'Anytime soon' : Fmt.dateTime(when)),
                    accent: live.isLive ? _liveRed : null,
                  ),
                  const SizedBox(width: 10),
                  _Fact(
                    icon: AppIcons.receipt,
                    label: 'Ticket',
                    value: live.isFree ? 'Free' : (access.allowed && !access.isHost ? 'You have one ✓' : Fmt.money(live.price)),
                    accent: !live.isFree && access.allowed && !access.isHost ? AppColors.success : null,
                  ),
                ],
              ).animate(delay: 60.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Fact(icon: live.isPrivate ? AppIcons.lock : AppIcons.globe, label: 'Who can watch', value: live.audience.label),
                  const SizedBox(width: 10),
                  _Fact(icon: AppIcons.messages, label: 'Chat', value: live.chatEnabled ? 'On — say hi!' : 'Off'),
                ],
              ).animate(delay: 100.ms).fadeIn(duration: 300.ms),

              if (upcoming && when != null && when.isAfter(DateTime.now())) ...[
                const SizedBox(height: 16),
                _Countdown(to: when, onDone: _cubit.refresh).animate(delay: 140.ms).fadeIn(duration: 300.ms),
              ],

              if (access.isPrivateBlocked) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.lock, size: 18, color: palette.textPrimary),
                          const SizedBox(width: 8),
                          Text('Private live', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Enter the invite code the creator shared with you.', style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
                      const SizedBox(height: 12),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: TextField(
                          controller: _code,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _useCode(),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1, color: palette.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Invite code',
                            hintStyle: TextStyle(fontSize: 15, letterSpacing: 0, color: palette.textTertiary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (live.description.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('About this live', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary)),
                const SizedBox(height: 8),
                Text(live.description, style: TextStyle(fontSize: 14, height: 1.55, color: palette.textPrimary)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 10, AppSpacing.gutter, 10), child: child),
      ),
    );
  }
}

/// "Join live" — the one bold button, with a soft live pulse.
class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: _liveRed,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.broadcast, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
    if (busy) return button;
    return button.animate(onPlay: (c) => c.repeat()).shimmer(delay: 1600.ms, duration: 1100.ms, color: Colors.white.withValues(alpha: 0.35));
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.textPrimary))),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value, this.accent});

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: (accent ?? palette.textSecondary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 16, color: accent ?? palette.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                  const SizedBox(height: 1),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent ?? palette.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Days · hours · minutes · seconds until it starts. Refreshes the page at 0.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.to, required this.onDone});

  final DateTime to;
  final Future<void> Function() onDone;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  late Duration _left = widget.to.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = widget.to.difference(DateTime.now());
      if (left.isNegative) {
        _timer?.cancel();
        widget.onDone();
      }
      if (mounted) setState(() => _left = left.isNegative ? Duration.zero : left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final parts = [
      (_left.inDays, 'days'),
      (_left.inHours % 24, 'hours'),
      (_left.inMinutes % 60, 'min'),
      (_left.inSeconds % 60, 'sec'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Starts in', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, p) in parts.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: child)),
                          child: Text(
                            p.$1.toString().padLeft(2, '0'),
                            key: ValueKey('${p.$2}-${p.$1}'),
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()], color: palette.textPrimary),
                          ),
                        ),
                        Text(p.$2, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _liveRed,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [BoxShadow(color: _liveRed.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 1, end: 0.25, duration: 650.ms),
          const SizedBox(width: 6),
          const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.05, duration: 900.ms, curve: Curves.easeInOut);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF475467)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFF344054), fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// White round button over the cover (back).
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: const Color(0x33101828),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: const Color(0xFF344054))),
      ),
    );
  }
}