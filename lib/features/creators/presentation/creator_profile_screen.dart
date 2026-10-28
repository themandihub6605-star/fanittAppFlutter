// File: lib/features/creators/presentation/creator_profile_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/purchase_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../../core/widgets/report_sheet.dart';
import '../../content/data/content_repository.dart';
import '../../feed/presentation/media_viewer_screen.dart';
import '../../feed/presentation/reels_screen.dart';
import '../../profile/data/profile_models.dart';
import '../../store/presentation/fanbox/fanbox_sheet.dart';
import '../../subscription/data/subscription_repository.dart';
import '../data/creators_repository.dart';


/// Creator profile — calm and clean: centred photo, name, numbers card,
/// Follow (the one orange button) + FanBox, then white section cards:
/// store, posts & reels, about, trust, portfolio, sessions, skills, links,
/// reviews.
class CreatorProfileScreen extends StatelessWidget {
  const CreatorProfileScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<CreatorPublicProfile>(() => sl<CreatorsRepository>().bySlug(slug)),
        child: _ProfileView(slug: slug),
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.slug});

  final String slug;

  Future<void> _toggleFollow(BuildContext context, CreatorPublicProfile data) async {
    final cubit = context.read<LoadCubit<CreatorPublicProfile>>();
    final result = await context.read<ActionCubit>().run('follow', () => sl<CreatorsRepository>().toggleFollow(data.creator.id));
    if (result == null) return;
    HapticFeedback.mediumImpact();
    cubit.replace(data.withCreator(data.creator.copyWith(isFollowing: result.following, followerCount: result.followerCount)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorPublicProfile>>();
    final data = cubit.state.data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Creator')),
        body: AsyncView<CreatorPublicProfile>(state: cubit.state, onRetry: cubit.load, builder: (_) => const SizedBox.shrink()),
      );
    }
    return _Loaded(data: data, slug: slug, onFollow: () => _toggleFollow(context, data));
  }
}

/// Can the viewer open the creator's Instagram? Only on a paid plan.
/// Fans have no plans, so they never see it; brands and creators on the
/// free plan see a locked button that leads to Plans.
enum _InstaAccess { checking, allowed, locked, hidden }

Future<_InstaAccess> _instaAccess(Object auth, String creatorUserId) async {
  if (auth is! AuthAuthenticated) return _InstaAccess.hidden;
  if (auth.user.id == creatorUserId) return _InstaAccess.allowed; // your own profile
  if (auth.user.role != UserRole.creator && auth.user.role != UserRole.brand) return _InstaAccess.hidden;
  try {
    final sub = await sl<SubscriptionRepository>().mine();
    final now = DateTime.now();
    final active = sub.status == 'active' || sub.status == 'past_due' || (sub.status == 'cancelled' && (sub.periodEnd?.isAfter(now) ?? false));
    return sub.plan.price > 0 && active ? _InstaAccess.allowed : _InstaAccess.locked;
  } catch (_) {
    return _InstaAccess.locked;
  }
}

String _instagramUrl(String raw) {
  final v = raw.trim();
  if (v.startsWith('http')) return v;
  final handle = v.replaceAll('@', '').replaceAll(RegExp(r'^(www\.)?instagram\.com/'), '');
  return 'https://instagram.com/$handle';
}

class _Loaded extends StatefulWidget {
  const _Loaded({required this.data, required this.slug, required this.onFollow});

  final CreatorPublicProfile data;
  final String slug;
  final VoidCallback onFollow;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  _InstaAccess _insta = _InstaAccess.checking;

