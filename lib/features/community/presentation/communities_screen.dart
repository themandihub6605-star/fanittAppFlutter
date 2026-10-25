// File: lib/features/community/presentation/communities_screen.dart
import 'dart:async';

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
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';
import 'community_paid_join.dart';

const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

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

/// The pills under the title. "Joined" shows the communities you're in.
enum _Pill { forYou, popular, newest, joined }

extension on _Pill {
  String get label => switch (this) {
    _Pill.forYou => 'For You',
    _Pill.popular => 'Popular',
    _Pill.newest => 'New',
    _Pill.joined => 'Joined',
  };

  CommunitySort get sort => switch (this) {
    _Pill.popular => CommunitySort.popular,
    _Pill.newest => CommunitySort.newest,
    _ => CommunitySort.trending,
  };
}

class _CommunitiesView extends StatefulWidget {
  const _CommunitiesView();

  @override
  State<_CommunitiesView> createState() => _CommunitiesViewState();
}

class _CommunitiesViewState extends State<_CommunitiesView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  _Pill _pill = _Pill.forYou;
  Category? _category;
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String get _query => _search.text.trim();

  void _reload() {
    final repo = sl<CommunityRepository>();
    final text = _query;
    final sort = _pill.sort;
    final categoryId = _category?.id;
    context.read<PagedCubit<Community>>().updateQuery((page) => repo.list(page: page, search: text, sort: sort, categoryId: categoryId));
  }

  void _selectPill(_Pill p) {
    if (p == _pill) return;
    HapticFeedback.selectionClick();
    setState(() => _pill = p);
    if (p == _Pill.joined) {
      context.read<LoadCubit<List<Community>>>().refresh();
    } else {
      _reload();
    }
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
      if (_search.text.isNotEmpty) {
        _search.clear();
        _reload();
      }
    }
  }

  Future<void> _pickCategory() async {
    final categories = await sl<CategoriesRepository>().getAll().catchError((_) => const <Category>[]);
    if (!mounted) return;
    final picked = await showAppSheet<Category?>(
      context,
      builder: (sheet) => SheetBody(
        title: 'Categories',
        subtitle: 'Find communities for your niche',
        child: categories.isEmpty
            ? Text('No categories yet.', style: sheet.text.bodyMedium)
            : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PillButton(label: 'All', selected: _category == null, onTap: () => Navigator.of(sheet).pop(const Category(id: '', label: ''))),
            for (final c in categories) _PillButton(label: c.label, selected: _category?.id == c.id, onTap: () => Navigator.of(sheet).pop(c)),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _category = picked.id.isEmpty ? null : picked;
      if (_pill == _Pill.joined) _pill = _Pill.forYou;
    });
    _reload();
  }

  Future<void> _create() async {
    HapticFeedback.selectionClick();
    final created = await context.push<Community>(AppRoutes.communityForm);
    if (created == null || !mounted) return;
    context.read<LoadCubit<List<Community>>>().refresh();
    _reload();
    context.push(AppRoutes.communityDetail(created.slug));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canPop = Navigator.of(context).canPop();
    // Fans join communities; creating one is for creators / brands / agencies.
    final auth = context.watch<AuthBloc>().state;
    final canCreate = auth is AuthAuthenticated && auth.user.role != UserRole.fan;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Title row: back, "Communities", search, create.
            Padding(
              padding: EdgeInsets.fromLTRB(canPop ? 4 : AppSpacing.gutter, 8, AppSpacing.gutter, 4),
              child: Row(
                children: [
                  if (canPop) const BackButton(),
                  Expanded(
                    child: Text('Communities', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ),
                  IconButton(
                    tooltip: _searching ? 'Close search' : 'Search',
                    onPressed: _toggleSearch,
                    icon: Icon(_searching ? AppIcons.close : AppIcons.search, size: 24, color: palette.textPrimary),
                  ),
                  if (canCreate) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _create,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _brandGradient,
                          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
                        ),
                        child: const Icon(AppIcons.plus, color: Colors.white, size: 22),
                      ),
                    ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack),
                  ],
                ],
              ),
            ),
            // Search box (opens from the search icon).
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: !_searching
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 6),
                child: TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      if (_pill == _Pill.joined) setState(() => _pill = _Pill.forYou);
                      _reload();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search communities',
                    prefixIcon: Icon(AppIcons.search, size: 20, color: palette.textSecondary),
                    filled: true,
                    fillColor: palette.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
                  ),
                ),
              ),
            ),
            // Pills: For You / Popular / New / Joined / Categories
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 6),
                children: [
                  for (final p in _Pill.values) _PillButton(label: p.label, selected: _pill == p, onTap: () => _selectPill(p)),
                  _PillButton(
                    label: _category?.label ?? 'Categories',
                    selected: _category != null,
                    trailing: AppIcons.chevronDown,
                    onTap: _pickCategory,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _pill == _Pill.joined
                    ? const _JoinedTab(key: ValueKey('joined'))
                    : _DiscoverList(
                  key: const ValueKey('discover'),
                  title: _pill == _Pill.forYou ? 'Trending Communities' : (_pill == _Pill.popular ? 'Most popular' : 'Newest'),
                  showRail: _query.isEmpty,
                  searching: _query.isNotEmpty || _category != null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.selected, required this.onTap, this.trailing});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? _brandGradient : null,
            color: selected ? null : palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : palette.border.withValues(alpha: 0.8)),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 5))]
                : (context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 8, offset: Offset(0, 2))]),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : palette.textPrimary)),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 14, color: selected ? Colors.white : palette.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 18))),
          if (trailing != null) Text(trailing!, style: context.text.bodySmall?.copyWith(color: palette.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Discover: a rail of the top communities, then the rest as rows.
class _DiscoverList extends StatelessWidget {
  const _DiscoverList({super.key, required this.title, required this.showRail, required this.searching});

  final String title;
  final bool showRail;
  final bool searching;

  static const _railCount = 6;

  @override
  Widget build(BuildContext context) {
    final paged = context.watch<PagedCubit<Community>>();
    final state = paged.state;
    final items = state.items;
    // Trending = the communities with the most members; the rest are recommended.
    final byMembers = [...items]..sort((a, b) => b.memberCount.compareTo(a.memberCount));
    final rail = showRail && !searching ? byMembers.take(_railCount).toList() : const <Community>[];
    // With few communities, the rail alone would hide the list — keep all in the list then.
    final railShown = rail.length >= 3;
    final railIds = {for (final c in rail) c.id};
    final list = railShown ? items.where((c) => !railIds.contains(c.id)).toList() : items;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 500) paged.loadMore();
        return false;
      },
      child: AppRefresh(
        onRefresh: () async {
          await paged.refresh();
          if (context.mounted) await context.read<LoadCubit<List<Community>>>().refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (state.isFirstLoad)
              const SliverToBoxAdapter(child: _Skeleton())
            else if (items.isEmpty && state.errorMessage != null)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.errorMessage!, onRetry: paged.refresh))
            else if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: AppIcons.users,
                    title: searching ? 'No communities match' : 'No communities yet',
                    message: searching ? 'Try another name or category.' : 'Create the first one for your niche.',
                  ),
                )
              else ...[
                  if (railShown) ...[
                    SliverToBoxAdapter(child: _SectionHeader(title: title)),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 254,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                          itemCount: rail.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _TrendingCard(community: rail[i])
                              .animate(delay: (50 * i).ms)
                              .fadeIn(duration: 260.ms)
                              .slideX(begin: 0.08, curve: Curves.easeOutCubic),
                        ),
                      ),
                    ),
                  ],
                  if (list.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        title: searching ? 'Results' : (railShown ? 'Recommended for You' : title),
                        trailing: '${Fmt.compact(items.length)}${state.hasMore ? '+' : ''} communities',
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                      sliver: SliverList.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _CommunityRow(community: list[i])
                            .animate(delay: (35 * i.clamp(0, 6)).ms)
                            .fadeIn(duration: 240.ms)
                            .slideY(begin: 0.05, curve: Curves.easeOutCubic),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Center(
                        child: state.isLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

/// Join / leave logic shared by the rail cards and the rows.
mixin _JoinAction<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> toggleJoin(Community c) async {
    if (c.isOwner || c.isBanned) {
      context.push(AppRoutes.communityDetail(c.slug));
      return;
    }
    // Paid community / already a member: plans, chat and leaving live on its page.
    if (c.needsPlan || c.isMember) {
      context.push(AppRoutes.communityDetail(c.slug));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => busy = true);
    try {
      final status = await sl<CommunityRepository>().toggleJoin(c.id);
      if (!mounted) return;
      final updated = status == null
          ? c.copyWith(clearMembership: true)
          : c.copyWith(
        membership: CommunityMembership(role: CommunityRole.member, status: status, muted: false),
        memberCount: status == MembershipStatus.active ? c.memberCount + 1 : c.memberCount,
      );
      context.read<PagedCubit<Community>>().updateItem((x) => x.id == c.id, (_) => updated);
      context.read<LoadCubit<List<Community>>>().refresh();
      if (status == MembershipStatus.pending) {
        AppSnackbar.info(context, 'Request sent — a moderator will approve it.');
      } else if (status == MembershipStatus.active) {
        AppSnackbar.success(context, 'Welcome to ${c.name}!');
      }
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// Join button — gradient "Join", soft "Joined" / "Requested", or the plan price.
class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.community, required this.busy, required this.onTap, this.compact = false});

  final Community community;
  final bool busy;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = community;
    final String label;
    final bool primary;
    if (c.isOwner) {
      label = 'Manage';
      primary = false;
    } else if (c.needsPlan) {
      label = c.isExpired ? 'Renew' : communityPriceLabel(c);
      primary = true;
    } else if (c.isPending) {
      label = 'Requested';
      primary = false;
    } else if (c.isMember) {
      label = 'Joined';
      primary = false;
    } else {
      label = c.isPrivate ? 'Request' : 'Join';
      primary = true;
    }
    return GestureDetector(
      onTap: busy || c.isBanned ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: compact ? 32 : 36,
        constraints: BoxConstraints(minWidth: compact ? 72 : 80),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: primary ? _brandGradient : null,
          color: primary ? null : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(compact ? 16 : 18),
          border: primary ? null : Border.all(color: palette.border),
          boxShadow: primary ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: busy
            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primary ? Colors.white : AppColors.primary))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.isMember && !c.isOwner) ...[
              Icon(AppIcons.check, size: 13, color: palette.textPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary ? Colors.white : palette.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Members line with the people icon.
class _Members extends StatelessWidget {
  const _Members({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final n = community.memberCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.users, size: 13, color: palette.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${Fmt.compact(n)} ${n == 1 ? 'member' : 'members'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Rail card: soft cover band, round icon with a ring, name, line and members.
class _TrendingCard extends StatefulWidget {
  const _TrendingCard({required this.community});

  final Community community;

  @override
  State<_TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<_TrendingCard> with _JoinAction<_TrendingCard> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.community;
    final line = c.description.trim().isNotEmpty ? c.description.trim() : (c.category?.label ?? '');
    return SizedBox(
      width: 168,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border.withValues(alpha: 0.8)),
              boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 96,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: [
                      // Soft cover band at the top.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 52,
                        child: c.coverImageUrl == null
                            ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppColors.primary.withValues(alpha: 0.18), AppColors.primary.withValues(alpha: 0.02)],
                            ),
                          ),
                        )
                            : Opacity(opacity: 0.55, child: CommunityCover(url: c.coverImageUrl, fadeTo: palette.surface)),
                      ),
                      Positioned(
                        top: 14,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brandGradient),
                          child: CommunityIcon(name: c.name, url: c.iconUrl, size: 72, borderColor: palette.surface),
                        ),
                      ),
                      if (c.isFeatured)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(AppIcons.sparkle, size: 16, color: Color(0xFFF59E0B)),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 14, height: 1.2),
                            ),
                          ),
                          CommunityBadges(community: c, size: 13),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall?.copyWith(fontSize: 11.5, height: 1.35, color: palette.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _Members(community: c)),
                          _JoinButton(community: c, busy: busy, compact: true, onTap: () => toggleJoin(c)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// List row: picture on the left (cover, or the icon), name, line, members, Join.
class _CommunityRow extends StatefulWidget {
  const _CommunityRow({required this.community});

  final Community community;

  @override
  State<_CommunityRow> createState() => _CommunityRowState();
}

class _CommunityRowState extends State<_CommunityRow> with _JoinAction<_CommunityRow> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.community;
    final line = c.description.trim().isNotEmpty ? c.description.trim() : (c.category?.label ?? '');
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border.withValues(alpha: 0.8)),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 14, offset: Offset(0, 5))],
          ),
          child: Row(
            children: [
              // Picture with the community icon on its corner.
              SizedBox(
                width: 92,
                height: 80,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: c.coverImageUrl != null
                            ? CommunityCover(url: c.coverImageUrl)
                            : DecoratedBox(
                          decoration: const BoxDecoration(gradient: _brandGradient),
                          child: Center(child: CommunityIcon(name: c.name, url: c.iconUrl, size: 50, borderColor: Colors.white)),
                        ),
                      ),
                    ),
                    if (c.coverImageUrl != null)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: CommunityIcon(name: c.name, url: c.iconUrl, size: 28, borderColor: palette.surface),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 15, height: 1.2))),
                        CommunityBadges(community: c, size: 13),
                      ],
                    ),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: palette.textSecondary, fontSize: 12.5)),
                    ],
                    const SizedBox(height: 6),
                    _Members(community: c),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _JoinButton(community: c, busy: busy, onTap: () => toggleJoin(c)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget box(double w, double h, {double r = 12}) => Container(width: w, height: h, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(r)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(180, 18),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Row(children: [Expanded(child: box(double.infinity, 220, r: 20)), const SizedBox(width: 12), Expanded(child: box(double.infinity, 220, r: 20))]),
          ),
          const SizedBox(height: 20),
          box(200, 18),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 10), child: box(double.infinity, 100, r: 18)),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}

