// File: lib/features/store/presentation/meet/meets_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/models/common_models.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

const _liveRed = Color(0xFFFF3B5C);
const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

enum _Filter {
  upcoming('upcoming', 'Upcoming', 'Sessions you can book', AppIcons.calendar),
  live('live', 'Live now', 'Happening right now', AppIcons.broadcast),
  booked('booked', 'Booked', 'Sessions you’ve booked', AppIcons.checkCircle);

  const _Filter(this.value, this.label, this.hint, this.icon);
  final String value;
  final String label;
  final String hint;
  final IconData icon;
}

/// Discover other creators' live sessions.
/// Big title · Upcoming / Live now / Booked (chips + filter button) ·
/// a "Next up" spotlight with a live countdown · then ticket-style cards,
/// 10 to a row, each row swiping sideways. Sessions I host are managed
/// from My store → Live sessions.
class MeetsScreen extends StatefulWidget {
  const MeetsScreen({super.key});

  @override
  State<MeetsScreen> createState() => _MeetsScreenState();
}

class _MeetsScreenState extends State<MeetsScreen> {
  static const _perRow = 10;
  _Filter _filter = _Filter.upcoming;
  late final PagedCubit<StoreMeet> _cubit = PagedCubit<StoreMeet>((page) => _othersOnly(_filter.value, page));
  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  /// Same page from the server, without the sessions I host myself.
  static Future<Paged<StoreMeet>> _othersOnly(String tab, int page) async {
    final p = await sl<StoreRepository>().meets(tab: tab, page: page);
    return Paged(items: p.items.where((m) => !m.isHost).toList(), page: p.page, pages: p.pages, total: p.total);
  }

  @override
  void dispose() {
    _cubit.close();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(_Filter f) {
    if (f == _filter) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = f);
    _cubit.updateQuery((page) => _othersOnly(f.value, page));
  }

