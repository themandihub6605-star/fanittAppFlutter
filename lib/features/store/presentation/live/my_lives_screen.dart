// File: lib/features/store/presentation/live/my_lives_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/meet_host_api.dart';
import '../../data/store_repository.dart';
import '../meet/attendance_sheet.dart';
import '../widgets/store_widgets.dart';
import 'live_room_screen.dart';
import 'live_tickets_screen.dart';

const _liveRed = Color(0xFFFF3B5C);

/// Creator → My store → Stream Live. Upcoming (countdown, tickets, buyers)
/// and Past (who watched, peak, earnings). Go live / schedule from the button.
class MyLivesScreen extends StatelessWidget {
  const MyLivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => _UpcomingCubit(() => sl<StoreRepository>().myHostLives(tab: 'upcoming'))),
        BlocProvider(create: (_) => _PastCubit(() => sl<StoreRepository>().myHostLives(tab: 'past'))),
      ],
      child: const _MyLivesView(),
    );
  }
}

// Two cubits of the same data type, told apart by class.
class _UpcomingCubit extends LoadCubit<List<HostLive>> {
  _UpcomingCubit(super.loader);
}

class _PastCubit extends LoadCubit<List<HostLive>> {
  _PastCubit(super.loader);
}

void _reloadAll(BuildContext context) {
  context.read<_UpcomingCubit>().refresh();
  context.read<_PastCubit>().refresh();
}

enum _View {
  upcoming('Upcoming', 'Live now and planned lives', AppIcons.calendar),
  past('Past', 'Who watched, peak viewers and earnings', AppIcons.clock);

