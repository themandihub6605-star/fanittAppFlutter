// File: lib/features/community/presentation/community_detail_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/purchase_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/services/share_service.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/report_sheet.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../store/data/store_access.dart';
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
    // private community). Paid community without a plan: the server sends
    // only the free preview posts.
    return BlocProvider(
      key: ValueKey('${community.id}-${community.canView}'),
      create: (_) => PagedCubit<CommunityPost>(
            (page) => community.canView || (community.isPaid && !community.isBanned)
            ? sl<CommunityRepository>().posts(community.id, page: page)
            : Future.value(const Paged<CommunityPost>(items: [], page: 1, pages: 1, total: 0)),
      ),
      child: _DetailView(community: community),
    );
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({required this.community});

  final Community community;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView> {
  bool _joinBusy = false;

  /// Lives happening in this community right now (for the "Live now" bar).
  List<LiveStream> _liveNow = const [];
  Timer? _livePoll;

  Community get c => widget.community;
  CommunityRepository get _repo => sl<CommunityRepository>();

  @override
  void initState() {
    super.initState();
    _loadLiveNow();
    // A live can start while the screen is open — check now and then.
    _livePoll = Timer.periodic(const Duration(seconds: 30), (_) => _loadLiveNow());
  }

  @override
  void dispose() {
    _livePoll?.cancel();
    super.dispose();
  }

  Future<void> _loadLiveNow() async {
    try {
      final res = await sl<StoreRepository>().communityLives(c.id);
      if (!mounted) return;
      final now = res.lives.where((l) => l.isLive).toList();
      if (now.length != _liveNow.length || !now.every((l) => _liveNow.any((o) => o.id == l.id))) {
        setState(() => _liveNow = now);
      }
    } catch (_) {
      // Keep what we had.
    }
  }

  Future<void> _reload() async {
    unawaited(_loadLiveNow());
    await context.read<LoadCubit<Community>>().refresh();
  }

  /// Creators who own the community can go live just for its members.
  bool _canGoLive(Object? auth) => c.isOwner && auth is AuthAuthenticated && auth.user.role == UserRole.creator;

  /// Opens "Go live" with this community picked (needs a live Fanitt Store).
  void _goLive(String myId) {
    HapticFeedback.selectionClick();
    StoreAccess.open(context, '${AppRoutes.storeLiveNew}?community=${Uri.encodeQueryComponent(c.id)}', userId: myId);
  }

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
      AppSnackbar.info(context, PurchasePolicy.canBuyDigital ? 'Get a plan for ${c.name} to watch this live.' : 'This live is for members of ${c.name}.');
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
            if (_canGoLive(context.read<AuthBloc>().state))
              ListTile(
                leading: const Icon(AppIcons.broadcast, color: AppColors.error),
                title: const Text('Go live for members'),
                subtitle: const Text('Only members of this community can watch'),
                onTap: () {
                  Navigator.pop(ctx);
                  final auth = context.read<AuthBloc>().state;
                  _goLive(auth is AuthAuthenticated ? auth.user.id : '');
                },
              ),
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
            if (!c.isOwner && context.read<AuthBloc>().state is AuthAuthenticated)
              ListTile(
                leading: const Icon(AppIcons.warning, color: AppColors.error),
                title: const Text('Report community', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportSheet(context, type: ReportType.community, id: c.id);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _share(BuildContext ctx) {
    HapticFeedback.selectionClick();
    ShareService.send(ctx, ShareService.community(slug: c.slug, name: c.name, members: c.memberCount, mine: c.isOwner));
  }

  Future<void> _openChat() async {
    HapticFeedback.selectionClick();
    await context.push(AppRoutes.communityChat, extra: c);
    _reload();
  }

  Future<void> _openMembers() async {
    HapticFeedback.selectionClick();
    await context.push(AppRoutes.communityMembers, extra: c);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final posts = context.watch<PagedCubit<CommunityPost>>();
    final width = MediaQuery.sizeOf(context).width;
    final coverHeight = width * 0.46;

    // "Live now" bar — stays on screen while scrolling, for members and the host.
    final watchable = [for (final l in _liveNow) if (c.isMember || l.isHost) l];

    return Scaffold(
      backgroundColor: palette.background,
      bottomNavigationBar: watchable.isEmpty
          ? null
          : _LiveNowBar(
        live: watchable.first,
        more: watchable.length - 1,
        onTap: () => context.push(AppRoutes.liveDetail(watchable.first.id)).then((_) => _loadLiveNow()),
      ),
      // Post — white pill, not orange.
      floatingActionButton: c.canPost
          ? FloatingActionButton.extended(
        heroTag: 'community-post',
        onPressed: _compose,
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 3,
        highlightElevation: 5,
        shape: StadiumBorder(side: BorderSide(color: palette.border)),
        icon: const Icon(AppIcons.pencil, size: 18),
        label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w800)),
      ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack)
          : null,
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: () async {
          await _reload();
          await posts.refresh();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 400) posts.loadMore();
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: coverHeight + 46,
                backgroundColor: palette.background,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                leadingWidth: 60,
                leading: Center(child: _GlassButton(icon: AppIcons.back, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop())),
                actions: [
                  Builder(builder: (ctx) => _GlassButton(icon: AppIcons.shareNetwork, tooltip: 'Share', onTap: () => _share(ctx))),
                  const SizedBox(width: 8),
                  _GlassButton(icon: AppIcons.info, tooltip: 'About', onTap: _showAbout),
                  if (c.isMember || c.canModerate || myId != null) ...[
                    const SizedBox(width: 8),
                    _GlassButton(icon: AppIcons.dotsThree, tooltip: 'More', onTap: _moreMenu),
                  ],
                  const SizedBox(width: 12),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  // Cover on top, community icon overlapping its bottom edge —
                  // both inside the app bar so the icon is never cut off.
                  background: Stack(
                    children: [
                      Positioned.fill(
                        bottom: 46,
                        child: GestureDetector(
                          onTap: c.coverImageUrl == null ? null : () => _showCover(context),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CommunityCover(url: c.coverImageUrl),
                              // Soft shade on top so the round buttons read on any picture.
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0x33101828), Color(0x00101828)],
                                    stops: [0, 0.5],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.gutter,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x1F101828), blurRadius: 16, offset: Offset(0, 6))],
                          ),
                          child: CommunityIcon(name: c.name, url: c.iconUrl, size: 84, borderColor: palette.background),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _header(context).animate().fadeIn(duration: 300.ms).slideY(begin: 0.03)),
              SliverToBoxAdapter(
                child: _CommunityLives(
                  key: ValueKey('lives-${c.id}-${c.isMember}'),
                  communityId: c.id,
                  onJoinTap: _joinFromLive,
                ),
              ),
              if (!c.canView && c.isPaid && !c.isBanned)
                ..._previewSlivers(context, posts, myId)
              else if (!c.canView)
                SliverToBoxAdapter(child: _locked(context))
              else ...[
                  SliverToBoxAdapter(child: _SectionTitle(title: 'Posts', count: c.discussionCount)),
                  if (posts.state.isFirstLoad)
                    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: Center(child: CircularProgressIndicator.adaptive())))
                  else if (posts.state.items.isEmpty && posts.state.errorMessage != null)
                    SliverToBoxAdapter(child: ErrorView(message: posts.state.errorMessage!, onRetry: posts.refresh))
                  else if (posts.state.items.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 120),
                          child: _EmptyPosts(canPost: c.canPost, onPost: _compose),
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
                              // Free tag: only owner / moderators see it here — paying members don't need it.
                              showFreeTag: c.isPaid && c.canModerate,
                              canMarkFree: c.isPaid && c.canModerate,
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
      barrierColor: const Color(0xEB101828),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(child: Center(child: Image.network(c.coverImageUrl!, fit: BoxFit.contain))),
      ),
    );
  }

  String get _accessLabel => c.isPaid ? communityPriceLabel(c) : (c.isPrivate ? 'Private' : 'Free');

  Widget _header(BuildContext context) {
    final palette = context.palette;
    final canGoLive = _canGoLive(context.watch<AuthBloc>().state);
    final showJoin = !c.isOwner && !c.isBanned;

    // Labelled white buttons under the main one.
    final actions = <Widget>[
      if (canGoLive)
        _OutlineAction(
          icon: AppIcons.broadcast,
          iconColor: _liveRed,
          label: 'Go live',
          onTap: () {
            final auth = context.read<AuthBloc>().state;
            _goLive(auth is AuthAuthenticated ? auth.user.id : '');
          },
        ),
      if (c.isMember && c.chatEnabled) _OutlineAction(icon: AppIcons.messages, label: 'Chat', badge: c.unreadChatCount, onTap: _openChat),
      _OutlineAction(icon: AppIcons.users, label: 'Members', badge: c.canModerate ? c.pendingRequestCount : 0, onTap: c.canView ? _openMembers : null),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(c.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.7, height: 1.15, color: palette.textPrimary)),
              ),
              const SizedBox(width: 4),
              CommunityBadges(community: c, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(c.isPaid ? AppIcons.crown : (c.isPrivate ? AppIcons.lock : AppIcons.globe), size: 13, color: palette.textSecondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  [
                    if (c.category != null && c.category!.label.isNotEmpty) c.category!.label,
                    c.isPaid ? 'Paid community' : (c.isPrivate ? 'Private community' : 'Public community'),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Members · Posts · Access
          Row(
            children: [
              _StatBox(value: Fmt.compact(c.memberCount), label: c.memberCount == 1 ? 'Member' : 'Members'),
              const SizedBox(width: 8),
              _StatBox(value: Fmt.compact(c.discussionCount), label: 'Posts'),
              const SizedBox(width: 8),
              _StatBox(value: _accessLabel, label: 'Access'),
            ],
          ),

          if (c.description.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(c.description.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, height: 1.5, color: palette.textPrimary)),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showAbout,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('About, rules & team', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                  Icon(AppIcons.chevronRight, size: 15, color: palette.textSecondary),
                ],
              ),
            ),
          ),

          if (c.isBanned) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('You have been removed from this community.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.error)),
          ],
          // Paid status: owner earnings, member validity / renew.
          if (c.isPaid || (c.membership?.isPaid ?? false)) ...[
            const SizedBox(height: AppSpacing.md),
            PaidCommunityStrip(community: c, onRenew: _buyPlan),
          ],
          const SizedBox(height: 16),

          // The one main button (Join / Get plan) — or Joined.
          if (showJoin) ...[
            c.needsPlan
                ? AppButton(
              label: !PurchasePolicy.canBuyDigital ? 'Members only' : (c.isExpired ? 'Renew · ${communityPriceLabel(c)}' : 'Join · ${communityPriceLabel(c)}'),
              icon: PurchasePolicy.canBuyDigital ? AppIcons.crown : AppIcons.lock,
              height: 48,
              isLoading: _joinBusy,
              onPressed: _joinBusy ? null : _buyPlan,
            )
                : c.membership == null
                ? AppButton(label: c.isPrivate ? 'Request to join' : 'Join community', height: 48, isLoading: _joinBusy, onPressed: _joinBusy ? null : _toggleJoin)
                : AppButton.secondary(
              label: c.isPending ? 'Cancel request' : (c.isExpired ? 'Join again' : 'Joined'),
              icon: c.isPending || c.isExpired ? null : AppIcons.check,
              height: 48,
              isLoading: _joinBusy,
              onPressed: _joinBusy ? null : _toggleJoin,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              for (final (i, a) in actions.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: a),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// About, rules and team in a sheet (keeps the page about the posts).
  void _showAbout() {
    HapticFeedback.selectionClick();
    showAppSheet<void>(
      context,
      builder: (sheet) {
        final palette = sheet.palette;
        Widget block(String title, Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );
        return SheetBody(
          title: c.name,
          subtitle: 'About this community',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              block(
                'About',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.description.isEmpty ? 'No description yet.' : c.description, style: TextStyle(fontSize: 14, height: 1.5, color: palette.textPrimary)),
                    const SizedBox(height: 10),
                    if (c.isPaid)
                      _InfoRow(icon: AppIcons.crown, text: 'Paid — ${c.plans.map((p) => '${p.key.label} ${Fmt.money(p.price)}').join(' · ')}')
                    else
                      _InfoRow(icon: c.isPrivate ? AppIcons.lock : AppIcons.globe, text: c.isPrivate ? 'Private — moderators approve members' : 'Public — anyone can join'),
                    _InfoRow(icon: AppIcons.paperPlane, text: c.onlyModeratorsPost ? 'Only owner & moderators post' : 'All members can post'),
                    if (c.createdAt != null) _InfoRow(icon: AppIcons.calendar, text: 'Created ${Fmt.date(c.createdAt!)}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              block(
                'Rules',
                c.rules.isEmpty
                    ? Text('No rules set.', style: TextStyle(fontSize: 13.5, color: palette.textSecondary))
                    : Column(
                  children: [
                    for (final (i, rule) in c.rules.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: palette.surfaceMuted, shape: BoxShape.circle),
                              child: Text('${i + 1}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(rule, style: TextStyle(fontSize: 14, height: 1.45, color: palette.textPrimary))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              block(
                'Team',
                Column(
                  children: [
                    for (final (i, (user, role)) in c.moderators.indexed)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: Row(
                          children: [
                            UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 36),
                            const SizedBox(width: 10),
                            Expanded(child: Text(user.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary))),
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
      },
    );
  }

  /// Paid community, no plan: free posts first, then 2 locked previews,
  /// then the plans card.
  List<Widget> _previewSlivers(BuildContext context, PagedCubit<CommunityPost> posts, String? myId) {
    final palette = context.palette;
    final free = posts.state.items.where((p) => !p.isLocked).toList();
    final teasers = posts.state.items.where((p) => p.isLocked).toList();
    final shown = free.length + teasers.length;
    final rest = c.discussionCount > shown ? c.discussionCount - shown : 0;
    return [
      if (posts.state.isFirstLoad)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: Center(child: CircularProgressIndicator.adaptive())))
      else ...[
        if (free.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionTitle(
              title: 'Free to read',
              count: free.length,
              hint: free.length == 1 ? 'This post is open to everyone' : 'These posts are open to everyone',
              icon: AppIcons.globe,
              iconColor: AppColors.success,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            sliver: SliverList.separated(
              itemCount: free.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                final post = free[i];
                return CommunityPostCard(
                  key: ValueKey(post.id),
                  post: post,
                  myUserId: myId,
                  canInteract: false,
                  canModerate: false,
                  showFreeTag: true,
                  onChanged: (updated) => posts.updateItem((p) => p.id == updated.id, (_) => updated),
                  onDeleted: () => posts.removeItem((p) => p.id == post.id),
                );
              },
            ),
          ),
        ],
        if (teasers.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionTitle(title: 'Members only', count: teasers.length, icon: AppIcons.lock, iconColor: palette.textSecondary)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            sliver: SliverList.separated(
              itemCount: teasers.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _LockedPostCard(post: teasers[i], onTap: _buyPlan)
                  .animate(delay: (80 * i).ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.05),
            ),
          ),
        ],
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 110),
          child: shown == 0 || c.isExpired
              ? _paidLocked(context)
              : _unlockCard(context, rest: rest, paidTotal: c.discussionCount > free.length ? c.discussionCount - free.length : teasers.length),
        ),
      ),
    ];
  }

  /// Plan chips: the cheapest has a dark outline, the rest are grey.
  Widget _planChips(BuildContext context) {
    final palette = context.palette;
    final cheapest = c.cheapestPlan;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final p in c.plans)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: p == cheapest ? palette.surface : palette.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p == cheapest ? palette.textPrimary : palette.border, width: p == cheapest ? 1.4 : 1),
            ),
            child: Text(
              '${p.key.label} · ${Fmt.money(p.price)}${p.key == CommunityPlanKey.lifetime ? '' : p.key.suffix}',
              style: TextStyle(fontSize: 12.5, color: palette.textPrimary, fontWeight: FontWeight.w800),
            ),
          ),
      ],
    );
  }

  /// After the locked previews: how much more is waiting, what the
  /// community offers, and the plans.
  Widget _unlockCard(BuildContext context, {required int rest, required int paidTotal}) {
    final palette = context.palette;
    final cheapest = c.cheapestPlan;
    final highlights = <({IconData icon, String value, String label})>[
      (icon: AppIcons.users, value: Fmt.compact(c.memberCount), label: 'members'),
      (icon: AppIcons.feed, value: Fmt.compact(paidTotal), label: 'member posts'),
      if (c.chatEnabled) (icon: AppIcons.messages, value: 'Live', label: 'group chat'),
      (icon: AppIcons.videoCamera, value: 'All', label: 'community lives'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
        decoration: _cardFrame(context),
        child: Column(
          children: [
            Text(
              rest > 0 ? '+${Fmt.compact(rest)}' : Fmt.compact(paidTotal),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1.4, height: 1, color: palette.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              rest > 0 ? 'more ${rest == 1 ? 'post' : 'posts'} unlock with a plan' : 'members-only ${paidTotal == 1 ? 'post' : 'posts'} unlock with a plan',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary),
            ),
            const SizedBox(height: 2),
            Text('Read every post, join the chat and watch the lives in ${c.name}.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  for (final (i, h) in highlights.indexed) ...[
                    if (i > 0) Container(width: 1, height: 34, color: palette.border),
                    Expanded(
                      child: Column(
                        children: [
                          Icon(h.icon, size: 17, color: palette.textSecondary),
                          const SizedBox(height: 4),
                          Text(h.value, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                          Text(h.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (c.plans.isNotEmpty) ...[
              _planChips(context),
              const SizedBox(height: AppSpacing.md),
            ],
            if (!c.isBanned)
              AppButton(
                label: cheapest == null ? 'Unlock everything' : 'Unlock from ${Fmt.money(cheapest.price)}',
                icon: AppIcons.lock,
                onPressed: _buyPlan,
              ),
          ],
        ),
      ),
    );
  }

  Widget _locked(BuildContext context) {
    if (c.isPaid) return _paidLocked(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 110),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: _cardFrame(context),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
              child: Icon(AppIcons.lock, size: 26, color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('This community is private', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary)),
            const SizedBox(height: 4),
            Text(
              c.isPending ? 'Your request is waiting for approval.' : 'Request to join — a moderator will approve you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Paid community, viewer has no plan: what they get + the plans.
  Widget _paidLocked(BuildContext context, {int lockedCount = 0}) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: _cardFrame(context),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
              child: Icon(AppIcons.crown, size: 26, color: palette.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              c.isExpired
                  ? 'Your membership ended'
                  : lockedCount > 0
                  ? '$lockedCount more ${lockedCount == 1 ? 'post' : 'posts'} for members'
                  : 'Members-only community',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              c.isExpired ? 'Renew to get back into the posts, chat and lives.' : 'Get a plan to read posts, join the chat and watch community lives.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
            ),
            if (c.plans.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _planChips(context),
            ],
            if (!c.isBanned) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(label: c.isExpired ? 'Renew membership' : 'See plans', icon: AppIcons.crown, onPressed: _buyPlan),
            ],
          ],
        ),
      ),
    );
  }
}

