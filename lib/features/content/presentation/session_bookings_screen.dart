// File: lib/features/content/presentation/session_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../store/data/meet_host_api.dart';

const _liveRed = Color(0xFFFF3B5C);

enum _Show {
  all('Everyone', 'All people who booked', AppIcons.users),
  today('New today', 'Only bookings from today', AppIcons.sparkle);

  const _Show(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

/// Host view: everyone who booked a live session — how many, seats left,
/// what it earned and each person with when they booked.
/// Calm look: white cards, dark text; the filter icon shows New today.
class SessionBookingsScreen extends StatefulWidget {
  const SessionBookingsScreen({super.key, required this.sessionId, required this.title});

  final String sessionId;
  final String title;

  static Future<void> open(BuildContext context, {required String sessionId, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionBookingsScreen(sessionId: sessionId, title: title)));

  @override
  State<SessionBookingsScreen> createState() => _SessionBookingsScreenState();
}

class _SessionBookingsScreenState extends State<SessionBookingsScreen> {
  SessionBookings? _data;
  String? _error;
  _Show _show = _Show.all;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await MeetHostApi.bookings(widget.sessionId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t load bookings. Try again.');
    }
  }

  Future<void> _pickShow() async {
    HapticFeedback.selectionClick();
    final picked = await showAppSheet<_Show>(
      context,
      builder: (sheet) => SheetBody(
        title: 'Show',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _Show.values) ...[
              _Option(show: s, selected: s == _show, onTap: () => Navigator.of(sheet).pop(s)),
              if (s != _Show.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _show = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Bookings', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: d == null ? null : _pickShow,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(AppIcons.sliders, color: palette.textPrimary),
                if (_show != _Show.all)
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
      body: _error != null && d == null
          ? ErrorView(message: _error!, onRetry: _fetch)
          : d == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: _fetch,
        child: _body(context, d),
      ),
    );
  }

  Widget _body(BuildContext context, SessionBookings d) {
    final palette = context.palette;
    final people = _show == _Show.today ? d.people.where((p) => p.isNew).toList() : d.people;
    final fill = d.maxParticipants == 0 ? 0.0 : (d.booked / d.maxParticipants).clamp(0.0, 1.0);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
      children: [
        // Summary — white card.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: _frame(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.title.isEmpty ? widget.title : d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.2, color: palette.textPrimary),
              ),
              if (d.scheduledAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (d.isLive) ...[
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle))
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 1, end: 0.3, duration: 700.ms),
                      const SizedBox(width: 6),
                    ] else ...[
                      Icon(AppIcons.calendar, size: 13, color: palette.textSecondary),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      d.isLive ? 'Live now' : Fmt.weekdayDateTime(d.scheduledAt!.toLocal()),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: d.isLive ? _liveRed : palette.textSecondary),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${d.booked}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1, letterSpacing: -0.8, color: palette.textPrimary)),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 3),
                    child: Text(d.maxParticipants > 0 ? '/ ${d.maxParticipants} booked' : 'booked', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textSecondary)),
                  ),
                  const Spacer(),
                  if (d.bookedToday > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                      child: Text('+${d.bookedToday} today', style: const TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fill),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: palette.surfaceMuted, color: AppColors.success),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _StatBox(label: 'Seats left', value: '${d.seatsLeft}'),
                  const SizedBox(width: 8),
                  _StatBox(label: 'Earned', value: d.isFree ? 'Free' : Fmt.money(d.earned)),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06),
        const SizedBox(height: 22),

        // List title
        Row(
          children: [
            Text(_show == _Show.today ? 'Booked today' : 'People who booked', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
            const SizedBox(width: 6),
            Text('· ${people.length}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.textTertiary)),
          ],
        ),
        const SizedBox(height: 10),

        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 44),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
                  child: Icon(AppIcons.users, size: 30, color: palette.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(_show == _Show.today ? 'No bookings today' : 'No bookings yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  _show == _Show.today ? 'New bookings from today show up here.' : 'Share your session — everyone who books shows up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
                if (_show == _Show.today && d.people.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () => setState(() => _show = _Show.all),
                    style: OutlinedButton.styleFrom(foregroundColor: palette.textPrimary, side: BorderSide(color: palette.border), shape: const StadiumBorder()),
                    child: Text('See everyone · ${d.people.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          )
        else
          Container(
            decoration: _frame(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < people.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 66, color: palette.border.withValues(alpha: 0.8)),
                  _PersonRow(person: people[i], free: d.isFree).animate(delay: (30 * i.clamp(0, 12)).ms).fadeIn(duration: 240.ms).slideX(begin: 0.04),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// White card, thin grey border, soft shadow.
BoxDecoration _frame(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.8)),
  boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
);

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: palette.textPrimary)),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// One choice in the filter sheet: icon, name, one line, radio.
class _Option extends StatelessWidget {
  const _Option({required this.show, required this.selected, required this.onTap});

  final _Show show;
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
                child: Icon(show.icon, size: 18, color: palette.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(show.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(show.hint, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
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

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.free});

  final SessionBooker person;
  final bool free;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = person;
    final isFree = free || p.paid == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          UserAvatar(initials: _initials(p.name), imageUrl: p.avatarUrl.isEmpty ? null : p.avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary))),
                    if (p.isNew) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                        child: const Text('NEW', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.success, letterSpacing: 0.4)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  p.bookedAt == null ? 'Booked' : 'Booked ${Fmt.relative(p.bookedAt!.toLocal())}',
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(99)),
            child: Text(
              isFree ? 'Free' : Fmt.money(p.paid),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isFree ? palette.textSecondary : palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}