  const _View(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

class _MyLivesView extends StatefulWidget {
  const _MyLivesView();

  @override
  State<_MyLivesView> createState() => _MyLivesViewState();
}

class _MyLivesViewState extends State<_MyLivesView> {
  _View _view = _View.upcoming;

  Future<void> _pickView() async {
    HapticFeedback.selectionClick();
    final picked = await showAppSheet<_View>(
      context,
      builder: (sheet) => SheetBody(
        title: 'Show',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in _View.values) ...[
              _ViewOption(view: v, selected: v == _view, onTap: () => Navigator.of(sheet).pop(v)),
              if (v != _View.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _view = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(_view == _View.upcoming ? 'Stream Live' : 'Past lives', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _pickView,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(AppIcons.sliders, color: palette.textPrimary),
                if (_view == _View.past)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 1.5)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _view == _View.upcoming
          ? _GoLiveFab(
        onTap: () async {
          HapticFeedback.mediumImpact();
          await context.push(AppRoutes.storeLiveNew);
          if (context.mounted) _reloadAll(context);
        },
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _view == _View.upcoming ? const _UpcomingTab(key: ValueKey('upcoming')) : const _PastTab(key: ValueKey('past')),
      ),
    );
  }
}

/// One choice in the filter sheet: icon, name, one line, radio.
class _ViewOption extends StatelessWidget {
  const _ViewOption({required this.view, required this.selected, required this.onTap});

  final _View view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.4 : 1)),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                child: Icon(view.icon, size: 18, color: palette.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(view.hint, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 6 : 2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Go live" — white pill with a red broadcast icon.
class _GoLiveFab extends StatelessWidget {
  const _GoLiveFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: palette.surface,
      foregroundColor: palette.textPrimary,
      elevation: 3,
      highlightElevation: 5,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      icon: const Icon(AppIcons.broadcast, color: _liveRed, size: 20),
      label: const Text('Go live', style: TextStyle(fontWeight: FontWeight.w800)),
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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

String _audienceLabel(LiveStream l) {
  if (!l.isPrivate) return 'Everyone';
  return switch (l.privateMode) {
    'invite' => 'Invite only',
    'community' => l.audience.communityName.isNotEmpty ? l.audience.communityName : 'Community',
    'selected' => 'Selected people',
    _ => 'Private',
  };
}

IconData _audienceIcon(LiveStream l) {
  if (!l.isPrivate) return AppIcons.globe;
  return switch (l.privateMode) {
    'invite' => AppIcons.link,
    'community' => AppIcons.users,
    _ => AppIcons.lock,
  };
}

// ---------------------------------------------------------------------------
// Upcoming
// ---------------------------------------------------------------------------

class _UpcomingTab extends StatelessWidget {
  const _UpcomingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<_UpcomingCubit>();
    return AsyncView<List<HostLive>>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (items) {
        final running = items.where((h) => h.live.isLive).toList();
        final scheduled = items.where((h) => !h.live.isLive).toList()
          ..sort((a, b) => (a.live.scheduledAt ?? DateTime(2000)).compareTo(b.live.scheduledAt ?? DateTime(2000)));
        return AppRefresh(
          onRefresh: cubit.refresh,
          child: items.isEmpty
              ? const ScrollableMessage(
            child: MessageView(
              icon: AppIcons.broadcast,
              title: 'No lives planned',
              message: 'Go live now or schedule one — free, ticketed, invite-only or just for your community.',
            ),
          )
              : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 120),
            children: [
              _Overview(items: items).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
              const SizedBox(height: 18),
              for (final (i, h) in [...running, ...scheduled].indexed) ...[
                _UpcomingCard(item: h).animate(delay: (60 * i.clamp(0, 6)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.items});

  final List<HostLive> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tickets = items.fold<int>(0, (a, h) => a + h.live.ticketsSold);
    final earned = items.fold<int>(0, (a, h) => a + h.live.revenue);
    final today = items.fold<int>(0, (a, h) => a + h.ticketsToday);
    final liveNow = items.any((h) => h.live.isLive);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: context.isDark ? 0.55 : 0.8)),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (liveNow) ...[
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fade(begin: 1, end: 0.3, duration: 700.ms),
                const SizedBox(width: 8),
              ],
              Text(liveNow ? 'You’re live right now' : 'Your lives', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
              const Spacer(),
              if (today > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                  child: Text('+$today tickets today', style: const TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatBox(label: 'Upcoming', value: '${items.length}'),
              const SizedBox(width: 8),
              _StatBox(label: 'Tickets sold', value: '$tickets'),
              const SizedBox(width: 8),
              _StatBox(label: 'Earned', value: earned == 0 ? '₹0' : Fmt.money(earned)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: palette.textPrimary)),
            const SizedBox(height: 1),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

enum _More { edit, invite, tickets, cancel }

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.item});

  final HostLive item;

  LiveStream get live => item.live;

  static String _countdown(DateTime? at) {
    if (at == null) return 'Ready to start';
    final d = at.toLocal().difference(DateTime.now());
    if (d.isNegative) return 'Start now';
    if (d.inMinutes < 60) return 'Starts in ${d.inMinutes.clamp(1, 59)} min';
    if (d.inHours < 24) return 'Starts in ${d.inHours}h ${d.inMinutes % 60}m';
    final hours = d.inHours % 24;
    return hours == 0 ? 'Starts in ${d.inDays}d' : 'Starts in ${d.inDays}d ${hours}h';
  }

  Future<void> _start(BuildContext context) async {
    await goLiveAsHost(context, live);
    if (context.mounted) _reloadAll(context);
  }

  Future<void> _end(BuildContext context) async {
    final ok = await confirmAction(context, title: 'End this live?', message: 'Everyone watching will be disconnected.', confirmLabel: 'End live', destructive: true);
    if (!ok || !context.mounted) return;
    try {
      await sl<StoreRepository>().endLive(live.id);
      if (!context.mounted) return;
      AppSnackbar.success(context, 'Live ended');
      _reloadAll(context);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final reason = await showAppSheet<String>(context, builder: (_) => _CancelSheet(tickets: live.ticketsSold));
    if (reason == null || !context.mounted) return;
    try {
      await sl<StoreRepository>().cancelLive(live.id, reason);
      if (!context.mounted) return;
      AppSnackbar.success(context, live.ticketsSold > 0 ? 'Cancelled — tickets refunded' : 'Live cancelled');
      _reloadAll(context);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => _EditLiveSheet(live: live));
    if (saved == true && context.mounted) _reloadAll(context);
  }

  Future<void> _copyInvite(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: 'Join my private live “${live.title}” on Fanitt. Invite code: ${live.inviteCode}'));
    HapticFeedback.selectionClick();
    if (context.mounted) AppSnackbar.success(context, 'Invite copied — share it with your guests');
  }

  Future<void> _tickets(BuildContext context) async {
    HapticFeedback.selectionClick();
    await LiveTicketsScreen.open(context, liveId: live.id, title: live.title);
    if (context.mounted) _reloadAll(context);
  }

  void _more(BuildContext context, _More m) {
    switch (m) {
      case _More.edit:
        _edit(context);
      case _More.invite:
        _copyInvite(context);
      case _More.tickets:
        _tickets(context);
      case _More.cancel:
        _cancel(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l = live;
    final isLive = l.isLive;
    final when = l.scheduledAt?.toLocal();
    final hasInvite = l.inviteCode.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isLive ? AppColors.error.withValues(alpha: 0.5) : palette.border, width: isLive ? 1.5 : 1),
        boxShadow: context.isDark
            ? null
            : [BoxShadow(color: isLive ? AppColors.error.withValues(alpha: 0.16) : const Color(0x0F101828), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(url: l.coverUrl, when: when, isLive: isLive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(99)),
                            child: Text(l.viewers > 0 ? '● LIVE · ${Fmt.compact(l.viewers)} watching' : '● LIVE', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.6, duration: 800.ms)
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(99)),
                            child: Text(_countdown(l.scheduledAt), style: TextStyle(color: palette.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        const Spacer(),
                        if (!isLive)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: PopupMenuButton<_More>(
                              padding: EdgeInsets.zero,
                              tooltip: 'More',
                              icon: Icon(AppIcons.dotsThree, size: 20, color: palette.textSecondary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              onSelected: (m) => _more(context, m),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: _More.edit, child: _MenuRow(icon: AppIcons.pencil, label: 'Edit')),
                                if (hasInvite) const PopupMenuItem(value: _More.invite, child: _MenuRow(icon: AppIcons.copy, label: 'Copy invite')),
                                if (!l.isFree) const PopupMenuItem(value: _More.tickets, child: _MenuRow(icon: AppIcons.receipt, label: 'Tickets')),
                                const PopupMenuItem(value: _More.cancel, child: _MenuRow(icon: AppIcons.xCircle, label: 'Cancel live', danger: true)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.25, color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                      isLive
                          ? (l.startedAt == null ? 'Live now' : 'Started ${Fmt.time(l.startedAt!.toLocal())}')
                          : (when == null ? 'Start whenever you’re ready' : Fmt.weekdayDateTime(when)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(icon: _audienceIcon(l), label: _audienceLabel(l)),
                        _Chip(
                          icon: l.isFree ? AppIcons.gift : AppIcons.receipt,
                          label: l.isFree ? 'Free' : Fmt.money(l.price),
                          color: l.isFree ? AppColors.success : palette.textPrimary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Paid → tickets strip. Free → who it's for.
          if (!l.isFree)
            Material(
              color: palette.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: palette.border.withValues(alpha: 0.8))),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _tickets(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      _AvatarStack(people: item.recentBuyers),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.ticketsSold == 0 ? 'No tickets yet' : '${l.ticketsSold} ticket${l.ticketsSold == 1 ? '' : 's'} sold',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.textPrimary),
                            ),
                            Text(
                              l.revenue > 0 ? '${Fmt.money(l.revenue)} earned' : 'Share your live to sell tickets',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (item.ticketsToday > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                          child: Text('+${item.ticketsToday} new', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.success)),
                        ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.06, duration: 900.ms),
                      Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: palette.background, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border.withValues(alpha: 0.8))),
              child: Row(
                children: [
                  Icon(hasInvite ? AppIcons.link : AppIcons.bell, size: 17, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasInvite
                          ? 'Only people with your invite code can join'
                          : (l.isPrivate ? 'Your community gets notified when you go live' : 'Your followers get notified when you go live'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.textPrimary),
                    ),
                  ),
                  if (hasInvite)
                    GestureDetector(
                      onTap: () => _copyInvite(context),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('Copy', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: palette.textPrimary)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          if (isLive)
            Row(
              children: [
                Expanded(child: AppButton(label: 'Return to live', height: 44, onPressed: () => _start(context))),
                const SizedBox(width: 8),
                Expanded(child: AppButton.secondary(label: 'End live', height: 44, onPressed: () => _end(context))),
              ],
            )
          else
            Row(
              children: [
                // Equal halves so both labels fit on small phones too.
                Expanded(child: AppButton(label: 'Start now', icon: AppIcons.broadcast, height: 44, onPressed: () => _start(context))),
                const SizedBox(width: 8),
                Expanded(
                  child: hasInvite
                      ? AppButton.secondary(label: 'Invite', height: 44, onPressed: () => _copyInvite(context))
                      : AppButton.secondary(label: 'Edit', height: 44, onPressed: () => _edit(context)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.when, required this.isLive});

  final String url;
  final DateTime? when;
  final bool isLive;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final w = when;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              ColoredBox(
                color: context.palette.surfaceMuted,
                child: Center(child: Icon(AppIcons.broadcast, color: context.palette.textTertiary, size: 30)),
              )
            else
              StoreImage(url: url, icon: AppIcons.broadcast),
            if (isLive)
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99101828)])))
            else if (w != null)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  width: 36,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)]),
                  child: Column(
                    children: [
                      Text(_months[w.month - 1], style: const TextStyle(color: Color(0xFF667085), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      Text('${w.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 15, fontWeight: FontWeight.w900, height: 1.1)),
                    ],
                  ),
                ),
              ),
            if (isLive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: const Icon(AppIcons.broadcast, color: Colors.white, size: 22)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 0.9, end: 1.15, duration: 700.ms),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : context.palette.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.people});

  final List<LiveBuyerLite> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surfaceMuted),
        child: Icon(AppIcons.receipt, size: 16, color: context.palette.textSecondary),
      );
    }
    const size = 30.0;
    const step = 20.0;
    final surface = context.palette.surface;
    return SizedBox(
      width: size + step * (people.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < people.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
                child: UserAvatar(initials: _initials(people[i].name), imageUrl: people[i].avatarUrl.isEmpty ? null : people[i].avatarUrl, size: size - 3),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Past
// ---------------------------------------------------------------------------

class _PastTab extends StatefulWidget {
  const _PastTab({super.key});

  @override
  State<_PastTab> createState() => _PastTabState();
}

class _PastTabState extends State<_PastTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cubit = context.watch<_PastCubit>();
    return AsyncView<List<HostLive>>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (items) {
        final sorted = [...items]..sort((a, b) => _at(b).compareTo(_at(a)));
        return AppRefresh(
          onRefresh: cubit.refresh,
          child: sorted.isEmpty
              ? const ScrollableMessage(
            child: MessageView(icon: AppIcons.clock, title: 'No past lives yet', message: 'Lives you’ve done show up here with who watched, peak viewers and earnings.'),
          )
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 120),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _PastCard(item: sorted[i]).animate(delay: (40 * i.clamp(0, 8)).ms).fadeIn(duration: 260.ms).slideY(begin: 0.04),
          ),
        );
      },
    );
  }

  static DateTime _at(HostLive h) => h.live.endedAt ?? h.live.startedAt ?? h.live.scheduledAt ?? DateTime(2000);
}

class _PastCard extends StatelessWidget {
  const _PastCard({required this.item});

