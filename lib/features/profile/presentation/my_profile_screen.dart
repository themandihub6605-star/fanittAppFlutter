import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../account/presentation/screens/account_screen.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../content/data/content_repository.dart';
import '../../content/presentation/create_post_screen.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../feed/presentation/reels_screen.dart';

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
  List<Post>? _mine;
  List<Post>? _saved;
  CreatorDashboard? _insights; // creators: profile views + reviews

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _canPost {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated && (auth.user.role == UserRole.creator || auth.user.role == UserRole.brand);
  }

  Future<void> _load() async {
    final repo = sl<ContentRepository>();
    final canPost = _canPost;
    final auth = context.read<AuthBloc>().state;
    final creatorId = auth is AuthAuthenticated && auth.user.role == UserRole.creator ? auth.user.id : null;
    await Future.wait([
      if (creatorId != null)
        sl<DashboardRepository>().creator(creatorId).then((d) {
          if (mounted) setState(() => _insights = d);
        }).catchError((_) {}),
      sl<ApiClient>()
          .get('/posts/me/stats', parser: (d) => ProfileStats.fromJson(J.asMap(d)))
          .then((r) {
        if (mounted) setState(() => _stats = r.data);
      })
          .catchError((_) {}),
      if (canPost)
        repo.myPosts().then((p) {
          if (mounted) setState(() => _mine = p);
        }).catchError((_) {
          if (mounted) setState(() => _mine = const []);
        }),
      repo.savedPosts().then((p) {
        if (mounted) setState(() => _saved = p);
      }).catchError((_) {
        if (mounted) setState(() => _saved = const []);
      }),
    ]);
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

  Future<void> _delete(Post post) async {
    final what = post.isReel ? 'reel' : 'post';
    final ok = await confirmAction(context, title: 'Delete this $what?', message: 'It’s removed from the feed and your profile for everyone.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    try {
      await sl<ContentRepository>().deletePost(post.id);
      if (!mounted) return;
      AppSnackbar.success(context, post.isReel ? 'Reel deleted' : 'Post deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const Scaffold();
    final user = auth.user;
    final canPost = user.role == UserRole.creator || user.role == UserRole.brand;
    final posts = [for (final p in _mine ?? const <Post>[]) if (!p.isReel) p];
    final reels = [for (final p in _mine ?? const <Post>[]) if (p.isReel) p];
    final s = _stats;

    final tabs = <({String label, IconData icon, Widget Function() body})>[
      if (canPost) (label: 'Posts', icon: Icons.grid_on_rounded, body: () => _Grid(items: _mine == null ? null : posts, empty: 'No posts yet', onLongPress: _delete)),
      if (canPost) (label: 'Reels', icon: AppIcons.video, body: () => _Grid(items: _mine == null ? null : reels, empty: 'No reels yet', reels: true, onLongPress: _delete)),
      (label: 'Saved', icon: AppIcons.bookmark, body: () => _Grid(items: _saved, empty: 'Posts you save show here')),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          actions: [
            if (canPost) IconButton(tooltip: 'Create', icon: const Icon(AppIcons.plus), onPressed: _create),
            IconButton(tooltip: 'Settings & more', icon: const Icon(Icons.menu_rounded), onPressed: _openMenu),
            const SizedBox(width: AppSpacing.xxs),
          ],
        ),
        body: RefreshIndicator.adaptive(
          color: AppColors.primary,
          onRefresh: _refresh,
          notificationPredicate: (_) => true,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
                sliver: SliverToBoxAdapter(
                  child: AccountCard(
                    user: user,
                    extra: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SocialRow(
                          items: [
                            if (canPost) (label: 'Posts', value: s == null ? null : s.posts + s.reels, onTap: null),
                            if (canPost) (label: 'Followers', value: s?.followers ?? _insights?.followerCount, onTap: null),
                            (label: 'Following', value: s?.following, onTap: () => context.push(AppRoutes.following)),
                          ],
                        ),
                        if (user.role == UserRole.creator) ...[
                          const SizedBox(height: 12),
                          _InsightsRow(data: _insights),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(pinned: true, delegate: _TabsHeader(tabs: [for (final t in tabs) (label: t.label, icon: t.icon)])),
            ],
            body: TabBarView(children: [for (final t in tabs) t.body()]),
          ),
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

class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({required this.tabs});

  final List<({String label, IconData icon})> tabs;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(color: palette.background, border: Border(bottom: BorderSide(color: palette.border))),
      child: TabBar(
        indicatorColor: palette.textPrimary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: palette.textPrimary,
        unselectedLabelColor: palette.textTertiary,
        dividerColor: Colors.transparent,
        tabs: [for (final t in tabs) Tab(height: 46, icon: Icon(t.icon, size: 22))],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.tabs.length != tabs.length;
}

/// 3-column grid of posts / reels. Tap opens it, long-press deletes (own).
class _Grid extends StatelessWidget {
  const _Grid({required this.items, required this.empty, this.reels = false, this.onLongPress});

  final List<Post>? items;
  final String empty;
  final bool reels;
  final ValueChanged<Post>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    if (list.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 60),
          Icon(reels ? AppIcons.video : AppIcons.image, size: 40, color: context.palette.textTertiary),
          const SizedBox(height: 10),
          Center(child: Text(empty, style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary))),
        ],
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.xxl),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: reels ? 9 / 16 : 1),
      itemCount: list.length,
      itemBuilder: (context, i) => _Tile(post: list[i], onLongPress: onLongPress == null ? null : () => onLongPress!(list[i])),
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