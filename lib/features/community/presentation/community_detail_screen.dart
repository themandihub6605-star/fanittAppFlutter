import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/services/share_service.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../store/data/store_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/live/live_poster_card.dart';
import '../data/community_repository.dart';
import 'community_composer_screen.dart';
import 'community_paid_join.dart';
import 'widgets/community_post_card.dart';
import 'widgets/community_widgets.dart';

class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<Community>(() => sl<CommunityRepository>().bySlug(slug)),
      child: const _DetailLoader(),
    );
  }
}

class _DetailLoader extends StatelessWidget {
  const _DetailLoader();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<Community>>();
    final community = cubit.state.data;
    if (community == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AsyncView<Community>(state: cubit.state, onRetry: cubit.load, builder: (_) => const SizedBox.shrink()),
      );
    }
    // Posts are recreated when the viewer's access changes (e.g. joined a
    // private community).
    return BlocProvider(
      key: ValueKey('${community.id}-${community.canView}'),
      create: (_) => PagedCubit<CommunityPost>(
            (page) => community.canView
            ? sl<CommunityRepository>().posts(community.id, page: page)
            : Future.value(const Paged<CommunityPost>(items: [], page: 1, pages: 1, total: 0)),
      ),
      child: _DetailView(community: community),
    );
  }
}

enum _Section { posts, about }

class _DetailView extends StatefulWidget {
  const _DetailView({required this.community});

  final Community community;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  _Section _section = _Section.posts;
  bool _joinBusy = false;

  Community get c => widget.community;
  CommunityRepository get _repo => sl<CommunityRepository>();

  Future<void> _reload() => context.read<LoadCubit<Community>>().refresh();

  /// Paid community: pick a plan and pay, then reload.
  Future<void> _buyPlan() async {
    final joined = await joinPaidCommunity(context, c);
    if (!mounted || !joined) return;
    AppSnackbar.success(context, c.isExpired || (c.membership?.isPaid ?? false) ? 'Membership renewed 🎉' : 'Welcome to ${c.name}! 🎉');
    await _reload();
  }

