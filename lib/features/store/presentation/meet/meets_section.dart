import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Virtual Meets on a store page. Tap opens the meet, where people book and join in-app.
class MeetsSection extends StatelessWidget {
  const MeetsSection({super.key, required this.meets, required this.isOwner});

  final List<StoreMeet> meets;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in meets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(AppRoutes.meetDetail(m.id)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: SizedBox(width: 64, height: 64, child: StoreImage(url: m.coverUrl, icon: AppIcons.videoCamera)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                            Text(
                              [
                                if (m.scheduledAt != null) Fmt.weekdayDateTime(m.scheduledAt!.toLocal()),
                                if (m.durationMinutes > 0) '${m.durationMinutes} min',
                                m.isFree ? 'Free' : Fmt.money(m.price),
                                if (m.spotsLeft != null) '${m.spotsLeft} spots left',
                              ].join(' · '),
                              style: context.text.bodySmall,
                            ),
                            if (m.isLive) Text('Happening now — tap to join', style: context.text.labelSmall?.copyWith(color: AppColors.error)),
                          ],
                        ),
                      ),
                      Icon(AppIcons.chevronRight, color: palette.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}