// File: lib/features/store/presentation/meet/attendance_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/meet_host_api.dart';

/// "Who attended" for the host: how many came, who, and how long each stayed.
Future<void> showAttendanceSheet(BuildContext context, {required String title, required Future<AttendanceReport> Function() load}) {
  return showAppSheet<void>(context, builder: (_) => _AttendanceSheet(title: title, load: load));
}

class _AttendanceSheet extends StatefulWidget {
  const _AttendanceSheet({required this.title, required this.load});

  final String title;
  final Future<AttendanceReport> Function() load;

  @override
  State<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<_AttendanceSheet> {
  AttendanceReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final r = await widget.load();
      if (mounted) setState(() {
        _report = r;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t load who attended. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who attended', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ...[
                Text(_error!, style: context.text.bodyMedium?.copyWith(color: AppColors.error)),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(onPressed: _fetch, child: const Text('Try again')),
              ] else if (r == null)
                const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator.adaptive()))
              else ...[
                  Row(
                    children: [
                      _Stat(label: 'Attended', value: r.booked == null ? '${r.totalPeople}' : '${r.totalPeople} / ${r.booked}', color: AppColors.primary),
                      const SizedBox(width: AppSpacing.xs),
                      _Stat(label: 'In now', value: '${r.inRoomNow}', color: AppColors.success),
                      const SizedBox(width: AppSpacing.xs),
                      _Stat(label: 'Avg. time', value: r.totalPeople == 0 ? '—' : watchTime(r.averageSeconds), color: AppColors.info),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (r.people.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Column(
                        children: [
                          Icon(AppIcons.users, size: 40, color: palette.textTertiary),
                          const SizedBox(height: AppSpacing.sm),
                          Text('No one has joined yet', style: context.text.titleSmall),
                          const SizedBox(height: 2),
                          Text('People show up here as soon as they join.', style: context.text.bodySmall),
                        ],
                      ),
                    )
                  else
                    Flexible(
                      child: RefreshIndicator.adaptive(
                        color: AppColors.primary,
                        onRefresh: _fetch,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: r.people.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: palette.border),
                          itemBuilder: (context, i) => _PersonRow(person: r.people[i], longest: r.people.first.watchedSeconds)
                              .animate(delay: (30 * i).ms)
                              .fadeIn(duration: 220.ms),
                        ),
                      ),
                    ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
            Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.longest});

  final AttendancePerson person;
  final int longest;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final palette = context.palette;
    final joined = p.firstJoinedAt == null ? '' : 'Joined ${Fmt.time(p.firstJoinedAt!.toLocal())}';
    final visits = p.visits > 1 ? ' · joined ${p.visits} times' : '';
    final share = longest == 0 ? 0.0 : (p.watchedSeconds / longest).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          UserAvatar(initials: p.name.isEmpty ? '?' : p.name[0].toUpperCase(), imageUrl: p.avatarUrl.isEmpty ? null : p.avatarUrl, size: 40),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                    if (p.inRoomNow) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: const Text('In now', style: TextStyle(color: AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('$joined$visits', style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: share, minHeight: 4, backgroundColor: palette.surfaceMuted, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(watchTime(p.watchedSeconds), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('watched', style: context.text.bodySmall?.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}