import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Discover Virtual Meets: live now, upcoming, and the ones I booked.
class MeetsScreen extends StatelessWidget {
  const MeetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Online Session'),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: palette.textSecondary,
            indicatorColor: AppColors.primary,
            dividerColor: palette.border,
            tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Live now'), Tab(text: 'My meetings')],
          ),
        ),
        body: const TabBarView(children: [_MeetList(tab: 'upcoming'), _MeetList(tab: 'live'), _MeetList(tab: 'booked')]),
      ),
    );
  }
}

class _MeetList extends StatelessWidget {
  const _MeetList({required this.tab});

  final String tab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PagedCubit<StoreMeet>((page) => sl<StoreRepository>().meets(tab: tab, page: page)),
      child: Builder(
        builder: (context) => PagedListView<StoreMeet>(
          cubit: context.read<PagedCubit<StoreMeet>>(),
          spacing: AppSpacing.sm,
          empty: MessageView(
            icon: AppIcons.videoCamera,
            title: switch (tab) {
              'live' => 'Nobody is live right now',
              'booked' => 'No meetings booked',
              _ => 'No upcoming meetings',
            },
            message: tab == 'booked' ? 'Meetings you book show up here.' : 'Check back soon — creators add new meetings often.',
          ),
          itemBuilder: (context, m) => _MeetCard(meet: m, onReturn: () => context.read<PagedCubit<StoreMeet>>().refresh()),
        ),
      ),
    );
  }
}

class _MeetCard extends StatelessWidget {
  const _MeetCard({required this.meet, required this.onReturn});

  final StoreMeet meet;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = meet;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push(AppRoutes.meetDetail(m.id));
          onReturn();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(width: 84, height: 84, child: StoreImage(url: m.coverUrl, icon: AppIcons.videoCamera)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(m.isHost ? 'You’re hosting' : m.hostName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (m.scheduledAt != null) Fmt.weekdayDateTime(m.scheduledAt!.toLocal()),
                        m.isFree ? 'Free' : Fmt.money(m.price),
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (m.isLive) const StatusChip(label: 'Live now', color: AppColors.error, icon: AppIcons.broadcast),
                        if (m.booked && !m.isHost) const StatusChip(label: 'Booked', color: AppColors.success),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04);
  }
}