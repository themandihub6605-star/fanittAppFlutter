// File: lib/features/profile/presentation/my_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../account/presentation/screens/account_screen.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../content/data/content_repository.dart';
import '../../content/presentation/create_post_screen.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../campaigns/presentation/brand/brand_campaigns_screen.dart' show openBrandCampaign;
import '../../community/data/community_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../feed/presentation/reels_screen.dart';
import '../../store/data/store_models.dart';
import '../../store/data/store_repository.dart';
import '../data/profile_repository.dart';

/// Followers / following / posts for the Profile card.
class ProfileStats {
  const ProfileStats({required this.followers, required this.following, required this.posts, required this.reels, required this.canPost});

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
    followers: J.integer(json, 'followers'),
    following: J.integer(json, 'following'),
    posts: J.integer(json, 'posts'),
    reels: J.integer(json, 'reels'),
    canPost: J.boolean(json, 'canPost'),
  );

  final int followers;
  final int following;
  final int posts;
  final int reels;
  final bool canPost;
}

/// The "Profile" tab: your card (with followers / following / posts),
/// then your posts, reels and saved posts. ☰ opens every account option.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  ProfileStats? _stats;
  List<Post>? _saved;
  CreatorDashboard? _insights; // creators: profile views + reviews
  (List<Proposal>, ProposalCounts)? _proposals; // creators: campaign work
  BrandDashboard? _brand; // brands: their campaigns
  bool _workLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = sl<ContentRepository>();
    final auth = context.read<AuthBloc>().state;
    final role = auth is AuthAuthenticated ? auth.user.role : null;
    final creatorId = role == UserRole.creator ? (auth as AuthAuthenticated).user.id : null;
    await Future.wait([
      if (creatorId != null)
        sl<DashboardRepository>().creator(creatorId).then((d) {
          if (mounted) setState(() => _insights = d);
        }).catchError((_) {}),
      // The main thing on a creator's profile: their campaign work.
      if (role == UserRole.creator)
        sl<CampaignRepository>().myProposals().then((p) {
          if (mounted) setState(() => _proposals = p);
        }).catchError((_) {}),
      // …and on a brand's: their campaigns.
      if (role == UserRole.brand)
        sl<DashboardRepository>().brand().then((d) {
          if (mounted) setState(() => _brand = d);
        }).catchError((_) {}),
      sl<ApiClient>()
          .get('/posts/me/stats', parser: (d) => ProfileStats.fromJson(J.asMap(d)))
          .then((r) {
        if (mounted) setState(() => _stats = r.data);
      })
          .catchError((_) {}),
      if (role == UserRole.fan)
        repo.savedPosts().then((p) {
          if (mounted) setState(() => _saved = p);
        }).catchError((_) {
          if (mounted) setState(() => _saved = const []);
        }),
    ]);
    if (mounted) setState(() => _workLoaded = true);
  }

  Future<void> _refresh() async {
    context.read<AuthBloc>().add(const AuthRefreshRequested());
    await _load();
  }

  Future<void> _openMenu() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen(showCard: false)));
    if (mounted) _load();
  }

  Future<void> _create() async {
    final made = await showCreateChooser(context);
    if (made != null && made != CreateMode.story && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const Scaffold();
    final user = auth.user;
    // Fans don't post — they get their own profile: what they follow,
    // bought, joined and saved.
    // Agencies don't post or save posts — their Profile tab is the account page.
    if (user.role == UserRole.agency) return const AccountScreen();
    if (user.role == UserRole.fan) return _FanProfile(user: user, stats: _stats, saved: _saved, onMenu: _openMenu, onRefresh: _refresh);
    final isCreator = user.role == UserRole.creator;
    final s = _stats;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          IconButton(tooltip: 'Create', icon: const Icon(AppIcons.plus), onPressed: _create),
          IconButton(tooltip: 'Settings & more', icon: const Icon(Icons.menu_rounded), onPressed: _openMenu),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            AccountCard(
              user: user,
              extra: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SocialRow(
                    items: [
                      // Posts & reels now live under ☰ → My posts & reels.
                      (label: 'Posts', value: s == null ? null : s.posts + s.reels, onTap: () => context.push(AppRoutes.posts)),
                      (label: 'Followers', value: s?.followers ?? _insights?.followerCount, onTap: null),
                      (label: 'Following', value: s?.following, onTap: () => context.push(AppRoutes.following)),
                    ],
                  ),
                  if (isCreator) ...[
                    const SizedBox(height: 12),
                    _InsightsRow(data: _insights),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (isCreator)
              _CreatorWork(data: _proposals, loaded: _workLoaded, onChanged: _load)
            else
              _BrandWork(data: _brand, loaded: _workLoaded, onChanged: _load),
          ],
        ),
      ),
    );
  }
}