const _liveRed = Color(0xFFFF3B5C);

/// White card, thin grey border, soft shadow.
BoxDecoration _cardFrame(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(color: context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.8)),
  boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 5))],
);

/// Round white button on the cover (back / share / about / more).
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.surface.withValues(alpha: 0.94),
        shape: CircleBorder(side: BorderSide(color: palette.border.withValues(alpha: 0.6))),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 19, color: palette.textPrimary)),
        ),
      ),
    );
  }
}

/// Grey number box.
class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: palette.border.withValues(alpha: 0.8))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, maxLines: 1, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3, color: palette.textPrimary)),
            ),
            const SizedBox(height: 1),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// White pill with icon + label (+ amber count). Disabled when [onTap] is null.
class _OutlineAction extends StatelessWidget {
  const _OutlineAction({required this.icon, required this.label, required this.onTap, this.badge = 0, this.iconColor});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: palette.surface,
        shape: StadiumBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: iconColor ?? palette.textSecondary),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.textPrimary))),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                    child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Posts · 24" — section title with an optional icon and one line under it.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count, this.hint, this.icon, this.iconColor});

  final String title;
  final int count;
  final String? hint;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 24, AppSpacing.gutter, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor ?? palette.textSecondary),
                const SizedBox(width: 6),
              ],
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
              const SizedBox(width: 6),
              Text('· ${Fmt.compact(count)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.textTertiary)),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts({required this.canPost, required this.onPost});

  final bool canPost;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: _cardFrame(context),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
            child: Icon(AppIcons.messages, size: 24, color: palette.textPrimary),
          ),
          const SizedBox(height: 12),
          Text('No posts yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: palette.textPrimary)),
          const SizedBox(height: 4),
          Text(canPost ? 'Start the first discussion — say hi to your members.' : 'Check back soon.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: palette.textSecondary)),
          if (canPost) ...[
            const SizedBox(height: 14),
            AppButton(label: 'Write the first post', icon: AppIcons.pencil, expand: false, height: 44, onPressed: onPost),
          ],
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

/// Sticky bar at the bottom while a members-only live is on.
class _LiveNowBar extends StatelessWidget {
  const _LiveNowBar({required this.live, required this.more, required this.onTap});

  final LiveStream live;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = live.title.trim().isEmpty ? 'Live now' : live.title.trim();
    final sub = live.isHost ? 'You\u2019re live \u00b7 open your room' : (more > 0 ? 'Members only \u00b7 +$more more live' : 'Members only \u00b7 tap to join');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Ink(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _liveRed.withValues(alpha: 0.35)),
                boxShadow: context.isDark ? null : [BoxShadow(color: _liveRed.withValues(alpha: 0.14), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _liveRed, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .fade(begin: 1, end: 0.25, duration: 650.ms),
                        const SizedBox(width: 5),
                        const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.palette.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 1),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.palette.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(color: _liveRed, borderRadius: BorderRadius.circular(99)),
                    child: Text(live.isHost ? 'Open' : 'Join', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 320.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms);
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
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Row(
                  children: [
                    if (anyLive)
                      Container(width: 9, height: 9, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle))
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 1, end: 0.3, duration: 700.ms)
                    else
                      Icon(AppIcons.broadcast, size: 16, color: context.palette.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(anyLive ? 'Live in this community' : 'Upcoming lives', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: context.palette.textPrimary)),
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

/// A paid post seen without a plan: who and when, the first line fading
/// out, a blurred picture with a lock, and the counts. Tap → plans.
class _LockedPostCard extends StatelessWidget {
  const _LockedPostCard({required this.post, required this.onTap});

  final CommunityPost post;
  final VoidCallback onTap;

  Uint8List? get _image {
    final raw = post.teaserImage;
    final comma = raw.indexOf(',');
    if (!raw.startsWith('data:image') || comma < 0) return null;
    try {
      return base64Decode(raw.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final image = _image;
    final hasMedia = post.mediaCount > 0;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.border.withValues(alpha: 0.8)),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(initials: post.author.initials, imageUrl: post.author.avatarUrl, size: 40),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                        Text(Fmt.relative(post.createdAt), style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.lock, size: 11, color: palette.textSecondary),
                        const SizedBox(width: 3),
                        Text('Members only', style: TextStyle(color: palette.textPrimary, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                // First line, fading out.
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.transparent],
                    stops: [0.35, 1],
                  ).createShader(r),
                  child: Text(post.text, maxLines: 2, overflow: TextOverflow.clip, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.4)),
                ),
              ],
              if (hasMedia || post.hasPoll) ...[
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (image != null)
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true),
                          )
                        else
                          ColoredBox(color: palette.surfaceMuted),
                        if (image != null) Container(color: const Color(0x40101828)),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.92),
                                  boxShadow: const [BoxShadow(color: Color(0x26101828), blurRadius: 14, offset: Offset(0, 4))],
                                ),
                                child: const Icon(AppIcons.lock, color: Color(0xFF344054), size: 22),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                post.hasPoll && !hasMedia
                                    ? 'Poll for members'
                                    : post.hasVideo
                                    ? 'Video for members'
                                    : post.mediaCount > 1
                                    ? '${post.mediaCount} photos for members'
                                    : 'Photo for members',
                                style: TextStyle(
                                  color: image != null ? Colors.white : palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  shadows: image != null ? const [Shadow(color: Color(0x66101828), blurRadius: 6)] : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(AppIcons.heart, size: 16, color: palette.textSecondary),
                  const SizedBox(width: 4),
                  Text(Fmt.compact(post.likeCount), style: context.text.bodySmall),
                  const SizedBox(width: AppSpacing.md),
                  Icon(AppIcons.messages, size: 16, color: palette.textSecondary),
                  const SizedBox(width: 4),
                  Text(Fmt.compact(post.commentCount), style: context.text.bodySmall),
                  const Spacer(),
                  Text('Join to read', style: TextStyle(fontSize: 13, color: palette.textPrimary, fontWeight: FontWeight.w800)),
                  Icon(AppIcons.chevronRight, size: 16, color: palette.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}