// ---------------------------------------------------------------------------
// Joined
// ---------------------------------------------------------------------------

class _JoinedTab extends StatelessWidget {
  const _JoinedTab({super.key});

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
          child: MessageView(icon: AppIcons.users, title: 'No communities yet', message: 'Communities you join show up here.'),
        )
            : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 96),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _JoinedTile(community: items[i]).animate(delay: (30 * i.clamp(0, 6)).ms).fadeIn(duration: 220.ms),
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
    final palette = context.palette;
    final c = community;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push(AppRoutes.communityDetail(c.slug));
          if (context.mounted) context.read<LoadCubit<List<Community>>>().refresh();
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              CommunityIcon(name: c.name, url: c.iconUrl, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c.name, maxLines: 2, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2), overflow: TextOverflow.ellipsis)),
                        CommunityBadges(community: c, size: 13),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${Fmt.compact(c.memberCount)} members · ${Fmt.compact(c.discussionCount)} posts', style: context.text.bodySmall?.copyWith(fontSize: 12)),
                  ],
                ),
              ),
              if (c.isPending)
                StatusChip(label: 'Requested', color: palette.textSecondary)
              else if (c.unreadChatCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.messages, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('${c.unreadChatCount}', style: context.text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
                )
              else if (c.membership != null && c.membership!.role != CommunityRole.member)
                  RoleChip(role: c.membership!.role)
                else
                  Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
            ],
          ),
        ),
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