/// Posts · Followers · Following, in one neat row.
class _SocialRow extends StatelessWidget {
  const _SocialRow({required this.items});

  final List<({String label, int? value, VoidCallback? onTap})> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) Container(width: 1, height: 26, color: palette.border),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(item.value == null ? '–' : Fmt.compact(item.value!), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(item.label, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Creators: profile views and reviews (moved here from the home screen).
class _InsightsRow extends StatelessWidget {
  const _InsightsRow({required this.data});

  final CreatorDashboard? data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final reviews = d?.reviewCount ?? 0;
    return Row(
      children: [
        Expanded(
          child: _Insight(
            icon: AppIcons.eye,
            color: AppColors.info,
            value: d == null ? '–' : Fmt.compact(d.profileViews),
            label: 'Profile views',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Insight(
            icon: AppIcons.star,
            color: AppColors.warning,
            value: d == null ? '–' : (reviews == 0 ? '—' : d.averageRating.toStringAsFixed(1)),
            label: d == null ? 'Reviews' : (reviews == 0 ? 'No reviews yet' : '$reviews review${reviews == 1 ? '' : 's'}'),
          ),
        ),
      ],
    );
  }
}

class _Insight extends StatelessWidget {
  const _Insight({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, maxLines: 1, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.post, this.onLongPress});

  final Post post;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final m = post.cover;
    final poster = m == null ? '' : (m.isVideo ? (m.thumbnailUrl.isNotEmpty ? m.thumbnailUrl : StreamVideoPlayer.thumbnailFor(m.url) ?? '') : m.url);
    return GestureDetector(
      onTap: () => post.isReel ? ReelsScreen.open(context, startId: post.id) : context.push(AppRoutes.postDetail(post.id)),
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.palette.surfaceMuted, child: AppNetworkImage(url: poster, fit: BoxFit.cover)),
          if (post.media.length > 1) const Positioned(top: 6, right: 6, child: Icon(AppIcons.copy, color: Colors.white, size: 16, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
          if (!post.isReel && post.media.length == 1 && (m?.isVideo ?? false))
            const Positioned(top: 6, right: 6, child: Icon(AppIcons.play, color: Colors.white, size: 15, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
          if (post.isReel)
            Positioned(
              left: 6,
              bottom: 6,
              child: Row(
                children: [
                  const Icon(AppIcons.play, color: Colors.white, size: 13, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                  const SizedBox(width: 3),
                  Text(Fmt.compact(post.viewCount), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Fan profile
// ---------------------------------------------------------------------------

const _fanGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Fan's Profile tab: the card, quick links, creators they follow, what
/// they bought, communities they're in and their saved posts.
class _FanProfile extends StatefulWidget {
  const _FanProfile({required this.user, required this.stats, required this.saved, required this.onMenu, required this.onRefresh});

  final AppUser user;
  final ProfileStats? stats;
  final List<Post>? saved;
  final VoidCallback onMenu;
  final Future<void> Function() onRefresh;

  @override
  State<_FanProfile> createState() => _FanProfileState();
}

class _FanProfileState extends State<_FanProfile> {
  List<FollowingItem>? _following;
  List<LibraryItem>? _library;
  List<Community>? _communities;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      sl<ProfileRepository>().following().then((v) {
        if (mounted) setState(() => _following = v);
      }).catchError((_) {
        if (mounted) setState(() => _following = const []);
      }),
      sl<StoreRepository>().library().then((v) {
        if (mounted) setState(() => _library = v);
      }).catchError((_) {
        if (mounted) setState(() => _library = const []);
      }),
      sl<CommunityRepository>().mine().then((v) {
        if (mounted) setState(() => _communities = v);
      }).catchError((_) {
        if (mounted) setState(() => _communities = const []);
      }),
    ]);
  }

  Future<void> _refresh() async {
    await Future.wait([widget.onRefresh(), _load()]);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final palette = context.palette;
    final creators = [for (final f in _following ?? const <FollowingItem>[]) if (f.isCreator) f];
    final saved = widget.saved;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          IconButton(tooltip: 'Settings & more', icon: const Icon(Icons.menu_rounded), onPressed: widget.onMenu),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
              child: AccountCard(
                user: user,
                extra: _SocialRow(
                  items: [
                    (label: 'Following', value: widget.stats?.following ?? _following?.length, onTap: () => context.push(AppRoutes.following)),
                    (label: 'Purchases', value: _library?.length, onTap: () => context.push(AppRoutes.library)),
                    (label: 'Communities', value: _communities?.length, onTap: () => context.push(AppRoutes.communities)),
                  ],
                ),
              ),
            ),

            // Quick links
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border.withValues(alpha: 0.7)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _FanLink(icon: AppIcons.library, label: 'Library', color: const Color(0xFFDB2777), onTap: () => context.push(AppRoutes.library)),
                        _FanLink(icon: AppIcons.package, label: 'My orders', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.shopOrders)),
                        _FanLink(icon: AppIcons.wallet, label: Fmt.money(user.walletBalance), color: const Color(0xFFF59E0B), onTap: () => context.push(AppRoutes.wallet)),
                        _FanLink(icon: AppIcons.bookmark, label: 'Saved', color: const Color(0xFFE11D48), onTap: () => context.push(AppRoutes.savedPosts)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _FanLink(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following)),
                        _FanLink(icon: AppIcons.receipt, label: 'Activity', color: AppColors.success, onTap: () => context.push(AppRoutes.transactions)),
                        _FanLink(icon: AppIcons.bell, label: 'Alerts', color: AppColors.info, onTap: () => context.push(AppRoutes.notifications)),
                        _FanLink(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Creators you follow
            _FanSection(
              title: 'Creators you follow',
              onSeeAll: creators.isEmpty ? null : () => context.push(AppRoutes.following),
              child: _following == null
                  ? const _FanLoading(height: 96)
                  : creators.isEmpty
                  ? _FanEmpty(
                icon: AppIcons.creators,
                text: 'Follow creators to see them here',
                action: 'Find creators',
                onAction: () => context.go(AppRoutes.fanLibrary),
              )
                  : SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: creators.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final f = creators[i];
                    return GestureDetector(
                      onTap: f.slug.isEmpty ? null : () => context.push(AppRoutes.creatorProfile(f.slug)),
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _fanGradient),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
                                child: ClipOval(child: SizedBox(width: 56, height: 56, child: AppNetworkImage(url: f.avatarUrl, placeholderIcon: AppIcons.user))),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // What you bought
            _FanSection(
              title: 'Your library',
              onSeeAll: (_library ?? const []).isEmpty ? null : () => context.push(AppRoutes.library),
              child: _library == null
                  ? const _FanLoading(height: 150)
                  : _library!.isEmpty
                  ? _FanEmpty(icon: AppIcons.download, text: 'Courses, ebooks and more you buy show here', action: 'Browse products', onAction: () => context.push(AppRoutes.products))
                  : SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: _library!.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final item = _library![i];
                    return GestureDetector(
                      onTap: () => context.push(AppRoutes.library),
                      child: SizedBox(
                        width: 130,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(width: 130, height: 96, child: AppNetworkImage(url: item.product.coverUrl, placeholderIcon: AppIcons.download)),
                            ),
                            const SizedBox(height: 6),
                            Text(item.product.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                            Text(item.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Communities you're in
            _FanSection(
              title: 'Your communities',
              onSeeAll: () => context.push(AppRoutes.communities),
              child: _communities == null
                  ? const _FanLoading(height: 44)
                  : _communities!.isEmpty
                  ? _FanEmpty(icon: AppIcons.users, text: 'Join communities to chat with fans like you', action: 'Explore', onAction: () => context.push(AppRoutes.communities))
                  : SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: _communities!.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final c = _communities![i];
                    return GestureDetector(
                      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: palette.border)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipOval(child: SizedBox(width: 34, height: 34, child: AppNetworkImage(url: c.iconUrl, placeholderIcon: AppIcons.users))),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                            if (c.unreadChatCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(gradient: _fanGradient, borderRadius: BorderRadius.circular(10)),
                                child: Text('${c.unreadChatCount}', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Saved posts
            _FanSection(
              title: 'Saved posts',
              onSeeAll: (saved ?? const []).isEmpty ? null : () => context.push(AppRoutes.savedPosts),
              child: saved == null
                  ? const _FanLoading(height: 120)
                  : saved.isEmpty
                  ? _FanEmpty(icon: AppIcons.bookmark, text: 'Tap the bookmark on any post to keep it here', action: 'Open feed', onAction: () => context.go(AppRoutes.fanFeed))
                  : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3),
                  itemCount: saved.length.clamp(0, 9),
                  itemBuilder: (context, i) => ClipRRect(borderRadius: BorderRadius.circular(8), child: _Tile(post: saved[i])),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanSection extends StatelessWidget {
  const _FanSection({required this.title, required this.child, this.onSeeAll});

  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 10),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                if (onSeeAll != null)
                  GestureDetector(
                    onTap: onSeeAll,
                    child: const Text('See all', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _FanLink extends StatelessWidget {
  const _FanLink({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.06)]),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanEmpty extends StatelessWidget {
  const _FanEmpty({required this.icon, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, size: 22, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(fontSize: 12.5, color: palette.textSecondary))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(gradient: _fanGradient, borderRadius: BorderRadius.circular(12)),
                child: Text(action, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FanLoading extends StatelessWidget {
  const _FanLoading({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))));
  }
}


// ---------------------------------------------------------------------------
// Work section — what matters most on a creator's / brand's profile.
// ---------------------------------------------------------------------------

/// One stage of the work pipeline (label + colour).
class _Stage {
  const _Stage(this.label, this.color);

  final String label;
  final Color color;
}

const _pending = _Stage('Pending', AppColors.warning);
const _hiring = _Stage('Hiring', AppColors.info);
const _working = _Stage('Working', Color(0xFF7C4DFF));
const _review = _Stage('In review', AppColors.primary);
const _done = _Stage('Completed', AppColors.success);
const _declined = _Stage('Declined', AppColors.error);
const _draft = _Stage('Draft', Color(0xFF98A2B3));
const _cancelled = _Stage('Cancelled', Color(0xFF98A2B3));

/// A creator's proposal → where that work is now.
_Stage _proposalStage(Proposal p) {
  if (p.status == ProposalStatus.rejected) return _declined;
  if (p.status == ProposalStatus.pending) return _pending;
  return switch (p.campaign?.status) {
    CampaignStatus.submitted => _review,
    CampaignStatus.disputed => const _Stage('Disputed', AppColors.error),
    CampaignStatus.approved || CampaignStatus.completed => _done,
    CampaignStatus.cancelled => _cancelled,
    _ => _working,
  };
}

/// A brand's campaign → its stage.
_Stage _campaignStage(Campaign c) => switch (c.status) {
  CampaignStatus.draft => _draft,
  CampaignStatus.open => _hiring,
  CampaignStatus.inProgress => _working,
  CampaignStatus.submitted || CampaignStatus.disputed => _review,
  CampaignStatus.approved || CampaignStatus.completed => _done,
  CampaignStatus.cancelled => _cancelled,
};

class _CreatorWork extends StatefulWidget {
  const _CreatorWork({required this.data, required this.loaded, required this.onChanged});

  final (List<Proposal>, ProposalCounts)? data;
  final bool loaded;
  final Future<void> Function() onChanged;

  @override
  State<_CreatorWork> createState() => _CreatorWorkState();
}

class _CreatorWorkState extends State<_CreatorWork> {
  _Stage? _filter;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final header = _WorkHeader(title: 'My campaigns', subtitle: 'Where each application stands', onSeeAll: () => context.go(AppRoutes.creatorCampaigns));
    if (data == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, widget.loaded ? _WorkError(onRetry: widget.onChanged) : const _WorkSkeleton()]);
    }
    final proposals = data.$1;
    final stages = {for (final p in proposals) p: _proposalStage(p)};
    int count(_Stage st) => stages.values.where((v) => v == st).length;
    final visible = _filter == null ? proposals : proposals.where((p) => stages[p] == _filter).toList();

    if (proposals.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          _WorkEmpty(
            icon: AppIcons.campaigns,
            title: 'No campaigns yet',
            message: 'Apply to brand campaigns — every application and its status shows up here.',
            action: 'Find campaigns',
            onTap: () => context.go(AppRoutes.creatorCampaigns),
          ),
        ],
      );
    }

    final chipStages = [_pending, _working, _review, _done, _declined].where((st) => count(st) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        _StageStats(items: [(_pending, count(_pending)), (_working, count(_working)), (_review, count(_review)), (_done, count(_done))]),
        const SizedBox(height: AppSpacing.md),
        _StageChips(
          all: proposals.length,
          stages: [for (final st in chipStages) (st, count(st))],
          selected: _filter,
          onSelect: (st) => setState(() => _filter = st),
        ),
        const SizedBox(height: AppSpacing.sm),
        _WorkList(
          emptyText: 'Nothing in this list',
          children: [
            for (final p in visible.take(8))
              _WorkRow(
                imageUrl: p.campaign?.brand?.logoUrl ?? p.campaign?.campaignImageUrl,
                icon: AppIcons.brand,
                title: p.campaign?.title ?? 'Campaign',
                subtitle: [
                  if ((p.campaign?.brand?.name ?? '').isNotEmpty) p.campaign!.brand!.name,
                  if (p.createdAt != null) 'Applied ${Fmt.shortDate(p.createdAt!.toLocal())}',
                ].join(' · '),
                stage: stages[p]!,
                amount: p.quotedAmount != null && p.quotedAmount! > 0 ? Fmt.money(p.quotedAmount!) : p.campaign?.payLabel,
                onTap: () async {
                  await context.push(AppRoutes.campaignDetail(p.campaignId));
                  widget.onChanged();
                },
              ),
          ],
        ),
        if (visible.length > 8) _SeeAllButton(label: 'See all ${visible.length} in Campaigns', onTap: () => context.go(AppRoutes.creatorCampaigns)),
      ],
    );
  }
}

class _BrandWork extends StatefulWidget {
  const _BrandWork({required this.data, required this.loaded, required this.onChanged});

  final BrandDashboard? data;
  final bool loaded;
  final Future<void> Function() onChanged;

  @override
  State<_BrandWork> createState() => _BrandWorkState();
}

class _BrandWorkState extends State<_BrandWork> {
  _Stage? _filter;

  Future<void> _post() async {
    final created = await context.push<bool>(AppRoutes.campaignEditor());
    if (created ?? false) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final header = _WorkHeader(title: 'My campaigns', subtitle: 'Hiring, in progress and done', onSeeAll: () => context.push(AppRoutes.brandCampaigns));
    if (d == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, widget.loaded ? _WorkError(onRetry: widget.onChanged) : const _WorkSkeleton()]);
    }
    final campaigns = d.campaigns;
    final stages = {for (final c in campaigns) c: _campaignStage(c)};
    int count(_Stage st) => stages.values.where((v) => v == st).length;
    // Waiting-for-you first, then hiring, working, the rest.
    const order = [_review, _hiring, _working, _draft, _done, _cancelled];
    final sorted = [...campaigns]..sort((a, b) => order.indexOf(stages[a]!).compareTo(order.indexOf(stages[b]!)));
    final visible = _filter == null ? sorted : sorted.where((c) => stages[c] == _filter).toList();

    if (campaigns.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          _WorkEmpty(
            icon: AppIcons.campaigns,
            title: 'No campaigns yet',
            message: 'Post a campaign and creators start applying. Track every one of them here.',
            action: 'Post a campaign',
            onTap: _post,
          ),
        ],
      );
    }

    final chipStages = [_review, _hiring, _working, _done, _draft, _cancelled].where((st) => count(st) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        _StageStats(items: [(_hiring, count(_hiring)), (_working, count(_working)), (_review, count(_review)), (_done, count(_done))]),
        const SizedBox(height: AppSpacing.md),
        _StageChips(
          all: campaigns.length,
          stages: [for (final st in chipStages) (st, count(st))],
          selected: _filter,
          onSelect: (st) => setState(() => _filter = st),
        ),
        const SizedBox(height: AppSpacing.sm),
        _WorkList(
          emptyText: 'Nothing in this list',
          children: [
            for (final c in visible.take(8))
              _WorkRow(
                imageUrl: c.campaignImageUrl,
                icon: AppIcons.campaigns,
                title: c.title,
                subtitle: switch (stages[c]) {
                  _review => '${(c.assignedCreatorName ?? '').isEmpty ? 'Creator' : c.assignedCreatorName} sent work — review it',
                  _working => '${(c.assignedCreatorName ?? '').isEmpty ? 'Creator' : c.assignedCreatorName} is working on it',
                  _ => c.applicantCount == 1 ? '1 applied' : '${c.applicantCount} applied',
                },
                stage: stages[c]!,
                amount: c.payLabel,
                onTap: () async {
                  if (await openBrandCampaign(context, c)) widget.onChanged();
                },
              ),
          ],
        ),
        if (visible.length > 8) _SeeAllButton(label: 'See all ${visible.length} campaigns', onTap: () => context.push(AppRoutes.brandCampaigns)),
        const SizedBox(height: AppSpacing.md),
        _SeeAllButton(label: 'Post a new campaign', icon: AppIcons.plus, onTap: _post),
      ],
    );
  }
}

class _WorkHeader extends StatelessWidget {
  const _WorkHeader({required this.title, required this.subtitle, required this.onSeeAll});

  final String title;
  final String subtitle;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
              ],
            ),
          ),
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                SizedBox(width: 2),
                Icon(AppIcons.chevronRight, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four counts in a row — a quick read of the pipeline.
class _StageStats extends StatelessWidget {
  const _StageStats({required this.items});

  final List<(_Stage, int)> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        for (final (i, (st, n)) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border.withValues(alpha: 0.8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: n > 0 ? st.color : palette.textTertiary)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: st.color, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Expanded(child: Text(st.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.textSecondary))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StageChips extends StatelessWidget {
  const _StageChips({required this.all, required this.stages, required this.selected, required this.onSelect});

  final int all;
  final List<(_Stage, int)> stages;
  final _Stage? selected;
  final ValueChanged<_Stage?> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget chip(String label, int n, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? palette.textPrimary : palette.surface,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? Colors.transparent : palette.border)),
            child: Text('$label · $n', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? palette.background : palette.textPrimary)),
          ),
        ),
      ),
    );
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('All', all, selected == null, () => onSelect(null)),
          for (final (st, n) in stages) chip(st.label, n, selected == st, () => onSelect(st)),
        ],
      ),
    );
  }
}

