import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';
import 'community_paid_join.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<CommunityRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PagedCubit<Community>((page) => repo.list(page: page))),
        BlocProvider(create: (_) => LoadCubit<List<Community>>(repo.mine)),
      ],
      child: const _CommunitiesView(),
    );
  }
}

class _CommunitiesView extends StatefulWidget {
  const _CommunitiesView();

  @override
  State<_CommunitiesView> createState() => _CommunitiesViewState();
}

class _CommunitiesViewState extends State<_CommunitiesView> {
  final _search = TextEditingController();
  Timer? _debounce;
  CommunitySort _sort = CommunitySort.trending;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    final repo = sl<CommunityRepository>();
    final text = _search.text.trim();
    final sort = _sort;
    context.read<PagedCubit<Community>>().updateQuery((page) => repo.list(page: page, search: text, sort: sort));
  }

  Future<void> _create() async {
    final created = await context.push<Community>(AppRoutes.communityForm);
    if (created == null || !mounted) return;
    context.read<LoadCubit<List<Community>>>().refresh();
    _reload();
    context.push(AppRoutes.communityDetail(created.slug));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communities'),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: palette.textSecondary,
            labelStyle: context.text.labelLarge,
            indicatorColor: AppColors.primary,
            dividerColor: palette.border,
            tabs: const [Tab(text: 'Discover'), Tab(text: 'Joined')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'create-community',
          onPressed: _create,
          icon: const Icon(AppIcons.plus),
          label: const Text('Create'),
        ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack),
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xs),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), _reload);
                    },
                    decoration: const InputDecoration(hintText: 'Search communities', prefixIcon: Icon(AppIcons.search, size: 20)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ChoicePills<CommunitySort>(
                    scrollable: true,
                    options: CommunitySort.values,
                    selected: {_sort},
                    labelOf: (s) => s.label,
                    onChanged: (s) {
                      setState(() => _sort = s);
                      _reload();
                    },
                  ),
                ),
                Expanded(
                  child: PagedListView<Community>(
                    cubit: context.read<PagedCubit<Community>>(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
                    spacing: AppSpacing.md,
                    empty: const MessageView(icon: AppIcons.users, title: 'No communities found', message: 'Create the first one for your niche.'),
                    itemBuilder: (context, c) => CommunityCard(community: c),
                  ),
                ),
              ],
            ),
            const _JoinedTab(),
          ],
        ),
      ),
    );
  }
}

class _JoinedTab extends StatelessWidget {
  const _JoinedTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Community>>>();
    return AsyncView<List<Community>>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (items) => AppRefresh(
        onRefresh: cubit.refresh,
        child: items.isEmpty
            ? const ScrollableMessage(
          child: MessageView(icon: AppIcons.users, title: 'No communities yet', message: 'Join or create one to see it here.'),
        )
            : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 96),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => _JoinedTile(community: items[i]),
        ),
      ),
    );
  }
}

class _JoinedTile extends StatelessWidget {
  const _JoinedTile({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    return AppCard(
      onTap: () async {
        await context.push(AppRoutes.communityDetail(c.slug));
        if (context.mounted) context.read<LoadCubit<List<Community>>>().refresh();
      },
      child: Row(
        children: [
          CommunityIcon(name: c.name, url: c.iconUrl, size: 50),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(c.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                    CommunityBadges(community: c, size: 14),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${Fmt.compact(c.memberCount)} members · ${Fmt.compact(c.discussionCount)} posts', style: context.text.bodySmall),
              ],
            ),
          ),
          if (c.isPending)
            StatusChip(label: 'Requested', color: context.palette.textSecondary)
          else if (c.unreadChatCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.messages, size: 12, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('${c.unreadChatCount}', style: context.text.labelSmall?.copyWith(color: Colors.white)),
                ],
              ),
            )
          else if (c.membership?.role != CommunityRole.member)
              RoleChip(role: c.membership!.role),
        ],
      ),
    );
  }
}

/// Discover card: cover strip, icon, name, stats and a join button.
class CommunityCard extends StatefulWidget {
  const CommunityCard({super.key, required this.community});

  final Community community;

  @override
  State<CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<CommunityCard> {
  bool _busy = false;

  Future<void> _toggle() async {
    final c = widget.community;
    if (c.isOwner || c.isBanned) return;
    // Paid community: plans and payment live on its page.
    if (c.needsPlan) {
      context.push(AppRoutes.communityDetail(c.slug));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final status = await sl<CommunityRepository>().toggleJoin(c.id);
      if (!mounted) return;
      final wasMember = c.isMember;
      final updated = status == null
          ? c.copyWith(clearMembership: true, memberCount: wasMember ? c.memberCount - 1 : c.memberCount)
          : c.copyWith(
        membership: CommunityMembership(role: CommunityRole.member, status: status, muted: false),
        memberCount: status == MembershipStatus.active ? c.memberCount + 1 : c.memberCount,
      );
      context.read<PagedCubit<Community>>().updateItem((x) => x.id == c.id, (_) => updated);
      context.read<LoadCubit<List<Community>>>().refresh();
      if (status == MembershipStatus.pending) AppSnackbar.info(context, 'Request sent — a moderator will approve it.');
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.community;
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AspectRatio(
                aspectRatio: 3,
                child: CommunityCover(
                  url: c.coverImageUrl,
                  fadeTo: palette.surface,
                  child: c.isFeatured
                      ? const Positioned(top: 8, right: 8, child: StatusChip(label: 'Featured', color: AppColors.sunrise, icon: AppIcons.sparkle))
                      : null,
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                bottom: -26,
                child: CommunityIcon(name: c.name, url: c.iconUrl, size: 56, borderColor: palette.surface),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 34, AppSpacing.md, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(c.name, style: context.text.titleMedium, overflow: TextOverflow.ellipsis)),
                    CommunityBadges(community: c),
                  ],
                ),
                if (c.category != null && c.category!.label.isNotEmpty) Text(c.category!.label, style: context.text.bodySmall),
                if (c.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(c.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${Fmt.compact(c.memberCount)} members · ${Fmt.compact(c.discussionCount)} posts',
                        style: context.text.bodySmall,
                      ),
                    ),
                    if (!c.isOwner && !c.isBanned)
                      SizedBox(
                        height: 34,
                        child: FilledButton(
                          onPressed: _busy ? null : _toggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: c.membership == null || c.needsPlan ? AppColors.primary : palette.surfaceMuted,
                            foregroundColor: c.membership == null || c.needsPlan ? Colors.white : palette.textPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                          child: _busy
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(
                            c.needsPlan ? (c.isExpired ? 'Renew' : 'Join · ${communityPriceLabel(c)}') : joinLabelFor(c),
                            style: context.text.labelMedium?.copyWith(color: c.membership == null || c.needsPlan ? Colors.white : null),
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
    );
  }
}