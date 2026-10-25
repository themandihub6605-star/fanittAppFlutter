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
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../content/data/content_repository.dart';
import '../../feed/presentation/media_viewer_screen.dart';
import '../../feed/presentation/reels_screen.dart';
import '../../profile/data/profile_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/call/request_call_sheet.dart';
import '../../store/presentation/fanbox/fanbox_sheet.dart';
import '../data/creators_repository.dart';

const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Full-screen creator profile: big photo header, numbers, follow / FanBox,
/// about, skills, links, posts and reviews.
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

class _Loaded extends StatefulWidget {
  const _Loaded({required this.data, required this.slug, required this.onFollow});

  final CreatorPublicProfile data;
  final String slug;
  final VoidCallback onFollow;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  bool _messaging = false;
  bool _calling = false;

  /// Fan (or creator) → direct chat with this creator.
  Future<void> _message() async {
    final c = widget.data.creator;
    HapticFeedback.selectionClick();
    setState(() => _messaging = true);
    try {
      final conversation = await sl<ChatRepository>().startWith(c.userId);
      if (!mounted) return;
      context.push(AppRoutes.chat(conversation.id), extra: ChatArgs(title: c.name, avatarUrl: c.avatarUrl));
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _messaging = false);
    }
  }

  /// Audio / video call at the creator's own per-minute rate (or free).
  Future<void> _call() async {
    final ref = widget.data.store;
    if (ref == null) return;
    HapticFeedback.selectionClick();
    setState(() => _calling = true);
    try {
      final page = await sl<StoreRepository>().storePage(ref.slug);
      if (!mounted) return;
      final info = page.calls;
      final name = widget.data.creator.name;
      if (!info.enabled) {
        AppSnackbar.info(context, '$name isn’t taking calls yet');
      } else if (info.busy) {
        AppSnackbar.info(context, '$name is on another call — try again in a bit');
      } else if (!info.online) {
        AppSnackbar.info(context, '$name is offline right now — try again later');
      } else {
        await showRequestCallSheet(context, store: page.store, info: info);
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = data.creator;
    final palette = context.palette;
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final isMe = auth is AuthAuthenticated && auth.user.id == c.userId;
    final viewerIsBrand = auth is AuthAuthenticated && auth.user.role == UserRole.brand;
    // Creators can't message other creators (they can still call their store).
    final viewerIsCreator = auth is AuthAuthenticated && auth.user.role == UserRole.creator;
    final topInset = MediaQuery.paddingOf(context).top;
    final verified = c.verificationStatus == VerificationStatus.verified;
    // Instagram isn't shown on profiles.
    final links = <String, String>{
      for (final e in c.socials.values.entries)
        if (e.key != 'instagram') e.key: e.value,
      if (c.portfolioLink.isNotEmpty) 'website': c.portfolioLink,
    };

    return AnnotatedRegion(
      value: context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator.adaptive(
          color: AppColors.primary,
          edgeOffset: topInset + kToolbarHeight,
          onRefresh: context.read<LoadCubit<CreatorPublicProfile>>().refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Simple bar: back, name, share.
              SliverAppBar(
                pinned: true,
                backgroundColor: palette.background,
                surfaceTintColor: Colors.transparent,
                foregroundColor: palette.textPrimary,
                titleSpacing: 0,
                title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                actions: [
                  ShareIconButton(
                    size: 40,
                    message: () => ShareService.creator(slug: c.slug, name: c.name, category: c.category?.label ?? '', mine: isMe),
                  ),
                  const SizedBox(width: 10),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
                sliver: SliverList.list(
                  children: [
                    // Photo + numbers side by side.
                    Row(
                      children: [
                        _Avatar(creator: c, slug: widget.slug, available: c.isAvailableForWork),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Row(
                            children: [
                              _Stat(value: Fmt.compact(c.followerCount), label: 'Followers'),
                              _Stat(value: Fmt.compact(data.posts.length), label: 'Posts'),
                              _Stat(
                                value: c.reviewCount == 0 ? '—' : c.averageRating.toStringAsFixed(1),
                                label: c.reviewCount == 0 ? 'Rating' : '${c.reviewCount} reviews',
                                icon: c.reviewCount == 0 ? null : AppIcons.starFilled,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 300.ms),
                    const SizedBox(height: 14),

                    // Name, title, chips.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15),
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 6),
                          const Icon(AppIcons.sealCheck, color: Color(0xFF3B82F6), size: 22),
                        ],
                        if (c.isProPlan) ...[
                          const SizedBox(width: 8),
                          _HeaderChip(label: c.planName, icon: AppIcons.crown, gradient: true),
                        ],
                      ],
                    ),
                    if (c.title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textSecondary, height: 1.35)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (c.category != null && c.category!.label.isNotEmpty) _MetaChip(icon: AppIcons.sparkle, label: c.category!.label, color: AppColors.primary),
                        if (c.location.isNotEmpty) _MetaChip(icon: AppIcons.mapPin, label: c.location),
                        if (c.isAvailableForWork) const _MetaChip(icon: AppIcons.checkCircle, label: 'Open to work', color: AppColors.success),
                        if (data.isTopCreator) const _MetaChip(icon: AppIcons.crown, label: 'Top creator', color: AppColors.warning),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Actions: Follow + FanBox.
                    if (!isMe)
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _ActionButton(
                              label: c.isFollowing ? 'Following' : 'Follow',
                              icon: c.isFollowing ? AppIcons.check : AppIcons.userPlus,
                              filled: !c.isFollowing,
                              busy: actions.isBusyWith('follow'),
                              onTap: actions.isBusy ? null : widget.onFollow,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 2,
                            child: _ActionButton(
                              label: 'FanBox',
                              icon: AppIcons.gift,
                              filled: false,
                              onTap: () => showFanBoxSheet(context, creatorId: c.id, creatorName: c.name, sentFrom: 'profile'),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
                    // Message + Call (brands talk to creators through campaigns instead;
                    // creators can't message other creators, only call).
                    if (!isMe && !viewerIsBrand && (!viewerIsCreator || data.store != null)) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          if (!viewerIsCreator)
                            Expanded(
                              child: _ActionButton(label: 'Message', icon: AppIcons.messages, filled: false, busy: _messaging, onTap: _messaging ? null : _message),
                            ),
                          if (data.store != null) ...[
                            if (!viewerIsCreator) const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _ActionButton(label: 'Call', icon: AppIcons.phone, filled: false, busy: _calling, onTap: _calling ? null : _call),
                            ),
                          ],
                        ],
                      ).animate().fadeIn(delay: 110.ms, duration: 300.ms),
                    ],
                    if (c.responseTime.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Icon(AppIcons.clock, size: 14, color: palette.textTertiary),
                          const SizedBox(width: 4),
                          Text('Usually replies ${c.responseTime}', style: context.text.bodySmall),
                        ],
                      ),
                    ],

                    // Their Fanitt Store
                    if (data.store != null) _StoreCard(store: data.store!),

                    if (c.bio.isNotEmpty) _Section(title: 'About', icon: AppIcons.user, child: _Expandable(text: c.bio)),

                    // Trust numbers
                    _Section(
                      title: 'Why brands pick ${c.name.split(' ').first}',
                      icon: AppIcons.lightning,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _TrustTile(icon: AppIcons.checkCircle, value: '${data.onTimeDeliveryPercent}%', label: 'On-time delivery', color: AppColors.success)),
                              const SizedBox(width: 8),
                              Expanded(child: _TrustTile(icon: AppIcons.campaigns, value: '${data.projectsCompleted}', label: 'Projects done', color: AppColors.info)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (verified) const _Fact(icon: AppIcons.sealCheck, text: 'Verified', color: Color(0xFF3B82F6)),
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
                          height: 150,
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
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(width: 120, child: AppNetworkImage(url: data.portfolioImages[i], fit: BoxFit.cover)),
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
                              if (i > 0) Divider(height: 18, color: palette.border),
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(AppIcons.videoCamera, size: 19, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(se.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                        Text(
                                          '${se.scheduledAt == null ? 'Soon' : Fmt.dateTime(se.scheduledAt!)} · ${se.durationMinutes} min',
                                          style: context.text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(se.price == 0 ? 'Free' : Fmt.money(se.price), style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
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
                        title: 'More links',
                        icon: AppIcons.link,
                        child: Column(
                          children: [
                            for (final (i, e) in links.entries.indexed) ...[
                              if (i > 0) Divider(height: 1, color: palette.border),
                              InkWell(
                                onTap: () => LinkOpener.open(e.value.startsWith('http') ? e.value : 'https://${e.value}'),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                                        child: Icon(_linkIcon(e.key), size: 17, color: AppColors.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(Fmt.titleCase(e.key), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                            Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
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

                    if (data.posts.isNotEmpty)
                      _Section(title: 'Posts & reels', icon: AppIcons.image, padded: false, child: _ContentGrid(posts: data.posts)),

                    _Section(
                      title: 'Reviews${c.reviewCount > 0 ? ' · ${c.reviewCount}' : ''}',
                      icon: AppIcons.star,
                      child: data.reviews.isEmpty
                          ? Text('No reviews yet.', style: context.text.bodyMedium)
                          : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Rating summary
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                            child: Row(
                              children: [
                                Text(c.averageRating.toStringAsFixed(1), style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                                    Text('From ${c.reviewCount} ${c.reviewCount == 1 ? 'review' : 'reviews'}', style: context.text.bodySmall),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          for (final (i, review) in data.reviews.indexed) ...[
                            if (i > 0) Divider(height: 24, color: palette.border),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(review.from?.name ?? 'Fanitt user', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                                    for (var s = 0; s < 5; s++) Icon(s < review.rating ? AppIcons.starFilled : AppIcons.star, size: 14, color: AppColors.warning),
                                  ],
                                ),
                                if (review.comment.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(review.comment, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.45)),
                                ],
                                const SizedBox(height: 4),
                                Text(Fmt.date(review.createdAt), style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
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

IconData _linkIcon(String key) => switch (key.toLowerCase()) {
  'youtube' => AppIcons.youtube,
  'linkedin' => AppIcons.linkedin,
  'website' => AppIcons.globe,
  _ => AppIcons.link,
};

/// Big round photo with a gradient ring and an "available" dot.
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
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _gradient),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
              child: Hero(
                tag: 'creator-photo-$slug',
                child: ClipOval(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: (c.avatarUrl ?? '').isNotEmpty
                        ? CachedNetworkImage(imageUrl: c.avatarUrl!, fit: BoxFit.cover)
                        : DecoratedBox(
                      decoration: const BoxDecoration(gradient: _gradient),
                      child: Center(child: Text(c.initials, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800))),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (available)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: const Color(0xFF22C55E), shape: BoxShape.circle, border: Border.all(color: palette.background, width: 3)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color == null ? palette.surfaceMuted : tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color ?? palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _TrustTile extends StatelessWidget {
  const _TrustTile({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, this.icon, this.dot, this.gradient = false});

  final String label;
  final IconData? icon;
  final Color? dot;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient ? _gradient : null,
        color: gradient ? null : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: gradient ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
              Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
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
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? _gradient : null,
          color: filled ? null : palette.surface,
          border: filled ? null : Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Center(
              child: busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: filled ? Colors.white : AppColors.primary),
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
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: context.text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
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
                    child: Text(_open ? 'Show less' : 'Read more', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
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
    const shadow = [Shadow(color: Colors.black54, blurRadius: 6)];
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: palette.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
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
                        ? const DecoratedBox(decoration: BoxDecoration(gradient: _gradient), child: Icon(AppIcons.store, color: Colors.white))
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
                  decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: const Text('Visit store', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
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