/// Rows in one card, divided by hairlines.
class _WorkList extends StatelessWidget {
  const _WorkList({required this.children, required this.emptyText});

  final List<Widget> children;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 16, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: children.isEmpty
          ? Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(emptyText, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: palette.textSecondary)),
      )
          : Column(
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 70, color: palette.border.withValues(alpha: 0.7)),
            w,
          ],
        ],
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.imageUrl, required this.icon, required this.title, required this.subtitle, required this.stage, required this.onTap, this.amount});

  final String? imageUrl;
  final IconData icon;
  final String title;
  final String subtitle;
  final _Stage stage;
  final String? amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 46,
                height: 46,
                child: (imageUrl ?? '').isEmpty
                    ? ColoredBox(color: palette.surfaceMuted, child: Icon(icon, size: 20, color: palette.textSecondary))
                    : AppNetworkImage(url: imageUrl!, fit: BoxFit.cover, placeholderIcon: icon),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: stage.color.withValues(alpha: context.isDark ? 0.2 : 0.12), borderRadius: BorderRadius.circular(99)),
                  child: Text(stage.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: stage.color)),
                ),
                if ((amount ?? '').isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(amount!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: context.palette.border),
          foregroundColor: context.palette.textPrimary,
        ),
        icon: Icon(icon ?? AppIcons.arrowRightSimple, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _WorkEmpty extends StatelessWidget {
  const _WorkEmpty({required this.icon, required this.title, required this.message, required this.action, required this.onTap});

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary)),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _WorkSkeleton extends StatelessWidget {
  const _WorkSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.palette.border.withValues(alpha: 0.5);
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)));
    return Column(
      children: [
        Row(children: [for (var i = 0; i < 4; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: Container(height: 62, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16))))]]),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [bar(46, 46), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(160, 12), const SizedBox(height: 6), bar(110, 10)]))]),
          ),
      ],
    );
  }
}

class _WorkError extends StatelessWidget {
  const _WorkError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Text('Couldn’t load your campaigns.', style: TextStyle(color: context.palette.textSecondary)),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}