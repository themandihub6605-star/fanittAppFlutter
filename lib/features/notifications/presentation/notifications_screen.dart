import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../../core/enums/user_role.dart';
import '../data/notification_repository.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<NotificationFeed>(sl<NotificationRepository>().feed),
      child: const _NotificationsView(),
    );
  }
}

class _NotificationsView extends StatelessWidget {
  const _NotificationsView();

  Future<void> _markAll(BuildContext context, NotificationFeed feed) async {
    final cubit = context.read<LoadCubit<NotificationFeed>>();
    cubit.replace(NotificationFeed(items: [for (final n in feed.items) n.markRead()], unreadCount: 0));
    try {
      await sl<NotificationRepository>().markAllRead();
    } catch (_) {
      cubit.refresh();
    }
  }

  Future<void> _open(BuildContext context, NotificationFeed feed, AppNotification item) async {
    final cubit = context.read<LoadCubit<NotificationFeed>>();
    if (!item.isRead) {
      cubit.replace(NotificationFeed(
        items: [for (final n in feed.items) n.id == item.id ? n.markRead() : n],
        unreadCount: feed.unreadCount > 0 ? feed.unreadCount - 1 : 0,
      ));
      sl<NotificationRepository>().markRead(item.id).ignore();
    }

    final auth = context.read<AuthBloc>().state;
    final role = auth is AuthAuthenticated ? auth.user.role : null;
    final id = item.relatedId;
    if (id == null) return;
    switch (item.relatedModel) {
      case 'Campaign':
        context.push(role == UserRole.brand ? AppRoutes.manageCampaign(id) : AppRoutes.campaignDetail(id));
      case 'Conversation':
        context.push(AppRoutes.chat(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<NotificationFeed>>();
    final feed = cubit.state.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (feed != null && feed.unreadCount > 0)
            TextButton(onPressed: () => _markAll(context, feed), child: const Text('Mark all read')),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncView<NotificationFeed>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (feed) => AppRefresh(
          onRefresh: cubit.refresh,
          child: feed.items.isEmpty
              ? const ScrollableMessage(
                  child: MessageView(icon: AppIcons.bell, title: 'You’re all caught up', message: 'Updates on proposals, payments and messages appear here.'),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: feed.items.length,
                  separatorBuilder: (_, _) => const Divider(indent: 72),
                  itemBuilder: (context, index) {
                    final item = feed.items[index];
                    return _NotificationTile(item: item, onTap: () => _open(context, feed, item));
                  },
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  IconData get _icon => switch (item.type) {
        'new_message' => AppIcons.messages,
        'proposal_received' || 'proposal_status_update' => AppIcons.paperPlane,
        'milestone_funded' || 'payout_released' || 'payment_success' => AppIcons.wallet,
        'milestone_submitted' || 'milestone_changes_requested' || 'campaign_update' => AppIcons.campaigns,
        'dispute_raised' || 'dispute_refund' => AppIcons.warning,
        'follow' => AppIcons.userPlus,
        'like' => AppIcons.heart,
        'gift_received' || 'donation_received' => AppIcons.gift,
        'account_verified' => AppIcons.sealCheck,
        _ => AppIcons.bell,
      };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: item.isRead ? null : palette.primarySoft.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.isRead ? palette.surfaceMuted : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(_icon, size: 20, color: item.isRead ? palette.textSecondary : AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.title, style: context.text.titleSmall)),
                      Text(Fmt.relative(item.createdAt), style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.message, style: context.text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