  final HostLive item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l = item.live;
    final ended = l.status == LiveStatus.ended;
    final (label, color) = ended
        ? ('Ended', AppColors.success)
        : item.missed
        ? ('Not started', palette.textSecondary)
        : ('Cancelled', AppColors.error);
    final at = (l.startedAt ?? l.scheduledAt)?.toLocal();
    final duration = (l.startedAt != null && l.endedAt != null) ? l.endedAt!.difference(l.startedAt!) : null;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 12, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: l.coverUrl.isEmpty
                      ? ColoredBox(
                    color: palette.surfaceMuted,
                    child: Center(child: Icon(AppIcons.broadcast, color: palette.textTertiary, size: 22)),
                  )
                      : ended
                      ? StoreImage(url: l.coverUrl, icon: AppIcons.broadcast)
                      : ColorFiltered(colorFilter: const ColorFilter.matrix(_grey), child: StoreImage(url: l.coverUrl, icon: AppIcons.broadcast)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (at != null) Fmt.weekdayDateTime(at),
                        if (duration != null && duration.inMinutes > 0) '${duration.inMinutes} min',
                        l.isFree ? 'Free' : Fmt.money(l.price),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
          if (ended) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(value: '${l.peakViewers}', label: 'Peak'),
                const SizedBox(width: 6),
                _Stat(value: '${l.totalJoins}', label: 'Joins'),
                const SizedBox(width: 6),
                _Stat(value: l.isFree ? '—' : '${l.ticketsSold}', label: 'Tickets'),
                const SizedBox(width: 6),
                _Stat(value: l.revenue == 0 ? '—' : Fmt.money(l.revenue), label: 'Earned'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LinkButton(
                    icon: AppIcons.users,
                    label: 'Who watched',
                    onTap: () => showAttendanceSheet(context, title: l.title, load: () => MeetHostApi.liveAttendance(l.id)),
                  ),
                ),
                if (!l.isFree && l.ticketsSold > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _LinkButton(icon: AppIcons.receipt, label: 'Tickets', onTap: () => LiveTicketsScreen.open(context, liveId: l.id, title: l.title))),
                ],
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              item.missed
                  ? 'You didn’t start this live, so it was cancelled${l.isFree ? '' : ' and every ticket refunded'}.'
                  : (item.cancelledReason.isEmpty ? 'Cancelled' : 'Reason: ${item.cancelledReason}'),
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static const List<double> _grey = [
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: palette.textPrimary)),
            Text(label, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// White pill with a grey border and dark text.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: palette.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.tickets});

  final int tickets;

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
      subtitle: widget.tickets > 0 ? '${widget.tickets} ticket${widget.tickets == 1 ? '' : 's'} will be refunded in full.' : 'People who saw it will be told.',
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

/// Edit a scheduled live: cover, title, description, time, chat.
class _EditLiveSheet extends StatefulWidget {
  const _EditLiveSheet({required this.live});

  final LiveStream live;

  @override
  State<_EditLiveSheet> createState() => _EditLiveSheetState();
}

class _EditLiveSheetState extends State<_EditLiveSheet> {
  late final _title = TextEditingController(text: widget.live.title);
  late final _description = TextEditingController(text: widget.live.description);
  late DateTime? _when = widget.live.scheduledAt?.toLocal();
  late bool _chat = widget.live.chatEnabled;
  PickedMedia? _cover;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final start = _when != null && _when!.isAfter(now) ? _when! : now.add(const Duration(hours: 1));
    final date = await showDatePicker(context: context, initialDate: start, firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      if (mounted) AppSnackbar.error(context, 'Pick a time in the future');
      return;
    }
    setState(() => _when = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.length < 3) {
      AppSnackbar.error(context, 'Enter a title (at least 3 characters)');
      return;
    }
    setState(() => _busy = true);
    final repo = sl<StoreRepository>();
    final old = widget.live.scheduledAt?.toLocal();
    final moved = _when != null && (old == null || _when!.difference(old).inMinutes.abs() >= 1);
    try {
      await repo.updateLive(
        widget.live.id,
        title: title,
        description: _description.text.trim(),
        scheduledAt: moved ? _when : null,
        chatEnabled: _chat,
      );
      if (_cover != null) await repo.uploadLiveCover(widget.live.id, _cover!);
      if (!mounted) return;
      AppSnackbar.success(context, moved && widget.live.ticketsSold > 0 ? 'Saved — ticket holders told about the new time' : 'Live updated');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SheetBody(
      title: 'Edit live',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _busy
                ? null
                : () async {
              final picked = await sl<MediaPicker>().image();
              if (picked != null) setState(() => _cover = picked);
            },
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(AppIcons.image, color: palette.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_cover == null ? 'Change cover' : 'New cover picked ✓', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                  ),
                  Icon(AppIcons.chevronRight, size: 18, color: palette.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: 'Title', controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 4, maxLength: 2000, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: _busy ? null : _pickWhen,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(AppIcons.calendar, color: palette.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _when == null ? 'No time set — start whenever' : Fmt.weekdayDateTime(_when!),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary),
                    ),
                  ),
                  Text('Change', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                ],
              ),
            ),
          ),
          if (widget.live.ticketsSold > 0) ...[
            const SizedBox(height: 6),
            Text('A new time is sent to everyone with a ticket.', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _chat,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _chat = v),
            title: Text('Live chat', style: context.text.titleSmall),
            subtitle: Text('Viewers can send messages and hearts', style: context.text.bodySmall),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Save changes', isLoading: _busy, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}