  void _onBlocks() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BlockedUsers.instance.removeListener(_onBlocks);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    BlockedUsers.instance.addListener(_onBlocks);
    _checkInsta();
  }

  Future<void> _checkInsta() async {
    final access = await _instaAccess(context.read<AuthBloc>().state, widget.data.creator.userId);
    if (mounted) setState(() => _insta = access);
  }

  Future<void> _openInstagram(String raw) async {
    HapticFeedback.selectionClick();
    if (_insta == _InstaAccess.allowed) {
      LinkOpener.open(_instagramUrl(raw));
      return;
    }
    await showAppSheet<void>(
      context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: _instaGradient),
                child: const Icon(AppIcons.instagram, color: Colors.white, size: 30),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Unlock Instagram profiles', textAlign: TextAlign.center, style: sheet.text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'See ${widget.data.creator.name}’s Instagram and every creator’s social profile with any paid Fanitt plan.',
                textAlign: TextAlign.center,
                style: sheet.text.bodyMedium?.copyWith(color: sheet.palette.textSecondary, height: 1.45),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: 'See plans',
                  icon: AppIcons.crown,
                  filled: true,
                  onTap: () {
                    Navigator.of(sheet).pop();
                    context.push(AppRoutes.plans).then((_) => _checkInsta());
                  },
                ),
              ),
              TextButton(onPressed: () => Navigator.of(sheet).pop(), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = data.creator;
    final palette = context.palette;
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final isMe = auth is AuthAuthenticated && auth.user.id == c.userId;
    final topInset = MediaQuery.paddingOf(context).top;
    final verified = c.verificationStatus == VerificationStatus.verified;
    final instagram = c.socials.get('instagram');
    // Instagram has its own button — the rest are listed as links.
    final links = <String, String>{
      for (final e in c.socials.values.entries)
        if (e.key != 'instagram') e.key: e.value,
      if (c.portfolioLink.isNotEmpty) 'website': c.portfolioLink,
    };
    final showInsta = instagram.isNotEmpty && _insta != _InstaAccess.hidden && _insta != _InstaAccess.checking;

    final firstName = c.name.split(' ').first;
    final hidden = !isMe && BlockedUsers.instance.isHidden(c.userId);

    return AnnotatedRegion(
      value: context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: palette.background,
        body: RefreshIndicator.adaptive(
          color: AppColors.primary,
          edgeOffset: topInset + kToolbarHeight,
          onRefresh: context.read<LoadCubit<CreatorPublicProfile>>().refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Simple bar: back, name, share, more.
              SliverAppBar(
                pinned: true,
                backgroundColor: palette.background,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                foregroundColor: palette.textPrimary,
                titleSpacing: 0,
                centerTitle: false,
                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                actions: [
                  ShareIconButton(
                    size: 40,
                    message: () => ShareService.creator(slug: c.slug, name: c.name, category: c.category?.label ?? '', mine: isMe),
                  ),
                  if (!isMe && auth is AuthAuthenticated && c.userId.isNotEmpty)
                    IconButton(
                      tooltip: 'More',
                      icon: Icon(AppIcons.dotsThree, color: palette.textPrimary),
                      onPressed: () => showContentActions(context, type: ReportType.user, id: c.userId, name: c.name, userId: c.userId),
                    ),
                  const SizedBox(width: 10),
                ],
              ),

              if (hidden)
                SliverFillRemaining(hasScrollBody: false, child: BlockedProfileNotice(userId: c.userId, name: c.name))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, AppSpacing.huge),
                  sliver: SliverList.list(
                    children: [
                      // Photo, name, title, chips — centred.
                      Center(child: _Avatar(creator: c, slug: widget.slug, available: c.isAvailableForWork)).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.94, curve: Curves.easeOutBack, duration: 420.ms),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -0.7, height: 1.15, color: palette.textPrimary),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            const Icon(AppIcons.sealCheck, color: AppColors.info, size: 21),
                          ],
                        ],
                      ),
                      if (c.title.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.4, color: palette.textSecondary)),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (c.isProPlan) _MetaChip(icon: AppIcons.crown, label: c.planName, iconColor: AppColors.warning),
                          if (c.category != null && c.category!.label.isNotEmpty) _MetaChip(icon: AppIcons.sparkle, label: c.category!.label),
                          if (c.location.isNotEmpty) _MetaChip(icon: AppIcons.mapPin, label: c.location),
                          if (c.isAvailableForWork) const _MetaChip(icon: AppIcons.checkCircle, label: 'Open to work', iconColor: AppColors.success),
                          if (data.isTopCreator) const _MetaChip(icon: AppIcons.crown, label: 'Top creator', iconColor: AppColors.warning),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Numbers card
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: _frame(context),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              _Stat(value: Fmt.compact(c.followerCount), label: 'Followers'),
                              _Divider(color: palette.border),
                              _Stat(value: Fmt.compact(data.posts.length), label: 'Posts'),
                              _Divider(color: palette.border),
                              _Stat(
                                value: c.reviewCount == 0 ? '—' : c.averageRating.toStringAsFixed(1),
                                label: c.reviewCount == 0 ? 'Rating' : '${c.reviewCount} ${c.reviewCount == 1 ? 'review' : 'reviews'}',
                                icon: c.reviewCount == 0 ? null : AppIcons.starFilled,
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 60.ms, duration: 300.ms).slideY(begin: 0.05),
                      const SizedBox(height: 14),

                      // Follow (orange) + FanBox (white)
                      if (!isMe)
                        Row(
                          children: [
                            Expanded(
                              child: _ActionButton(
                                label: c.isFollowing ? 'Following' : 'Follow',
                                icon: c.isFollowing ? AppIcons.check : AppIcons.userPlus,
                                filled: !c.isFollowing,
                                busy: actions.isBusyWith('follow'),
                                onTap: actions.isBusy ? null : widget.onFollow,
                              ),
                            ),
                            // FanBox isn't available on iPhone (Apple rules).
                            if (PurchasePolicy.canBuyDigital) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _ActionButton(
                                  label: 'FanBox',
                                  icon: AppIcons.gift,
                                  filled: false,
                                  onTap: () => showFanBoxSheet(context, creatorId: c.id, creatorName: c.name, sentFrom: 'profile'),
                                ),
                              ),
                            ],
                          ],
                        ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                      if (c.responseTime.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(AppIcons.clock, size: 13, color: palette.textTertiary),
                            const SizedBox(width: 4),
                            Text('Usually replies ${c.responseTime}', style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
                          ],
                        ),
                      ],
                      if (showInsta) ...[
                        const SizedBox(height: 14),
                        _InstagramButton(locked: _insta == _InstaAccess.locked, mine: isMe, onTap: () => _openInstagram(instagram)).animate().fadeIn(delay: 140.ms, duration: 300.ms),
                      ],

                      // Their Fanitt Store
                      if (data.store != null) _StoreCard(store: data.store!),

                      // Content first.
                      if (data.posts.isNotEmpty) _Section(title: 'Posts & reels', icon: AppIcons.image, padded: false, child: _ContentGrid(posts: data.posts)),

                      if (c.bio.isNotEmpty) _Section(title: 'About', icon: AppIcons.user, child: _Expandable(text: c.bio)),

                      // Trust numbers
                      _Section(
                        title: 'Why brands pick $firstName',
                        icon: AppIcons.lightning,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _TrustTile(icon: AppIcons.checkCircle, value: '${data.onTimeDeliveryPercent}%', label: 'On-time delivery')),
                                const SizedBox(width: 8),
                                Expanded(child: _TrustTile(icon: AppIcons.campaigns, value: '${data.projectsCompleted}', label: 'Projects done')),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (verified) const _Fact(icon: AppIcons.sealCheck, text: 'Verified', color: AppColors.info),
                                if (c.responseTime.isNotEmpty) _Fact(icon: AppIcons.clock, text: 'Replies ${c.responseTime}'),
                                if (c.yearsOfExperience != null) _Fact(icon: AppIcons.star, text: '${c.yearsOfExperience} yrs experience'),
                                if (data.profileViews > 0) _Fact(icon: AppIcons.eye, text: '${Fmt.compact(data.profileViews)} profile views'),
                                if (data.joinedAt != null) _Fact(icon: AppIcons.calendar, text: 'Joined ${Fmt.date(data.joinedAt!)}'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Portfolio photos
                      if (data.portfolioImages.isNotEmpty)
                        _Section(
                          title: 'Portfolio',
                          icon: AppIcons.image,
                          child: SizedBox(
                            height: 160,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: data.portfolioImages.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, i) => GestureDetector(
                                onTap: () => MediaViewerScreen.open(
                                  context,
                                  media: [for (final u in data.portfolioImages) PostMedia(url: u, isVideo: false)],
                                  index: i,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(width: 124, child: AppNetworkImage(url: data.portfolioImages[i], fit: BoxFit.cover)),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Upcoming live sessions
                      if (data.sessions.isNotEmpty)
                        _Section(
                          title: 'Upcoming sessions',
                          icon: AppIcons.videoCamera,
                          child: Column(
                            children: [
                              for (final (i, se) in data.sessions.take(5).indexed) ...[
                                if (i > 0) Divider(height: 20, color: palette.border.withValues(alpha: 0.8)),
                                Row(
                                  children: [
                                    _DateTile(date: se.scheduledAt),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(se.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                                          const SizedBox(height: 1),
                                          Text(
                                            '${se.scheduledAt == null ? 'Soon' : Fmt.time(se.scheduledAt!.toLocal())} · ${se.durationMinutes} min',
                                            style: TextStyle(fontSize: 12, color: palette.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(color: se.price == 0 ? AppColors.success.withValues(alpha: 0.1) : palette.surfaceMuted, borderRadius: BorderRadius.circular(99)),
                                      child: Text(
                                        se.price == 0 ? 'Free' : Fmt.money(se.price),
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: se.price == 0 ? AppColors.success : palette.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                      if (c.skills.isNotEmpty || c.languages.isNotEmpty)
                        _Section(
                          title: 'Skills & languages',
                          icon: AppIcons.sparkle,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in c.skills) _Pill(label: s),
                              for (final l in c.languages) _Pill(label: l, icon: AppIcons.translate),
                            ],
                          ),
                        ),

                      if (links.isNotEmpty)
                        _Section(
                          title: 'Links',
                          icon: AppIcons.link,
                          child: Column(
                            children: [
                              for (final (i, e) in links.entries.indexed) ...[
                                if (i > 0) Divider(height: 1, color: palette.border.withValues(alpha: 0.8)),
                                InkWell(
                                  onTap: () => LinkOpener.open(e.value.startsWith('http') ? e.value : 'https://${e.value}'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                                          child: Icon(_linkIcon(e.key), size: 17, color: palette.textPrimary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(Fmt.titleCase(e.key), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary)),
                                              Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                                            ],
                                          ),
                                        ),
                                        Icon(AppIcons.arrowUpRight, size: 16, color: palette.textTertiary),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                      _Section(
                        title: 'Reviews${c.reviewCount > 0 ? ' · ${c.reviewCount}' : ''}',
                        icon: AppIcons.star,
                        child: data.reviews.isEmpty
                            ? Text('No reviews yet.', style: TextStyle(fontSize: 13.5, color: palette.textSecondary))
                            : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Rating summary
                            Container(
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Text(c.averageRating.toStringAsFixed(1), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1, color: palette.textPrimary)),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          for (var s = 0; s < 5; s++)
                                            Icon(s < c.averageRating.round() ? AppIcons.starFilled : AppIcons.star, size: 16, color: AppColors.warning),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text('From ${c.reviewCount} ${c.reviewCount == 1 ? 'review' : 'reviews'}', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            for (final (i, review) in data.reviews.indexed) ...[
                              if (i > 0) Divider(height: 24, color: palette.border.withValues(alpha: 0.8)),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(review.from?.name ?? 'Fanitt user', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary))),
                                      for (var s = 0; s < 5; s++) Icon(s < review.rating ? AppIcons.starFilled : AppIcons.star, size: 14, color: AppColors.warning),
                                    ],
                                  ),
                                  if (review.comment.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(review.comment, style: TextStyle(fontSize: 14, color: palette.textPrimary, height: 1.45)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(Fmt.date(review.createdAt), style: TextStyle(fontSize: 12, color: palette.textTertiary)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White card, thin grey border, soft shadow.
BoxDecoration _frame(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.8)),
  boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 5))],
);

/// Small white date tile: month on top, day under it.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});

  final DateTime? date;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = date?.toLocal();
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: palette.border)),
      child: Column(
        children: [
          Text(d == null ? 'SOON' : _months[d.month - 1], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: palette.textSecondary)),
          Text(d == null ? '—' : '${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.1, color: palette.textPrimary)),
        ],
      ),
    );
  }
}

IconData _linkIcon(String key) => switch (key.toLowerCase()) {
  'youtube' => AppIcons.youtube,
  'linkedin' => AppIcons.linkedin,
  'website' => AppIcons.globe,
  _ => AppIcons.link,
};

const _instaGradient = LinearGradient(
  begin: Alignment.bottomLeft,
  end: Alignment.topRight,
  colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)],
);

/// Big round photo: white ring, soft shadow and an "available" dot.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.creator, required this.slug, required this.available});

  final CreatorProfile creator;
  final String slug;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = creator;
    final hasPhoto = (c.avatarUrl ?? '').isNotEmpty;
    return GestureDetector(
      // Tap the circle → the full photo.
      onTap: hasPhoto
          ? () {
        HapticFeedback.selectionClick();
        MediaViewerScreen.open(context, media: [PostMedia(url: c.avatarUrl!, isVideo: false)], index: 0);
      }
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
              border: Border.all(color: palette.border),
              boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x1A101828), blurRadius: 24, offset: Offset(0, 10))],
            ),
            child: Hero(
              tag: 'creator-photo-$slug',
              child: ClipOval(
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: hasPhoto
                      ? CachedNetworkImage(imageUrl: c.avatarUrl!, fit: BoxFit.cover)
                      : ColoredBox(
                    color: palette.surfaceMuted,
                    child: Center(child: Text(c.initials, style: TextStyle(color: palette.textPrimary, fontSize: 36, fontWeight: FontWeight.w800))),
                  ),
                ),
              ),
            ),
          ),
          if (available)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 3.5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grey chip: small icon (optionally coloured) + dark text.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: palette.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? palette.textSecondary),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// "View on Instagram" — white card with the Instagram tile; locked without a paid plan.
