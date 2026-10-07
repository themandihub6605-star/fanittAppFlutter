import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../content/data/content_repository.dart';
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
    cubit.replace(CreatorPublicProfile(
      creator: data.creator.copyWith(isFollowing: result.following, followerCount: result.followerCount),
      reviews: data.reviews,
      projectsCompleted: data.projectsCompleted,
      posts: data.posts,
    ));
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

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data, required this.slug, required this.onFollow});

  final CreatorPublicProfile data;
  final String slug;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final c = data.creator;
    final palette = context.palette;
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final isMe = auth is AuthAuthenticated && auth.user.id == c.userId;
    final topInset = MediaQuery.paddingOf(context).top;
    final verified = c.verificationStatus == VerificationStatus.verified;
    final links = <String, String>{...c.socials.values, if (c.portfolioLink.isNotEmpty) 'website': c.portfolioLink};

    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: RefreshIndicator.adaptive(
          color: AppColors.primary,
          edgeOffset: topInset,
          onRefresh: context.read<LoadCubit<CreatorPublicProfile>>().refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Big photo header that collapses into a bar with the name.
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: 360,
                backgroundColor: const Color(0xFF14141F),
                foregroundColor: Colors.white,
                title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                actions: [
                  ShareIconButton(
                    onDark: true,
                    size: 40,
                    message: () => ShareService.creator(slug: c.slug, name: c.name, category: c.category?.label ?? '', mine: isMe),
                  ),
                  const SizedBox(width: 10),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'creator-photo-$slug',
                        child: c.avatarUrl != null && c.avatarUrl!.isNotEmpty
                            ? CachedNetworkImage(imageUrl: c.avatarUrl!, fit: BoxFit.cover, alignment: Alignment.topCenter)
                            : (c.coverImageUrl != null && c.coverImageUrl!.isNotEmpty
                            ? CachedNetworkImage(imageUrl: c.coverImageUrl!, fit: BoxFit.cover)
                            : DecoratedBox(
                          decoration: const BoxDecoration(gradient: _gradient),
                          child: Center(child: Text(c.initials, style: const TextStyle(color: Colors.white, fontSize: 90, fontWeight: FontWeight.w800))),
                        )),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66000000), Color(0x00000000), Color(0xEE000000)],
                            stops: [0, 0.4, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.gutter,
                        right: AppSpacing.gutter,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (c.isAvailableForWork) const _HeaderChip(label: 'Available for work', dot: Color(0xFF34D399)),
                                if (c.isProPlan) _HeaderChip(label: c.planName, icon: AppIcons.crown, gradient: true),
                                if (c.category != null && c.category!.label.isNotEmpty) _HeaderChip(label: c.category!.label),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5),
                                  ),
                                ),
                                if (verified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(AppIcons.sealCheck, color: Color(0xFF60A5FA), size: 24),
                                ],
                              ],
                            ),
                            if (c.title.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            ],
                            if (c.location.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(AppIcons.mapPin, size: 14, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(c.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.huge),
                sliver: SliverList.list(
                  children: [
                    // Numbers
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                      child: Row(
                        children: [
                          _Stat(value: Fmt.compact(c.followerCount), label: 'Followers'),
                          _Divider(color: palette.border),
                          _Stat(value: c.reviewCount == 0 ? '—' : c.averageRating.toStringAsFixed(1), label: c.reviewCount == 0 ? 'Rating' : '${c.reviewCount} reviews', icon: c.reviewCount == 0 ? null : AppIcons.starFilled),
                          _Divider(color: palette.border),
                          _Stat(value: '${data.projectsCompleted}', label: 'Projects'),
                          if (c.yearsOfExperience != null) ...[
                            _Divider(color: palette.border),
                            _Stat(value: '${c.yearsOfExperience}y', label: 'Experience'),
                          ],
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08),
                    const SizedBox(height: AppSpacing.md),

                    // Actions
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
                              onTap: actions.isBusy ? null : onFollow,
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

                    if (c.bio.isNotEmpty) _Section(title: 'About', icon: AppIcons.user, child: _Expandable(text: c.bio)),

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
                        title: 'Find them online',
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
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                        child: const Icon(AppIcons.link, size: 17, color: AppColors.primary),
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
                                      Icon(AppIcons.chevronRight, size: 16, color: palette.textTertiary),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    if (data.posts.isNotEmpty)
                      _Section(title: 'Posts', icon: AppIcons.image, padded: false, child: _PostGrid(posts: data.posts)),

                    _Section(
                      title: 'Reviews${c.reviewCount > 0 ? ' · ${c.reviewCount}' : ''}',
                      icon: AppIcons.star,
                      child: data.reviews.isEmpty
                          ? Text('No reviews yet.', style: context.text.bodyMedium)
                          : Column(
                        children: [
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

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      children: [
        for (final post in posts)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: post.media.isNotEmpty && !post.media.first.isVideo
                ? AppNetworkImage(url: post.media.first.url)
                : Container(
              color: palette.surfaceMuted,
              child: Icon(post.media.isEmpty ? AppIcons.fileText : AppIcons.play, color: palette.textSecondary),
            ),
          ),
      ],
    );
  }
}