  Future<void> _pickFilter() async {
    HapticFeedback.selectionClick();
    final picked = await showAppSheet<_Filter>(
      context,
      builder: (sheet) => SheetBody(
        title: 'Show sessions',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in _Filter.values) ...[
              _FilterOption(filter: f, selected: f == _filter, onTap: () => Navigator.of(sheet).pop(f)),
              if (f != _Filter.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) _setFilter(picked);
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  bool _matches(StoreMeet m) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return m.title.toLowerCase().contains(q) || m.hostName.toLowerCase().contains(q);
  }

  String _rowTitle(int row) => switch (_filter) {
    _Filter.upcoming => row == 0 ? 'Starting soon' : 'More upcoming',
    _Filter.live => row == 0 ? 'Live now' : 'More live',
    _Filter.booked => row == 0 ? 'Your sessions' : 'More booked',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<PagedCubit<StoreMeet>, PagedState<StoreMeet>>(
        builder: (context, state) {
          final items = state.items.where(_matches).toList();
          final spotlight = _query.isEmpty && items.isNotEmpty ? items.first : null;
          final rest = spotlight == null ? items : items.skip(1).toList();
          final rows = <List<StoreMeet>>[
            for (var i = 0; i < rest.length; i += _perRow) rest.sublist(i, (i + _perRow).clamp(0, rest.length)),
          ];

          return Scaffold(
            backgroundColor: palette.background,
            body: SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 300) _cubit.loadMore();
                  return false;
                },
                child: RefreshIndicator.adaptive(
                  color: AppColors.primary,
                  onRefresh: _cubit.refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      // Top bar: back · search · filter
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Row(
                            children: [
                              _RoundButton(icon: AppIcons.back, onTap: () => Navigator.of(context).maybePop()),
                              const Spacer(),
                              _RoundButton(icon: _searching ? AppIcons.close : AppIcons.search, onTap: _toggleSearch),
                              const SizedBox(width: 10),
                              _RoundButton(icon: AppIcons.sliders, dot: _filter != _Filter.upcoming, onTap: _pickFilter),
                            ],
                          ),
                        ),
                      ),
                      // Title
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter + 4, 16, AppSpacing.gutter, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Live sessions', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.9, height: 1.1, color: palette.textPrimary)),
                              const SizedBox(height: 4),
                              Text('Learn live with creators you love', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                            ],
                          ),
                        ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1),
                      ),
                      // Search
                      SliverToBoxAdapter(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: !_searching
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 0),
                            child: _SearchField(controller: _search, onChanged: (v) => setState(() => _query = v.trim())),
                          ),
                        ),
                      ),
                      // Chips
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 58,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 4),
                            children: [
                              for (final f in _Filter.values)
                                _FilterChip(filter: f, selected: f == _filter, count: f == _filter && !state.isLoading ? state.items.length : null, onTap: () => _setFilter(f)),
                            ],
                          ),
                        ),
                      ),

                      if (state.isFirstLoad)
                        const SliverToBoxAdapter(child: _Skeleton())
                      else if (state.items.isEmpty && state.errorMessage != null)
                        SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.errorMessage!, onRetry: _cubit.refresh))
                      else if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: MessageView(
                              icon: _query.isNotEmpty ? AppIcons.search : _filter.icon,
                              title: _query.isNotEmpty
                                  ? 'No match'
                                  : switch (_filter) {
                                _Filter.live => 'Nobody is live right now',
                                _Filter.booked => 'No sessions booked',
                                _ => 'No upcoming sessions',
                              },
                              message: _query.isNotEmpty
                                  ? 'Try another name.'
                                  : (_filter == _Filter.booked ? 'Sessions you book show up here.' : 'Check back soon — creators add new sessions often.'),
                            ),
                          )
                        else ...[
                            if (spotlight != null)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 4),
                                  child: _Spotlight(meet: spotlight, filter: _filter, onReturn: _cubit.refresh),
                                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
                              ),
                            for (final (r, row) in rows.indexed) ...[
                              SliverToBoxAdapter(child: _RowHeader(title: _query.isNotEmpty ? 'Results' : _rowTitle(r), swipe: row.length > 1)),
                              SliverToBoxAdapter(
                                child: _TicketRow(
                                  key: PageStorageKey('${_filter.value}-$r'),
                                  items: row,
                                  onReturn: _cubit.refresh,
                                  onEnd: r == rows.length - 1 ? _cubit.loadMore : null,
                                ),
                              ),
                            ],
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                                child: Center(
                                  child: state.isLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                      SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _openMeet(BuildContext context, StoreMeet m, Future<void> Function() onReturn) async {
  HapticFeedback.selectionClick();
  await context.push(AppRoutes.meetDetail(m.id));
  await onReturn();
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

// ---------------------------------------------------------------------------
// Top bar pieces
// ---------------------------------------------------------------------------

/// White round button with a thin border (back / search / filter).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.dot = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: palette.surface,
          shape: CircleBorder(side: BorderSide(color: palette.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 19, color: palette.textPrimary)),
          ),
        ),
        if (dot)
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2)),
            ).animate().scale(begin: const Offset(0.4, 0.4), curve: Curves.easeOutBack, duration: 300.ms),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: palette.border)),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 18, color: palette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14.5, color: palette.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search sessions or creators',
                hintStyle: TextStyle(fontSize: 14.5, color: palette.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter, required this.selected, required this.onTap, this.count});

  final _Filter filter;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.06) : palette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (filter == _Filter.live) ...[
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fade(begin: 1, end: 0.3, duration: 700.ms),
                const SizedBox(width: 6),
              ],
              Text(
                count == null ? filter.label : '${filter.label} · $count',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.primary : palette.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({required this.filter, required this.selected, required this.onTap});

  final _Filter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = filter == _Filter.live ? _liveRed : palette.textPrimary;
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
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Icon(filter.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(filter.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(filter.hint, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
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

// ---------------------------------------------------------------------------
// Spotlight ("Next up")
// ---------------------------------------------------------------------------

class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.meet, required this.filter, required this.onReturn});

  final StoreMeet meet;
  final _Filter filter;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = meet;
    final when = m.scheduledAt?.toLocal();
    final full = m.spotsLeft != null && m.spotsLeft! <= 0 && !m.booked;
    final label = m.isLive ? 'LIVE NOW' : (filter == _Filter.booked ? 'YOUR NEXT SESSION' : 'NEXT UP');
    final button = m.booked ? (m.isLive ? 'Join now' : 'View') : (full ? 'Full' : (m.isLive ? 'Join' : 'Book seat'));

    return _Pressable(
      onTap: () => _openMeet(context, m, onReturn),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
          boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 30, offset: Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoreImage(url: m.coverUrl, icon: AppIcons.videoCamera),
                  Positioned(left: 14, top: 14, child: m.isLive ? const _LivePill(big: true) : _CalendarBadge(date: when)),
                  Positioned(right: 14, top: 14, child: _WhiteChip(icon: AppIcons.clock, label: '${m.durationMinutes} min')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: m.isLive ? _liveRed : AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.25, color: palette.textPrimary)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      UserAvatar(initials: _initials(m.hostName), imageUrl: m.hostAvatarUrl.isEmpty ? null : m.hostAvatarUrl, size: 26),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.hostName.isEmpty ? 'Creator' : m.hostName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.textPrimary),
                        ),
                      ),
                      if (when != null && !m.isLive) Text(Fmt.time(when), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textSecondary)),
                    ],
                  ),
                  if (!m.isLive && when != null && when.isAfter(DateTime.now())) ...[
                    const SizedBox(height: 14),
                    _Countdown(to: when),
                  ],
                  const SizedBox(height: 14),
                  _Dashed(color: palette.border),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: m.booked ? 'Booked ✓' : (m.isFree ? 'Free' : Fmt.money(m.price)),
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: m.booked ? AppColors.success : palette.textPrimary),
                              ),
                              if (!m.booked && m.spotsLeft != null)
                                TextSpan(
                                  text: m.spotsLeft! > 0 ? '  ·  ${m.spotsLeft} seats left' : '  ·  Fully booked',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textSecondary),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: m.isLive ? _liveRed : (full ? palette.surfaceMuted : AppColors.primary),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openMeet(context, m, onReturn),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                            child: Text(button, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: full ? palette.textSecondary : Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Days · hours · min · sec, ticking.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.to});

  final DateTime to;

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
      if (left.isNegative) _timer?.cancel();
      if (mounted) setState(() => _left = left.isNegative ? Duration.zero : left);
    });
  }

  @override
  void didUpdateWidget(_Countdown old) {
    super.didUpdateWidget(old);
    _left = widget.to.difference(DateTime.now());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final parts = [(_left.inDays, 'days'), (_left.inHours % 24, 'hours'), (_left.inMinutes % 60, 'min'), (_left.inSeconds % 60, 'sec')];
    return Row(
      children: [
        for (final (i, p) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: palette.background, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(a), child: child),
                    ),
                    child: Text(
                      p.$1.toString().padLeft(2, '0'),
                      key: ValueKey('${p.$2}${p.$1}'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()], color: palette.textPrimary),
                    ),
                  ),
                  Text(p.$2, style: TextStyle(fontSize: 10, color: palette.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rows of ticket cards
// ---------------------------------------------------------------------------

class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, required this.swipe});

  final String title;
  final bool swipe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter + 4, 22, AppSpacing.gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary))),
          if (swipe)
            Row(
              children: [
                Text('Swipe', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textTertiary)),
                Icon(AppIcons.chevronRight, size: 14, color: palette.textTertiary),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms);
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({super.key, required this.items, required this.onReturn, this.onEnd});

  final List<StoreMeet> items;
  final Future<void> Function() onReturn;

  /// Last row only: swiped to its end → load the next page.
  final VoidCallback? onEnd;

  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return _Ticket.coverHeight + 28 + 92 * scale;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (onEnd != null && n.metrics.axis == Axis.horizontal && n.metrics.pixels > n.metrics.maxScrollExtent - 200) onEnd!();
          return false;
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, i) => _Ticket(meet: items[i], onReturn: onReturn)
              .animate(delay: (50 * i.clamp(0, 6)).ms)
              .fadeIn(duration: 320.ms)
              .slideX(begin: 0.12, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

/// Ticket-style card: cover with date (or LIVE), host photo on the edge,
/// title, host · length, a dashed tear line with side notches, then time
/// and price / status.
class _Ticket extends StatelessWidget {
  const _Ticket({required this.meet, required this.onReturn});

  final StoreMeet meet;
  final Future<void> Function() onReturn;

  static const double width = 232;
  static const double coverHeight = 128;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = meet;
    final when = m.scheduledAt?.toLocal();
    final full = m.spotsLeft != null && m.spotsLeft! <= 0 && !m.booked;
    final fewLeft = !m.booked && m.spotsLeft != null && m.spotsLeft! > 0 && m.spotsLeft! <= 10;

    final left = m.isLive ? (m.booked ? 'Booked ✓' : 'Live now') : (when == null ? 'Soon' : Fmt.time(when));
    final leftColor = m.isLive && m.booked ? AppColors.success : (m.isLive ? _liveRed : palette.textSecondary);
    final (right, rightColor) = m.booked
        ? (m.isLive ? ('Join now ›', _liveRed) : ('Booked ✓', AppColors.success))
        : full
        ? ('Full', palette.textTertiary)
        : fewLeft
        ? ('${m.spotsLeft} seats left', AppColors.warning)
        : (m.isFree ? 'Free' : Fmt.money(m.price), palette.textPrimary);

    return _Pressable(
      onTap: () => _openMeet(context, m, onReturn),
      child: SizedBox(
        width: width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
                boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    child: SizedBox(
                      height: coverHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StoreImage(url: m.coverUrl, icon: AppIcons.videoCamera),
                          Positioned(left: 10, top: 10, child: m.isLive ? const _LivePill() : _CalendarBadge(date: when, small: true)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '${m.hostName.isEmpty ? 'Creator' : m.hostName} · ${m.durationMinutes} min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        _Dashed(color: palette.border),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: leftColor))),
                            Text(right, maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: rightColor)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Host photo on the cover's edge.
            Positioned(
              left: 14,
              top: coverHeight - 17,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                child: UserAvatar(initials: _initials(m.hostName), imageUrl: m.hostAvatarUrl.isEmpty ? null : m.hostAvatarUrl, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// White calendar tile: "OCT / 29".
class _CalendarBadge extends StatelessWidget {
  const _CalendarBadge({required this.date, this.small = false});

  final DateTime? date;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final d = date;
    return Container(
      width: small ? 44 : 52,
      padding: EdgeInsets.symmetric(vertical: small ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(small ? 11 : 14),
        boxShadow: const [BoxShadow(color: Color(0x26101828), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text(d == null ? 'SOON' : _months[d.month - 1], style: TextStyle(fontSize: small ? 9 : 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.primary)),
          Text(d == null ? '—' : '${d.day}'.padLeft(2, '0'), style: TextStyle(fontSize: small ? 18 : 22, fontWeight: FontWeight.w800, height: 1.05, color: const Color(0xFF1D2939))),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({this.big = false});

  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 8, vertical: big ? 5 : 4),
      decoration: BoxDecoration(
        color: _liveRed,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [BoxShadow(color: _liveRed.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 1, end: 0.3, duration: 650.ms),
          const SizedBox(width: 5),
          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: big ? 12 : 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _WhiteChip extends StatelessWidget {
  const _WhiteChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFF475467)),
            const SizedBox(width: 4),
          ],
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF344054))),
        ],
      ),
    );
  }
}

/// A dashed "tear here" line.
class _Dashed extends StatelessWidget {
  const _Dashed({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 5.0;
        const gap = 4.0;
        final count = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              Container(width: dash, height: 1.2, color: color),
              if (i < count - 1) const SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

/// Shrinks a little while pressed.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget box(double w, double h, [double r = 12]) => Container(width: w, height: h, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(r)));
    final width = MediaQuery.sizeOf(context).width - AppSpacing.gutter * 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(width, width * 9 / 16 + 170, 24),
          const SizedBox(height: 26),
          box(140, 16),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [box(232, 220, 20), const SizedBox(width: 14), box(232, 220, 20)]),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}