class _InstagramButton extends StatelessWidget {
  const _InstagramButton({required this.locked, required this.mine, required this.onTap});

  final bool locked;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: palette.border.withValues(alpha: 0.8))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: _instaGradient),
                child: const Icon(AppIcons.instagram, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locked ? 'See their Instagram' : (mine ? 'Your Instagram' : 'View on Instagram'),
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      locked ? 'Available on paid Fanitt plans' : 'Reels, followers and recent posts',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(locked ? AppIcons.lock : AppIcons.arrowUpRight, size: 13, color: palette.textPrimary),
                    const SizedBox(width: 4),
                    Text(locked ? 'Unlock' : 'Open', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustTile extends StatelessWidget {
  const _TrustTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: palette.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: palette.textPrimary)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.warning),
                const SizedBox(width: 3),
              ],
              Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3, color: context.palette.textPrimary)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.palette.textSecondary)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 32, color: color);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.filled, required this.onTap, this.busy = false});

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = filled ? Colors.white : palette.textPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : palette.surface,
          border: filled ? null : Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(99),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: filled ? Colors.white : palette.textSecondary),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child, this.padded = true});

  final String title;
  final IconData icon;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: _frame(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 15, color: palette.textPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary))),
              ],
            ),
          ),
          Padding(padding: padded ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : const EdgeInsets.fromLTRB(4, 0, 4, 4), child: child),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: palette.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(label, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text});

  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = context.text.bodyMedium?.copyWith(color: context.palette.textPrimary, height: 1.5);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 4,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.text, style: style, maxLines: _open ? null : 4, overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis),
              if (long)
                GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_open ? 'Show less' : 'Read more', style: TextStyle(fontSize: 13, color: context.palette.textPrimary, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Posts | Reels switch and a 3-column grid. Every tile shows what it is
/// (several photos, video, reel) and opens it.
class _ContentGrid extends StatefulWidget {
  const _ContentGrid({required this.posts});

  final List<Post> posts;

  @override
  State<_ContentGrid> createState() => _ContentGridState();
}

class _ContentGridState extends State<_ContentGrid> {
  bool _reels = false;

  @override
  Widget build(BuildContext context) {
    final posts = [for (final p in widget.posts) if (!p.isReel) p];
    final reels = [for (final p in widget.posts) if (p.isReel) p];
    final list = _reels ? reels : posts;
    final palette = context.palette;

    Widget tab(String label, int count, bool active, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? palette.textPrimary : palette.border, width: active ? 2 : 1))),
          child: Text(
            '$label · $count',
            textAlign: TextAlign.center,
            style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: active ? palette.textPrimary : palette.textTertiary),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            tab('Posts', posts.length, !_reels, () => setState(() => _reels = false)),
            tab('Reels', reels.length, _reels, () => setState(() => _reels = true)),
          ],
        ),
        const SizedBox(height: 3),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Text(_reels ? 'No reels yet' : 'No posts yet', style: context.text.bodyMedium?.copyWith(color: palette.textSecondary)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 3, crossAxisSpacing: 3, childAspectRatio: _reels ? 9 / 16 : 1),
            itemCount: list.length,
            itemBuilder: (context, i) => _ContentTile(post: list[i]),
          ),
      ],
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final m = post.cover;
    final poster = m == null ? '' : (m.isVideo ? (m.thumbnailUrl.isNotEmpty ? m.thumbnailUrl : StreamVideoPlayer.thumbnailFor(m.url) ?? '') : m.url);
    const shadow = [Shadow(color: Color(0x8A101828), blurRadius: 6)];
    return GestureDetector(
      onTap: () => post.isReel ? ReelsScreen.open(context, startId: post.id) : context.push(AppRoutes.postDetail(post.id)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.palette.surfaceMuted, child: AppNetworkImage(url: poster, fit: BoxFit.cover)),
            // What it is, top-right: several items / a video / a reel.
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                post.isReel ? AppIcons.video : (post.media.length > 1 ? AppIcons.copy : (m?.isVideo ?? false) ? AppIcons.play : null),
                color: Colors.white,
                size: 16,
                shadows: shadow,
              ),
            ),
            if (post.isReel || post.likeCount > 0)
              Positioned(
                left: 6,
                bottom: 5,
                child: Row(
                  children: [
                    Icon(post.isReel ? AppIcons.play : AppIcons.heartFilled, color: Colors.white, size: 12, shadows: shadow),
                    const SizedBox(width: 3),
                    Text(Fmt.compact(post.isReel ? post.viewCount : post.likeCount), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: shadow)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Visit store" card.
class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});

  final CreatorStoreRef store;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: palette.border.withValues(alpha: 0.8))),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(AppRoutes.storePage(store.slug)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: store.logoUrl.isEmpty
                        ? ColoredBox(color: palette.surfaceMuted, child: Icon(AppIcons.store, color: palette.textPrimary))
                        : AppNetworkImage(url: store.logoUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(store.tagline.isNotEmpty ? store.tagline : 'Products, live sessions & more', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(AppRadius.pill), border: Border.all(color: palette.border)),
                  child: Text('Visit store', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded fact: icon + text.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = color ?? palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(text, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary)),
        ],
      ),
    );
  }
}