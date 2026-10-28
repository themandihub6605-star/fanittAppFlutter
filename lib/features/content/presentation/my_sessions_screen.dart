// File: lib/features/content/presentation/my_sessions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/image_upload_box.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../data/content_repository.dart';
import '../../store/data/meet_host_api.dart';
import '../../store/presentation/meet/attendance_sheet.dart';
import '../../store/presentation/meet/meet_detail_screen.dart';
import 'gifts_screen.dart';
import 'session_bookings_screen.dart';

/// Creator → My store → Live sessions. Upcoming (with who booked, seats and
/// earnings) and History. Tap the booking strip to see everyone who booked.
class MySessionsScreen extends StatelessWidget {
  const MySessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<HostSession>>(MeetHostApi.myUpcoming),
        child: const _SessionsView(),
      ),
    );
  }
}

enum _View {
  upcoming('Upcoming', 'Sessions you have scheduled', AppIcons.calendar),
  history('History', 'Past sessions and who attended', AppIcons.clock);

  const _View(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

class _SessionsView extends StatefulWidget {
  const _SessionsView();

  @override
  State<_SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<_SessionsView> {
  _View _view = _View.upcoming;

  Future<void> _create(BuildContext context) async {
    HapticFeedback.selectionClick();
    final created = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _NewSessionSheet()));
    if ((created ?? false) && context.mounted) {
      AppSnackbar.success(context, 'Session scheduled');
      if (_view != _View.upcoming) setState(() => _view = _View.upcoming);
      context.read<LoadCubit<List<HostSession>>>().refresh();
    }
  }

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
    final cubit = context.watch<LoadCubit<List<HostSession>>>();
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          _view == _View.upcoming ? 'Live sessions' : 'Session history',
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _pickView,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(AppIcons.sliders, color: palette.textPrimary),
                if (_view == _View.history)
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
      // Schedule — white pill, not orange.
      floatingActionButton: _view == _View.upcoming
          ? FloatingActionButton.extended(
        onPressed: () => _create(context),
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 3,
        highlightElevation: 5,
        shape: StadiumBorder(side: BorderSide(color: palette.border)),
        icon: const Icon(AppIcons.plus, size: 20),
        label: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w800)),
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _view == _View.history
            ? const _HistoryTab(key: ValueKey('history'))
            : KeyedSubtree(
          key: const ValueKey('upcoming'),
          child: AsyncView<List<HostSession>>(
            state: cubit.state,
            onRetry: cubit.load,
            builder: (sessions) => AppRefresh(
              onRefresh: cubit.refresh,
              child: sessions.isEmpty
                  ? const ScrollableMessage(
                child: MessageView(
                  icon: AppIcons.videoCamera,
                  title: 'No upcoming sessions',
                  message: 'Schedule a free or paid live session — you’ll see everyone who books it right here.',
                ),
              )
                  : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 110),
                children: [
                  _Overview(sessions: sessions).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
                  const SizedBox(height: 18),
                  for (final (i, s) in sessions.indexed) ...[
                    _SessionCard(item: s).animate(delay: (60 * i.clamp(0, 6)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
        ),
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

/// Summary on top — white card: sessions, people booked, earned.
class _Overview extends StatelessWidget {
  const _Overview({required this.sessions});

  final List<HostSession> sessions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final booked = sessions.fold<int>(0, (a, s) => a + s.session.bookedCount);
    final earned = sessions.fold<int>(0, (a, s) => a + s.earned);
    final today = sessions.fold<int>(0, (a, s) => a + s.bookedToday);
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
              Text('Your sessions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
              const Spacer(),
              if (today > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                  child: Text('+$today booked today', style: const TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatBox(label: 'Upcoming', value: '${sessions.length}'),
              const SizedBox(width: 8),
              _StatBox(label: 'People booked', value: '$booked'),
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

enum _More { edit, postpone, tips, cancel }

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.item});

  final HostSession item;

  LiveSession get session => item.session;

  void _reload(BuildContext context) => context.read<LoadCubit<List<HostSession>>>().refresh();

  Future<void> _start(BuildContext context) async {
    // Starts the meeting in-app (LiveKit) — no Zoom, no passcode.
    HapticFeedback.mediumImpact();
    await openMeetRoom(context, session.id);
    if (context.mounted) _reload(context);
  }

  Future<void> _end(BuildContext context) async {
    final ok = await context.read<ActionCubit>().run('live-${session.id}', () async {
      await sl<ContentRepository>().endLive(session.id);
      return true;
    }, success: 'Session ended');
    if (ok != null && context.mounted) _reload(context);
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancel this session?',
      message: session.bookedCount > 0 ? '${session.bookedCount} people booked it. They’ll be notified.' : 'It will be removed from your profile.',
      confirmLabel: 'Cancel session',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<ActionCubit>().run('cancel-${session.id}', () async {
      await sl<ContentRepository>().cancelSession(session.id);
      return true;
    }, success: 'Session cancelled');
    if (ok != null && context.mounted) _reload(context);
  }

  Future<void> _edit(BuildContext context) async {
    final updated = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _EditSessionSheet(session: session)));
    if (updated == true && context.mounted) _reload(context);
  }

  Future<void> _postpone(BuildContext context) async {
    final moved = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _PostponeSheet(session: session)));
    if (moved == true && context.mounted) _reload(context);
  }

  Future<void> _bookings(BuildContext context) async {
    HapticFeedback.selectionClick();
    await SessionBookingsScreen.open(context, sessionId: session.id, title: session.title);
    if (context.mounted) _reload(context);
  }

  void _more(BuildContext context, _More m) {
    switch (m) {
      case _More.edit:
        _edit(context);
      case _More.postpone:
        _postpone(context);
      case _More.tips:
        showAppSheet<void>(context, builder: (_) => _TipsSheet(session: session));
      case _More.cancel:
        _cancel(context);
    }
  }

  static String _countdown(DateTime at) {
    final d = at.toLocal().difference(DateTime.now());
    if (d.isNegative) return 'Starting now';
    if (d.inMinutes < 60) return 'Starts in ${d.inMinutes.clamp(1, 59)} min';
    if (d.inHours < 24) return 'Starts in ${d.inHours}h ${d.inMinutes % 60}m';
    final days = d.inDays;
    final hours = d.inHours % 24;
    return hours == 0 ? 'Starts in ${days}d' : 'Starts in ${days}d ${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final actions = context.watch<ActionCubit>().state;
    final s = session;
    final free = s.type == SessionType.free;
    final fill = s.maxParticipants == 0 ? 0.0 : (s.bookedCount / s.maxParticipants).clamp(0.0, 1.0);
    final cover = s.coverImageUrl ?? '';
    final w = s.scheduledAt.toLocal();

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.isLive ? AppColors.error.withValues(alpha: 0.45) : palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 16, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: cover + title + time
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: s.isLive ? null : () => _edit(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover.isEmpty)
                          ColoredBox(
                            color: palette.surfaceMuted,
                            child: Center(child: Icon(AppIcons.videoCamera, color: palette.textTertiary, size: 30)),
                          )
                        else
                          AppNetworkImage(url: cover),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            width: 36,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)]),
                            child: Column(
                              children: [
                                Text(MeetPosterPreview._months[w.month - 1], style: const TextStyle(color: Color(0xFF667085), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                Text('${w.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 15, fontWeight: FontWeight.w900, height: 1.1)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (s.isLive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(99)),
                            child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.55, duration: 800.ms)
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(99)),
                            child: Text(_countdown(s.scheduledAt), style: TextStyle(color: palette.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w800)),
                          ),
                        const Spacer(),
                        if (!s.isLive)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: PopupMenuButton<_More>(
                              padding: EdgeInsets.zero,
                              tooltip: 'More',
                              enabled: !actions.isBusy,
                              icon: Icon(AppIcons.dotsThree, size: 20, color: palette.textSecondary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              onSelected: (m) => _more(context, m),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: _More.edit, child: _MenuRow(icon: AppIcons.pencil, label: 'Edit')),
                                const PopupMenuItem(value: _More.postpone, child: _MenuRow(icon: AppIcons.calendar, label: 'Postpone')),
                                const PopupMenuItem(value: _More.tips, child: _MenuRow(icon: AppIcons.gift, label: 'Tips')),
                                const PopupMenuItem(value: _More.cancel, child: _MenuRow(icon: AppIcons.xCircle, label: 'Cancel session', danger: true)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.25, color: palette.textPrimary)),
                    const SizedBox(height: 4),
                    Text(
                      '${Fmt.weekdayDateTime(w)} · ${s.durationMinutes} min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      free ? 'Free' : '${Fmt.money(s.price)} · ${s.type.label}',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: free ? AppColors.success : palette.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Booking strip → full list of who booked
          Material(
            color: palette.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: palette.border.withValues(alpha: 0.8))),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _bookings(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _AvatarStack(people: item.recentBookers),
                        if (item.recentBookers.isNotEmpty) const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.bookedCount == 0 ? 'No bookings yet' : '${s.bookedCount} ${s.bookedCount == 1 ? 'person' : 'people'} booked',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.textPrimary),
                              ),
                              Text(
                                '${item.seatsLeft} of ${s.maxParticipants} seats left${!free && item.earned > 0 ? ' · ${Fmt.money(item.earned)} earned' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (item.bookedToday > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                            child: Text('+${item.bookedToday} new', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.success)),
                          ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.06, duration: 900.ms),
                        Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: fill),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: palette.surfaceMuted,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Actions
          if (s.isLive)
            Row(
              children: [
                Expanded(child: AppButton(label: 'Rejoin', icon: AppIcons.videoCamera, height: 44, onPressed: () => _start(context))),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton.secondary(
                    label: 'End session',
                    height: 44,
                    isLoading: actions.isBusyWith('live-${s.id}'),
                    onPressed: actions.isBusy ? null : () => _end(context),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                // Equal halves so both labels fit on small phones too.
                Expanded(
                  child: AppButton(
                    label: 'Go live',
                    icon: AppIcons.broadcast,
                    height: 44,
                    isLoading: actions.isBusyWith('live-${s.id}'),
                    onPressed: actions.isBusy ? null : () => _start(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton.secondary(label: 'Bookings', height: 44, onPressed: () => _bookings(context)),
                ),
              ],
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

/// Up to 4 overlapping avatars of the latest bookers.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.people});

  final List<BookerLite> people;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.palette.surfaceMuted),
        child: Icon(AppIcons.users, size: 17, color: context.palette.textSecondary),
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

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet();

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  SessionType _type = SessionType.free;
  DateTime? _when;
  int _duration = 60;
  int _seats = 50;
  String? _categoryId;
  List<Category> _categories = const [];
  PickedMedia? _cover;

  @override
  void initState() {
    super.initState();
    sl<CategoriesRepository>().getAll().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 180)), initialDate: _when ?? now.add(const Duration(days: 1)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final actions = context.read<ActionCubit>();
    if (_when == null || _when!.isBefore(DateTime.now())) {
      await actions.run<void>('create', () async => throw const ApiException('Pick a date and time in the future.'));
      return;
    }
    final repo = sl<ContentRepository>();
    final ok = await actions.run('create', () async {
      final coverUrl = _cover == null ? null : await repo.uploadSessionBanner(_cover!);
      return repo.createSession(
        title: _title.text.trim(),
        description: _description.text.trim(),
        categoryId: _categoryId!,
        type: _type,
        price: Fmt.rupeesToPaise(_price.text) ?? 0,
        scheduledAt: _when!,
        durationMinutes: _duration,
        maxParticipants: _type == SessionType.oneToOne ? 1 : _seats,
        coverImageUrl: coverUrl,
      );
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Schedule a session',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poster — same shape and look as the home "Online sessions" card.
            ListenableBuilder(
              listenable: _title,
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.meetPoster,
                picked: _cover,
                optional: true,
                enabled: !busy,
                onPick: () async {
                  final image = await sl<MediaPicker>().image();
                  if (image != null) setState(() => _cover = image);
                },
                onRemove: () => setState(() => _cover = null),
                previewBuilder: (context, image) => MeetPosterPreview(
                  image: image,
                  title: _title.text.trim(),
                  when: _when,
                  durationMinutes: _duration,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Title', controller: _title, textCapitalization: TextCapitalization.sentences, validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter a title' : null),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 4),
            const SizedBox(height: AppSpacing.md),
            AppDropdown<String>(
              label: 'Category',
              items: _categories.map((c) => c.id).toList(),
              value: _categoryId,
              labelOf: (id) => _categories.firstWhere((c) => c.id == id).label,
              onChanged: (id) => setState(() => _categoryId = id),
              validator: (v) => v == null ? 'Choose a category' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Type'),
            ChoicePills<SessionType>(options: SessionType.values, selected: {_type}, labelOf: (t) => t.label, onChanged: (t) => setState(() => _type = t)),
            if (_type != SessionType.free) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Price',
                controller: _price,
                prefixIcon: AppIcons.rupee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                validator: (v) => (Fmt.rupeesToPaise(v ?? '') ?? 0) < 100 ? 'Enter at least ₹1' : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Date & time'),
            AppCard(
              onTap: _pickDateTime,
              child: Row(
                children: [
                  Icon(AppIcons.calendar, size: 20, color: context.palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_when == null ? 'Choose when' : Fmt.weekdayDateTime(_when!), style: context.text.titleSmall)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Duration'),
            ChoicePills<int>(options: const [15, 30, 45, 60, 90, 120], selected: {_duration}, labelOf: (m) => '$m min', onChanged: (m) => setState(() => _duration = m)),
            if (_type != SessionType.oneToOne) ...[
              const SizedBox(height: AppSpacing.md),
              CounterField(label: 'Seats', value: _seats, min: 1, max: 1000, onChanged: (v) => setState(() => _seats = v)),
            ],
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Schedule session', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _TipsSheet extends StatelessWidget {
  const _TipsSheet({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Tip>>(() => sl<ContentRepository>().sessionTips(session.id)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<Tip>>>();
          return SheetBody(
            title: 'Tips for ${session.title}',
            child: SizedBox(
              height: 320,
              child: AsyncView<List<Tip>>(
                state: cubit.state,
                onRetry: cubit.load,
                builder: (tips) => tips.isEmpty
                    ? const MessageView(icon: AppIcons.gift, title: 'No tips yet', message: 'Fans can tip you while you’re live.')
                    : ListView.separated(
                  itemCount: tips.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (_, i) => TipTile(tip: tips[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Change a session's cover, title, description, length and seats.
class _EditSessionSheet extends StatefulWidget {
  const _EditSessionSheet({required this.session});

  final LiveSession session;

  @override
  State<_EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends State<_EditSessionSheet> {
  late final _title = TextEditingController(text: widget.session.title);
  late final _description = TextEditingController(text: widget.session.description);
  late final _duration = TextEditingController(text: '${widget.session.durationMinutes}');
  late final _seats = TextEditingController(text: '${widget.session.maxParticipants}');
  PickedMedia? _cover;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    final seats = int.tryParse(_seats.text.trim());
    if (_title.text.trim().length < 3) {
      AppSnackbar.error(context, 'Title needs at least 3 characters');
      return;
    }
    if (duration == null || duration < 5 || duration > 480) {
      AppSnackbar.error(context, 'Length must be 5–480 minutes');
      return;
    }
    if (seats == null || seats < 1) {
      AppSnackbar.error(context, 'Enter how many people can join');
      return;
    }
    final repo = sl<ContentRepository>();
    final ok = await context.read<ActionCubit>().run('save', () async {
      final coverUrl = _cover == null ? null : await repo.uploadSessionBanner(_cover!);
      await repo.updateSession(
        widget.session.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        durationMinutes: duration,
        maxParticipants: seats,
        coverImageUrl: coverUrl,
      );
      return true;
    }, success: 'Session updated');
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final current = widget.session.coverImageUrl;
    return SheetBody(
      title: 'Edit session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([_title, _duration]),
            builder: (context, _) => ImageUploadBox(
              slot: ImageSlot.meetPoster,
              picked: _cover,
              url: current,
              enabled: !busy,
              onPick: () async {
                final picked = await sl<MediaPicker>().image();
                if (picked != null) setState(() => _cover = picked);
              },
              previewBuilder: (context, image) => MeetPosterPreview(
                image: image,
                title: _title.text.trim(),
                when: widget.session.scheduledAt,
                durationMinutes: int.tryParse(_duration.text.trim()) ?? widget.session.durationMinutes,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: 'Title', controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Description', controller: _description, minLines: 2, maxLines: 5, maxLength: 1000, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppTextField(label: 'Length (min)', controller: _duration, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(label: 'Seats', controller: _seats, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Save changes', isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}

/// Move a session to a new date and time. People who booked get a notification.
class _PostponeSheet extends StatefulWidget {
  const _PostponeSheet({required this.session});

  final LiveSession session;

  @override
  State<_PostponeSheet> createState() => _PostponeSheetState();
}

class _PostponeSheetState extends State<_PostponeSheet> {
  DateTime? _when;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final start = widget.session.scheduledAt.isAfter(now) ? widget.session.scheduledAt : now;
    final date = await showDatePicker(context: context, initialDate: start.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 180)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(widget.session.scheduledAt));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      if (mounted) AppSnackbar.error(context, 'Pick a time at least 5 minutes from now');
      return;
    }
    setState(() => _when = picked);
  }

  Future<void> _save() async {
    if (_when == null) {
      AppSnackbar.error(context, 'Pick the new date and time');
      return;
    }
    final ok = await context.read<ActionCubit>().run('postpone', () async {
      await sl<ContentRepository>().updateSession(widget.session.id, scheduledAt: _when, rescheduleNote: _note.text.trim());
      return true;
    }, success: widget.session.bookedCount > 0 ? 'Moved — everyone who booked has been told' : 'Session moved');
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final palette = context.palette;
    return SheetBody(
      title: 'Postpone session',
      subtitle: 'Now: ${Fmt.weekdayDateTime(widget.session.scheduledAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : _pick,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _when == null ? palette.border : palette.textPrimary, width: _when == null ? 1 : 1.5),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.calendar, color: palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _when == null ? 'Pick new date & time' : Fmt.weekdayDateTime(_when!),
                      style: context.text.titleSmall?.copyWith(color: _when == null ? palette.textSecondary : palette.textPrimary),
                    ),
                  ),
                  Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Message to attendees (optional)', hint: 'Sorry for the change — see you then!', controller: _note, maxLength: 300, minLines: 2, maxLines: 3),
          if (widget.session.bookedCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${widget.session.bookedCount} people booked this. They’ll get a notification with the new time.', style: context.text.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Move session', icon: AppIcons.calendar, isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}

/// The home "Online sessions" card, drawn over a poster — used for the
/// upload preview and the session list so all three look the same.
class MeetPosterPreview extends StatelessWidget {
  const MeetPosterPreview({super.key, required this.image, required this.title, required this.when, required this.durationMinutes, this.isLive = false});

  final Widget image;
  final String title;
  final DateTime? when;
  final int durationMinutes;
  final bool isLive;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final w = when?.toLocal();
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x00000000), Color(0xE6000000)],
              stops: [0, 0.35, 1],
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text(w == null ? 'SOON' : _months[w.month - 1], style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                Text(w == null ? '—' : '${w.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: isLive ? AppColors.error : Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.videoCamera, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(isLive ? 'LIVE' : 'Online session', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.isEmpty ? 'Your session title shows here' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: title.isEmpty ? Colors.white70 : Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You${w == null ? '' : ' · ${TimeOfDay.fromDateTime(w).format(context)}'} · $durationMinutes min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(isLive ? 'Rejoin' : 'Start meeting', style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// History: past sessions with how many came and how long they stayed.
// ---------------------------------------------------------------------------

class _HistoryTab extends StatefulWidget {
  const _HistoryTab({super.key});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> with AutomaticKeepAliveClientMixin {
  late final PagedCubit<PastSession> _cubit = PagedCubit<PastSession>(MeetHostApi.sessionHistory);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PagedListView<PastSession>(
      cubit: _cubit,
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 96),
      empty: const MessageView(
        icon: AppIcons.clock,
        title: 'No past sessions yet',
        message: 'Sessions you’ve hosted show up here, with who attended and for how long.',
      ),
      itemBuilder: (context, s) => _HistoryCard(session: s),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.session});

  final PastSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final palette = context.palette;
    final ended = s.status == 'ended';
    final (label, color) = switch (s.status) {
      'cancelled' => ('Cancelled', AppColors.error),
      'missed' => ('Not started', palette.textSecondary),
      _ => ('Ended', AppColors.success),
    };
    final when = s.scheduledAt == null ? '' : Fmt.weekdayDateTime(s.scheduledAt!.toLocal());
    final price = s.isFree ? 'Free' : Fmt.money(s.price);

    return AppCard(
      onTap: ended ? () => showAttendanceSheet(context, title: s.title, load: () => MeetHostApi.meetAttendance(s.id)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: s.coverUrl.isEmpty
                      ? const DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3B1E5E), Color(0xFF1B1B3A)])),
                    child: Center(child: Icon(AppIcons.videoCamera, color: Colors.white38, size: 22)),
                  )
                      : AppNetworkImage(url: s.coverUrl),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text('$when · ${s.durationMinutes} min · $price', style: context.text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              StatusChip(label: label, color: color),
            ],
          ),
          if (ended) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _HistoryStat(value: s.bookedCount > 0 ? '${s.attended}/${s.bookedCount}' : '${s.attended}', label: 'Attended'),
                const SizedBox(width: AppSpacing.xs),
                _HistoryStat(value: s.attended == 0 ? '—' : watchTime(s.averageSeconds), label: 'Avg. time'),
                const SizedBox(width: AppSpacing.xs),
                _HistoryStat(value: s.watchedSeconds == 0 ? '—' : watchTime(s.watchedSeconds), label: 'Total time'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('See who attended', style: context.text.labelMedium?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                Icon(AppIcons.chevronRight, size: 16, color: palette.textSecondary),
              ],
            ),
          ] else if (s.status == 'missed' && s.bookedCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${s.bookedCount} people had booked this session', style: context.text.bodySmall?.copyWith(color: palette.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _HistoryStat extends StatelessWidget {
  const _HistoryStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: context.palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}