  Future<void> _toggleJoin() async {
    if (c.needsPlan) return _buyPlan();
    if (c.isMember) {
      final paidTime = c.membership?.isPaid ?? false;
      final ok = await confirmAction(
        context,
        title: 'Leave ${c.name}?',
        message: paidTime ? 'You’ll lose the time left on your plan — joining again means paying again.' : 'You can join again any time.',
        confirmLabel: 'Leave',
      );
      if (!ok) return;
    }
    HapticFeedback.selectionClick();
    setState(() => _joinBusy = true);
    try {
      final status = await _repo.toggleJoin(c.id);
      if (!mounted) return;
      if (status == MembershipStatus.pending) AppSnackbar.info(context, 'Request sent — a moderator will approve it.');
      if (status == MembershipStatus.active) AppSnackbar.success(context, 'Welcome to ${c.name}!');
      await _reload();
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _joinBusy = false);
    }
  }

  /// Tapped a members-only live while not a member.
  void _joinFromLive() {
    if (c.isBanned) {
      AppSnackbar.error(context, 'You can’t join this community.');
    } else if (c.isPending) {
      AppSnackbar.info(context, 'Your request is waiting for approval — you can watch once you’re in.');
    } else if (c.needsPlan) {
      AppSnackbar.info(context, 'Get a plan for ${c.name} to watch this live.');
      _buyPlan();
    } else if (c.membership == null && !_joinBusy) {
      AppSnackbar.info(context, 'Join ${c.name} to watch this live.');
      _toggleJoin();
    }
  }

  Future<void> _toggleMute() async {
    final muted = !(c.membership?.muted ?? false);
    try {
      await _repo.setMuted(c.id, muted);
      if (!mounted) return;
      context.read<LoadCubit<Community>>().replace(c.copyWith(membership: c.membership?.copyWith(muted: muted)));
      AppSnackbar.info(context, muted ? 'Announcements muted' : 'You’ll be notified about announcements');
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  Future<void> _openSettings() async {
    final updated = await context.push<Community>(AppRoutes.communityForm, extra: c);
    if (updated != null) _reload();
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Delete ${c.name}?',
      message: 'All posts, comments and chat messages will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _repo.delete(c.id);
      if (!mounted) return;
      AppSnackbar.success(context, 'Community deleted');
      context.pop();
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  Future<void> _compose() async {
    final post = await CommunityComposerScreen.open(context, c);
    if (post == null || !mounted) return;
    context.read<PagedCubit<CommunityPost>>().prependItem(post);
    AppSnackbar.success(context, post.isAnnouncement ? 'Announcement sent' : 'Posted');
  }

  void _moreMenu() {
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetBody(
        title: c.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.canModerate)
              ListTile(leading: const Icon(AppIcons.gear), title: const Text('Community settings'), onTap: () { Navigator.pop(ctx); _openSettings(); }),
            if (c.isMember)
              ListTile(
                leading: Icon(c.membership?.muted == true ? AppIcons.bell : AppIcons.bellSlash),
                title: Text(c.membership?.muted == true ? 'Unmute announcements' : 'Mute announcements'),
                onTap: () { Navigator.pop(ctx); _toggleMute(); },
              ),
            if (c.isMember && !c.isOwner)
              ListTile(leading: const Icon(AppIcons.signOut), title: const Text('Leave community'), onTap: () { Navigator.pop(ctx); _toggleJoin(); }),
            if (c.isOwner)
              ListTile(
                leading: const Icon(AppIcons.trash, color: AppColors.error),
                title: const Text('Delete community', style: TextStyle(color: AppColors.error)),
                onTap: () { Navigator.pop(ctx); _delete(); },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final posts = context.watch<PagedCubit<CommunityPost>>();
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      floatingActionButton: c.canPost
          ? FloatingActionButton.extended(
        heroTag: 'community-post',
        onPressed: _compose,
        icon: const Icon(AppIcons.plus),
        label: const Text('Post'),
      ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack)
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await _reload();
          await posts.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (_section == _Section.posts && n.metrics.pixels > n.metrics.maxScrollExtent - 400) posts.loadMore();
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: width / 3 + 44,
                backgroundColor: palette.background,
                actions: [
                  if (c.isMember || c.canModerate)
                    IconButton(tooltip: 'More', onPressed: _moreMenu, icon: const Icon(AppIcons.dotsThree)),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  // Cover on top, community icon overlapping its bottom edge —
                  // both inside the app bar so the icon is never cut off.
                  background: Stack(
                    children: [
                      Positioned.fill(
                        bottom: 44,
                        child: GestureDetector(
                          onTap: c.coverImageUrl == null ? null : () => _showCover(context),
                          child: CommunityCover(url: c.coverImageUrl),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.gutter,
                        bottom: 4,
                        child: CommunityIcon(name: c.name, url: c.iconUrl, size: 76, borderColor: palette.background),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _header(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.sm),
                  child: SegmentedButton<_Section>(
                    segments: const [
                      ButtonSegment(value: _Section.posts, label: Text('Posts'), icon: Icon(AppIcons.feed, size: 16)),
                      ButtonSegment(value: _Section.about, label: Text('About'), icon: Icon(AppIcons.info, size: 16)),
                    ],
                    selected: {_section},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _section = s.first),
                  ),
                ),
              ),
              if (_section == _Section.posts)
                SliverToBoxAdapter(
                  child: _CommunityLives(
                    key: ValueKey('lives-${c.id}-${c.isMember}'),
                    communityId: c.id,
                    onJoinTap: _joinFromLive,
                  ),
                ),
              if (_section == _Section.about)
                SliverToBoxAdapter(child: _about(context))
              else if (!c.canView)
                SliverToBoxAdapter(child: _locked(context))
              else ...[
                  if (posts.state.isFirstLoad)
                    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: Center(child: CircularProgressIndicator())))
                  else if (posts.state.items.isEmpty && posts.state.errorMessage != null)
                    SliverToBoxAdapter(child: ErrorView(message: posts.state.errorMessage!, onRetry: posts.refresh))
                  else if (posts.state.items.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: MessageView(
                            icon: AppIcons.messages,
                            title: 'No posts yet',
                            message: c.canPost ? 'Start the first discussion.' : 'Check back soon.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 110),
                        sliver: SliverList.separated(
                          itemCount: posts.state.items.length + (posts.state.hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                          itemBuilder: (context, i) {
                            if (i == posts.state.items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(AppSpacing.md),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            final post = posts.state.items[i];
                            return CommunityPostCard(
                              key: ValueKey(post.id),
                              post: post,
                              myUserId: myId,
                              canInteract: c.isMember,
                              canModerate: c.canModerate,
                              onChanged: (updated) => posts.updateItem((p) => p.id == updated.id, (_) => updated),
                              onDeleted: () => posts.removeItem((p) => p.id == post.id),
                            );
                          },
                        ),
                      ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  void _showCover(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(child: Center(child: Image.network(c.coverImageUrl!, fit: BoxFit.contain))),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Builder(
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(child: Text(c.name, style: context.text.headlineSmall)),
                          CommunityBadges(community: c, size: 18),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ShareIconButton(
                      size: 38,
                      message: () => ShareService.community(slug: c.slug, name: c.name, members: c.memberCount, mine: c.isOwner),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (c.category != null && c.category!.label.isNotEmpty) c.category!.label,
                    '${Fmt.compact(c.memberCount)} members',
                    '${Fmt.compact(c.discussionCount)} posts',
                  ].join(' · '),
                  style: context.text.bodySmall,
                ),
                if (c.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(c.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                ],
                if (c.isBanned) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('You have been removed from this community.', style: context.text.labelMedium?.copyWith(color: AppColors.error)),
                ],
                // Paid status: owner earnings, member validity / renew.
                if (c.isPaid || (c.membership?.isPaid ?? false)) ...[
                  const SizedBox(height: AppSpacing.md),
                  PaidCommunityStrip(community: c, onRenew: _buyPlan),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    if (!c.isOwner && !c.isBanned)
                      Expanded(
                        child: c.needsPlan
                            ? AppButton(
                          label: c.isExpired ? 'Renew · ${communityPriceLabel(c)}' : 'Join · ${communityPriceLabel(c)}',
                          icon: AppIcons.crown,
                          height: 44,
                          isLoading: _joinBusy,
                          onPressed: _joinBusy ? null : _buyPlan,
                        )
                            : c.membership == null
                            ? AppButton(label: c.isPrivate ? 'Request to join' : 'Join community', height: 44, isLoading: _joinBusy, onPressed: _joinBusy ? null : _toggleJoin)
                            : AppButton.secondary(
                          label: c.isPending ? 'Cancel request' : (c.isExpired ? 'Join again' : 'Joined'),
                          icon: c.isPending || c.isExpired ? null : AppIcons.check,
                          height: 44,
                          isLoading: _joinBusy,
                          onPressed: _joinBusy ? null : _toggleJoin,
                        ),
                      ),
                    if (c.isMember && c.chatEnabled) ...[
                      if (!c.isOwner) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Badge(
                          isLabelVisible: c.unreadChatCount > 0,
                          label: Text('${c.unreadChatCount}'),
                          backgroundColor: AppColors.primary,
                          child: AppButton.secondary(
                            label: 'Chat',
                            icon: AppIcons.messages,
                            height: 44,
                            onPressed: () async {
                              await context.push(AppRoutes.communityChat, extra: c);
                              _reload();
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (ctx) => AppButton.secondary(
                          label: 'Share',
                          icon: AppIcons.shareNetwork,
                          height: 42,
                          onPressed: () => ShareService.send(
                            ctx,
                            ShareService.community(slug: c.slug, name: c.name, members: c.memberCount, mine: c.isOwner),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Badge(
                        isLabelVisible: c.canModerate && c.pendingRequestCount > 0,
                        label: Text('${c.pendingRequestCount}'),
                        backgroundColor: AppColors.primary,
                        child: AppButton.secondary(
                          label: 'Members',
                          icon: AppIcons.users,
                          height: 42,
                          onPressed: c.canView
                              ? () async {
                            await context.push(AppRoutes.communityMembers, extra: c);
                            _reload();
                          }
                              : null,
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

  Widget _locked(BuildContext context) {
    if (c.isPaid) return _paidLocked(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: AppCard(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            Icon(AppIcons.lock, size: 36, color: context.palette.textSecondary),
            const SizedBox(height: AppSpacing.sm),
            Text('This community is private', style: context.text.titleMedium),
            const SizedBox(height: 4),
            Text(
              c.isPending ? 'Your request is waiting for approval.' : 'Request to join — a moderator will approve you.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  /// Paid community, viewer has no plan: what they get + the plans.
  Widget _paidLocked(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
              ),
              child: const Icon(AppIcons.crown, size: 28, color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(c.isExpired ? 'Your membership ended' : 'Members-only community', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              c.isExpired ? 'Renew to get back into the posts, chat and lives.' : 'Get a plan to read posts, join the chat and watch community lives.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in c.plans)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: palette.primarySoft, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      '${p.key.label} · ${Fmt.money(p.price)}${p.key == CommunityPlanKey.lifetime ? '' : p.key.suffix}',
                      style: context.text.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
            if (!c.isBanned) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: c.isExpired ? 'Renew membership' : 'See plans', icon: AppIcons.crown, onPressed: _buyPlan),
            ],
          ],
        ),
      ),
    );
  }

  Widget _about(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(c.description.isEmpty ? 'No description yet.' : c.description, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                const SizedBox(height: AppSpacing.md),
                if (c.isPaid)
                  _InfoRow(icon: AppIcons.crown, text: 'Paid — ${c.plans.map((p) => '${p.key.label} ${Fmt.money(p.price)}').join(' · ')}')
                else
                  _InfoRow(icon: c.isPrivate ? AppIcons.lock : AppIcons.globe, text: c.isPrivate ? 'Private — moderators approve members' : 'Public — anyone can join'),
                _InfoRow(icon: AppIcons.paperPlane, text: c.onlyModeratorsPost ? 'Only owner & moderators post' : 'All members can post'),
                if (c.createdAt != null) _InfoRow(icon: AppIcons.calendar, text: 'Created ${Fmt.date(c.createdAt!)}'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rules', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                if (c.rules.isEmpty)
                  Text('No rules set.', style: context.text.bodyMedium)
                else
                  for (final (i, rule) in c.rules.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}.', style: context.text.titleSmall?.copyWith(color: AppColors.primary)),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(child: Text(rule, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Team', style: context.text.titleMedium),
                for (final (user, role) in c.moderators)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      children: [
                        UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 36),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(user.name, style: context.text.titleSmall)),
                        RoleChip(role: role),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.palette.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

/// Lives made for this community — "Members only" lock for non-members.
class _CommunityLives extends StatefulWidget {
  const _CommunityLives({super.key, required this.communityId, required this.onJoinTap});

  final String communityId;
  final VoidCallback onJoinTap;

  @override
  State<_CommunityLives> createState() => _CommunityLivesState();
}

class _CommunityLivesState extends State<_CommunityLives> {
  late final Future<({List<LiveStream> lives, bool isMember})> _future = _load();

  Future<({List<LiveStream> lives, bool isMember})> _load() async {
    try {
      return await sl<StoreRepository>().communityLives(widget.communityId);
    } catch (_) {
      return (lives: const <LiveStream>[], isMember: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<LiveStream> lives, bool isMember})>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null || data.lives.isEmpty) return const SizedBox.shrink();
        final lives = data.lives;
        final anyLive = lives.any((l) => l.isLive);
        final width = MediaQuery.sizeOf(context).width;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Row(
                  children: [
                    if (anyLive)
                      Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 1, end: 0.3, duration: 700.ms)
                    else
                      const Icon(AppIcons.broadcast, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(anyLive ? 'Live in this community' : 'Upcoming lives', style: context.text.titleMedium),
                          Text(
                            data.isMember ? 'Only members can watch these' : 'Members only — join the community to watch',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 212,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: lives.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) => SizedBox(
                    width: lives.length == 1 ? width - AppSpacing.gutter * 2 : 292,
                    child: LivePosterCard(
                      live: lives[i],
                      locked: !data.isMember && !lives[i].isHost,
                      onLockedTap: widget.onJoinTap,
                    ).animate(delay: (60 * i.clamp(0, 5)).ms).fadeIn(duration: 280.ms).slideX(begin: 0.1, curve: Curves.easeOutCubic),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}