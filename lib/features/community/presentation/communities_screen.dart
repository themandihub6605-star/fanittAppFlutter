// File: lib/features/community/presentation/communities_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import '../../../core/services/purchase_policy.dart';
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
import '../../common/data/categories_repository.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';
import 'community_paid_join.dart';

// One look for the whole screen — same as Home: white cards, thin grey
// border, rounded pictures, orange only for actions and highlights.
const double _kRadius = 18;

BoxDecoration _frame(BuildContext context) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(_kRadius),
  border: Border.all(color: context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.7)),
);

/// Community picture: the cover, or a soft orange box with the icon.
Widget _cover(Community c, {double iconSize = 44}) {
  final url = c.coverImageUrl;
  if (url != null && url.isNotEmpty) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => const ColoredBox(color: Color(0x14F4511E)),
      errorWidget: (_, _, _) => ColoredBox(color: const Color(0x14F4511E), child: Center(child: CommunityIcon(name: c.name, url: c.iconUrl, size: iconSize))),
    );
  }
  return ColoredBox(color: const Color(0x14F4511E), child: Center(child: CommunityIcon(name: c.name, url: c.iconUrl, size: iconSize)));
}

/// Discover other creators' communities (and the ones you joined).
/// Communities you own are managed from My store → Community
/// ([MyCommunitiesScreen]), so they are not listed here.
class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<CommunityRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PagedCubit<Community>((page) => _withoutMine(repo.list(page: page)))),
        BlocProvider(create: (_) => LoadCubit<List<Community>>(() async => (await repo.mine()).where((c) => !c.isOwner).toList())),
      ],
      child: const _CommunitiesView(),
    );
  }
}

/// Same page from the server, without the communities I own.
Future<Paged<Community>> _withoutMine(Future<Paged<Community>> request) async {
  final p = await request;
  return Paged(items: p.items.where((c) => !c.isOwner).toList(), page: p.page, pages: p.pages, total: p.total);
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
  static const _perRow = 10;
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
    context.read<PagedCubit<Community>>().updateQuery((page) => _withoutMine(repo.list(page: page, search: text, sort: sort, categoryId: categoryId)));
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
    HapticFeedback.selectionClick();
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

  String _rowTitle(int row) {
    if (_query.isNotEmpty || _category != null) return row == 0 ? (_category?.label ?? 'Results') : 'More';
    return switch (_pill) {
      _Pill.popular => row == 0 ? 'Most popular' : 'More popular',
      _Pill.newest => row == 0 ? 'Just started' : 'More new',
      _ => row == 0 ? 'Trending now' : 'Recommended for you',
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canPop = Navigator.of(context).canPop();
    final paged = context.watch<PagedCubit<Community>>();
    final state = paged.state;
    final joined = context.watch<LoadCubit<List<Community>>>().state.data;
    final items = state.items;
    final filtering = _query.isNotEmpty || _category != null;
    // Spotlight: a featured one if any, else the biggest.
    Community? spotlight;
    if (!filtering && items.isNotEmpty) {
      spotlight = items.firstWhere((c) => c.isFeatured, orElse: () => ([...items]..sort((a, b) => b.memberCount.compareTo(a.memberCount))).first);
    }
    final rest = spotlight == null ? items : items.where((c) => c.id != spotlight!.id).toList();
    final rows = <List<Community>>[
      for (var i = 0; i < rest.length; i += _perRow) rest.sublist(i, (i + _perRow).clamp(0, rest.length)),
    ];

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (_pill != _Pill.joined && n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 400) paged.loadMore();
            return false;
          },
          child: RefreshIndicator.adaptive(
            color: AppColors.primary,
            onRefresh: () async {
              await paged.refresh();
              if (context.mounted) await context.read<LoadCubit<List<Community>>>().refresh();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                // Top bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        if (canPop) _RoundButton(icon: AppIcons.back, onTap: () => Navigator.of(context).maybePop()),
                        const Spacer(),
                        _RoundButton(icon: _searching ? AppIcons.close : AppIcons.search, onTap: _toggleSearch),
                        const SizedBox(width: 10),
                        _RoundButton(icon: AppIcons.sliders, dot: _category != null, onTap: _pickCategory),
                      ],
                    ),
                  ),
                ),
                // Title
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter + 4, 16, AppSpacing.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Communities', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.9, height: 1.1, color: palette.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Find your people — join, chat and grow together', style: TextStyle(fontSize: 14, color: palette.textSecondary)),
                      ],
                    ),
                  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1),
                ),
                // Search
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: !_searching
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 0),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: palette.border)),
                        child: Row(
                          children: [
                            Icon(AppIcons.search, size: 18, color: palette.textSecondary),
                            const SizedBox(width: 10),
                            Expanded(
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
                                style: TextStyle(fontSize: 14.5, color: palette.textPrimary),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Search communities',
                                  hintStyle: TextStyle(fontSize: 14.5, color: palette.textSecondary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Chips
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 58,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 4),
                      children: [
                        for (final p in _Pill.values)
                          _PillButton(
                            label: p == _Pill.joined && joined != null && joined.isNotEmpty ? '${p.label} · ${joined.length}' : p.label,
                            selected: _pill == p,
                            onTap: () => _selectPill(p),
                          ),
                        if (_category != null) _PillButton(label: _category!.label, selected: true, trailing: AppIcons.close, onTap: () {
                          setState(() => _category = null);
                          _reload();
                        }),
                      ],
                    ),
                  ),
                ),

                if (_pill == _Pill.joined)
                  const SliverFillRemaining(hasScrollBody: true, child: _JoinedTab(key: ValueKey('joined')))
                else if (state.isFirstLoad)
                  const SliverToBoxAdapter(child: _Skeleton())
                else if (items.isEmpty && state.errorMessage != null)
                    SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.errorMessage!, onRetry: paged.refresh))
                  else if (items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: MessageView(
                          icon: AppIcons.users,
                          title: filtering ? 'No communities match' : 'No communities yet',
                          message: filtering ? 'Try another name or category.' : 'Creators are setting theirs up — check back soon.',
                        ),
                      )
                    else ...[
                        if (spotlight != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 4),
                              child: _Spotlight(key: ValueKey('spot-${spotlight.id}'), community: spotlight),
                            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
                          ),
                        for (final (r, row) in rows.indexed) ...[
                          SliverToBoxAdapter(child: _RowHeader(title: _rowTitle(r), swipe: row.length > 1)),
                          SliverToBoxAdapter(
                            child: _CardRow(
                              key: PageStorageKey('${_pill.name}-${_category?.id}-$r'),
                              items: row,
                              onEnd: r == rows.length - 1 ? paged.loadMore : null,
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            child: Center(child: state.isLoading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const SizedBox.shrink()),
                          ),
                        ),
                      ],
                SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White round button with a thin border (back / search / categories).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.dot = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: palette.surface,
          shape: CircleBorder(side: BorderSide(color: palette.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 19, color: palette.textPrimary)),
          ),
        ),
        if (dot)
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2)),
            ).animate().scale(begin: const Offset(0.4, 0.4), curve: Curves.easeOutBack, duration: 300.ms),
          ),
      ],
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
          duration: const Duration(milliseconds: 180),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : palette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.primary : palette.border.withValues(alpha: 0.8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : palette.textPrimary)),
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

/// Join button — solid orange "Join" / price, soft "Joined", outline "Requested".
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
    final int kind; // 0 = solid, 1 = soft, 2 = outline
    if (c.isOwner) {
      label = 'Manage';
      kind = 1;
    } else if (c.needsPlan) {
      label = c.isExpired && PurchasePolicy.canBuyDigital ? 'Renew' : communityPriceLabel(c);
      kind = 0;
    } else if (c.isPending) {
      label = 'Requested';
      kind = 2;
    } else if (c.isMember) {
      label = 'Joined';
      kind = 1;
    } else {
      label = c.isPrivate ? 'Request' : 'Join';
      kind = 0;
    }
    final fg = kind == 0 ? Colors.white : (kind == 1 ? AppColors.primary : palette.textSecondary);
    return GestureDetector(
      onTap: busy || c.isBanned ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: compact ? 32 : 34,
        constraints: BoxConstraints(minWidth: compact ? 70 : 78),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kind == 0 ? AppColors.primary : (kind == 1 ? AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.10) : Colors.transparent),
          borderRadius: BorderRadius.circular(99),
          border: kind == 2 ? Border.all(color: palette.border) : null,
        ),
        child: busy
            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.isMember && !c.isOwner) ...[Icon(AppIcons.check, size: 13, color: fg), const SizedBox(width: 4)],
            Text(label, maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover: spotlight + rows of cards
// ---------------------------------------------------------------------------

String _accessLabel(Community c) => c.isPaid ? communityPriceLabel(c) : (c.isPrivate ? 'Private' : 'Free');

class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, required this.swipe});

  final String title;
  final bool swipe;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter + 4, 22, AppSpacing.gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary))),
          if (swipe)
            Row(
              children: [
                Text('Swipe', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textTertiary)),
                Icon(AppIcons.chevronRight, size: 14, color: palette.textTertiary),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms);
  }
}

/// Big card for the featured (or biggest) community.
class _Spotlight extends StatefulWidget {
  const _Spotlight({super.key, required this.community});

  final Community community;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with _JoinAction<_Spotlight> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.community;
    final category = c.category?.label ?? '';
    return _Pressable(
      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border),
          boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 30, offset: Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).width * 0.48,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  _cover(c, iconSize: 64),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: _WhiteTag(icon: c.isFeatured ? AppIcons.sparkle : AppIcons.users, label: c.isFeatured ? 'Featured' : 'Most loved', iconColor: AppColors.primary),
                  ),
                  Positioned(right: 14, top: 14, child: _WhiteTag(icon: c.isPaid ? AppIcons.crown : (c.isPrivate ? AppIcons.lock : AppIcons.globe), label: _accessLabel(c))),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Align(alignment: Alignment.centerLeft, child: CommunityIcon(name: c.name, url: c.iconUrl, size: 60, borderColor: palette.surface)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: palette.textPrimary)),
                        ),
                        CommunityBadges(community: c, size: 16),
                      ],
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(category, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.textSecondary)),
                    ],
                    if (c.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(c.description.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.4, color: palette.textPrimary)),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _Stat(value: Fmt.compact(c.memberCount), label: c.memberCount == 1 ? 'member' : 'members'),
                        const SizedBox(width: 8),
                        _Stat(value: Fmt.compact(c.discussionCount), label: 'posts'),
                        const SizedBox(width: 8),
                        _Stat(value: c.chatEnabled ? 'Live' : '—', label: 'group chat'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Dashed(color: palette.border),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.isMember ? 'You’re a member ✓' : (c.isPending ? 'Request sent' : 'Join ${Fmt.compact(c.memberCount)} others'),
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.isMember ? AppColors.success : palette.textSecondary),
                          ),
                        ),
                        _JoinButton(community: c, busy: busy, onTap: () => toggleJoin(c)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(color: palette.background, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text(value, maxLines: 1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: palette.textPrimary)),
            Text(label, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({super.key, required this.items, this.onEnd});

  final List<Community> items;
  final VoidCallback? onEnd;

  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    // Fixed part (border, paddings, gaps, dashed line, 32px Join button) +
    // the two text lines, which grow with the phone's font size, + a little room.
    return _CommunityTile.coverHeight + 108 + 40 * scale;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightFor(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (onEnd != null && n.metrics.axis == Axis.horizontal && n.metrics.pixels > n.metrics.maxScrollExtent - 200) onEnd!();
          return false;
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (context, i) => _CommunityTile(community: items[i])
              .animate(delay: (50 * i.clamp(0, 6)).ms)
              .fadeIn(duration: 320.ms)
              .slideX(begin: 0.12, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }
}

/// Card: cover with access tag, icon on the edge, name ✓, category,
/// members · posts, dashed line, then the join button.
class _CommunityTile extends StatefulWidget {
  const _CommunityTile({required this.community});

  final Community community;

  static const double width = 232;
  static const double coverHeight = 112;

  @override
  State<_CommunityTile> createState() => _CommunityTileState();
}

class _CommunityTileState extends State<_CommunityTile> with _JoinAction<_CommunityTile> {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = widget.community;
    final category = c.category?.label ?? '';
    return _Pressable(
      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
      child: SizedBox(
        width: _CommunityTile.width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border),
                boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    child: SizedBox(
                      height: _CommunityTile.coverHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _cover(c, iconSize: 40),
                          Positioned(right: 10, top: 10, child: _WhiteTag(icon: c.isPaid ? AppIcons.crown : (c.isPrivate ? AppIcons.lock : AppIcons.globe), label: _accessLabel(c), small: true)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 26, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary))),
                            CommunityBadges(community: c, size: 13),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [if (category.isNotEmpty) category, '${Fmt.compact(c.memberCount)} members'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: palette.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        _Dashed(color: palette.border),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Icon(AppIcons.feed, size: 13, color: palette.textTertiary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('${Fmt.compact(c.discussionCount)} posts', maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textSecondary)),
                            ),
                            _JoinButton(community: c, busy: busy, compact: true, onTap: () => toggleJoin(c)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(left: 12, top: _CommunityTile.coverHeight - 20, child: CommunityIcon(name: c.name, url: c.iconUrl, size: 40, borderColor: palette.surface)),
          ],
        ),
      ),
    );
  }
}

/// White chip on a picture.
class _WhiteTag extends StatelessWidget {
  const _WhiteTag({required this.icon, required this.label, this.iconColor, this.small = false});

  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 11 : 12, color: iconColor ?? const Color(0xFF475467)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 10.5 : 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF344054))),
          ),
        ],
      ),
    );
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 5.0;
        const gap = 4.0;
        final count = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              Container(width: dash, height: 1.2, color: color),
              if (i < count - 1) const SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget box(double w, double h, {double r = 12}) => Container(width: w, height: h, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(r)));
    final width = MediaQuery.sizeOf(context).width - AppSpacing.gutter * 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box(width, width * 0.5 + 200, r: 24),
          const SizedBox(height: 26),
          box(140, 16),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: [box(232, 230, r: 20), const SizedBox(width: 14), box(232, 230, r: 20)]),
          ),
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_kRadius),
        onTap: () async {
          await context.push(AppRoutes.communityDetail(c.slug));
          if (context.mounted) context.read<LoadCubit<List<Community>>>().refresh();
        },
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: _frame(context),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 60, height: 60, child: _cover(c, iconSize: 34))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary))),
                        CommunityBadges(community: c, size: 13),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('${Fmt.compact(c.memberCount)} members · ${Fmt.compact(c.discussionCount)} posts', style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
                  ],
                ),
              ),
              if (c.isPending)
                StatusChip(label: 'Requested', color: palette.textSecondary)
              else if (c.unreadChatCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.messages, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('${c.unreadChatCount}', style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w800)),
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
                            c.needsPlan ? (!PurchasePolicy.canBuyDigital ? 'Members only' : (c.isExpired ? 'Renew' : 'Join · ${communityPriceLabel(c)}')) : joinLabelFor(c),
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

// ---------------------------------------------------------------------------
// My communities (My store → Community): the ones I own, plus "Create".
// Calm look like My store: white cards, dark text, orange only on the main
// "Create community" button.
// ---------------------------------------------------------------------------

class MyCommunitiesScreen extends StatelessWidget {
  const MyCommunitiesScreen({super.key});

  /// Route for this screen (registered in app_router.dart). Under /app/store/
  /// so it needs a live Fanitt Store, like the other store tools.
  static const route = '/app/store/communities';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Community>>(() async => (await sl<CommunityRepository>().mine()).where((c) => c.isOwner).toList()),
      child: const _MyCommunitiesView(),
    );
  }
}

class _MyCommunitiesView extends StatelessWidget {
  const _MyCommunitiesView();

  Future<void> _create(BuildContext context) async {
    HapticFeedback.selectionClick();
    final created = await context.push<Community>(AppRoutes.communityForm);
    if (created == null || !context.mounted) return;
    context.read<LoadCubit<List<Community>>>().refresh();
    context.push(AppRoutes.communityDetail(created.slug));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Community>>>();
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('My communities', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _InkButton(label: 'New', icon: AppIcons.plus, onTap: () => _create(context), small: true, outlined: true),
          ),
        ],
      ),
      body: AsyncView<List<Community>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (items) => AppRefresh(
          onRefresh: cubit.refresh,
          child: items.isEmpty
              ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 40, AppSpacing.gutter, 40),
            children: [_EmptyCommunities(onCreate: () => _create(context)).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05)],
          )
              : ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
            children: [
              _OwnerSummary(items: items).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
              if (items.any((c) => c.pendingRequestCount > 0)) ...[
                const SizedBox(height: 12),
                _RequestsBanner(items: items),
              ],
              const SizedBox(height: 18),
              Text('Your communities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
              const SizedBox(height: 10),
              for (final (i, c) in items.indexed) ...[
                _OwnedCommunityCard(community: c).animate(delay: (60 * i.clamp(0, 6)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Summary — white card: members, posts, earnings.
class _OwnerSummary extends StatelessWidget {
  const _OwnerSummary({required this.items});

  final List<Community> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final members = items.fold<int>(0, (a, c) => a + c.memberCount);
    final posts = items.fold<int>(0, (a, c) => a + c.discussionCount);
    final earned = items.fold<int>(0, (a, c) => a + c.paidRevenue);
    final anyPaid = items.any((c) => c.isPaid || c.paidRevenue > 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: context.isDark ? 0.55 : 0.8)),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(10)),
                child: Icon(AppIcons.users, size: 16, color: palette.textPrimary),
              ),
              const SizedBox(width: 10),
              Text(
                items.length == 1 ? '1 community' : '${items.length} communities',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _DarkStat(value: Fmt.compact(members), label: 'Members'),
              const SizedBox(width: 8),
              _DarkStat(value: Fmt.compact(posts), label: 'Posts'),
              const SizedBox(width: 8),
              _DarkStat(value: anyPaid ? (earned == 0 ? '₹0' : Fmt.money(earned)) : 'Free', label: anyPaid ? 'Earned' : 'Plan', accent: anyPaid && earned > 0),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grey number box (green number when it's money earned).
class _DarkStat extends StatelessWidget {
  const _DarkStat({required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent ? AppColors.success : palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(color: palette.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// "3 people want to join" — opens the requests of the first community with any.
class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({required this.items});

  final List<Community> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = items.fold<int>(0, (a, c) => a + c.pendingRequestCount);
    final first = items.firstWhere((c) => c.pendingRequestCount > 0);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.selectionClick();
          await context.push(AppRoutes.communityMembers, extra: first);
          if (context.mounted) context.read<LoadCubit<List<Community>>>().refresh();
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
                child: Icon(AppIcons.userPlus, size: 18, color: palette.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$total ${total == 1 ? 'person wants' : 'people want'} to join', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(items.where((c) => c.pendingRequestCount > 0).length == 1 ? first.name : 'Across your private communities', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  ],
                ),
              ),
              Text('Review', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textPrimary)),
              Icon(AppIcons.chevronRight, size: 16, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedCommunityCard extends StatelessWidget {
  const _OwnedCommunityCard({required this.community});

  final Community community;

  Future<void> _go(BuildContext context, String route, {Object? extra}) async {
    HapticFeedback.selectionClick();
    await context.push(route, extra: extra);
    if (context.mounted) context.read<LoadCubit<List<Community>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = community;
    final hasCover = c.coverImageUrl != null && c.coverImageUrl!.isNotEmpty;
    final kind = c.isPaid ? communityPriceLabel(c) : 'Free';
    final access = c.isPrivate ? 'Private' : 'Public';

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 16, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cover band + icon
          GestureDetector(
            onTap: () => _go(context, AppRoutes.communityDetail(c.slug)),
            child: SizedBox(
              height: 118,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    bottom: 26,
                    child: hasCover
                        ? CachedNetworkImage(imageUrl: c.coverImageUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => ColoredBox(color: palette.surfaceMuted))
                        : DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [palette.surfaceMuted, palette.surfaceMuted.withValues(alpha: 0.5)]),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _GlassTag(icon: c.isPrivate ? AppIcons.lock : AppIcons.globe, label: access),
                  ),
                  Positioned(left: 14, bottom: 0, child: CommunityIcon(name: c.name, url: c.iconUrl, size: 56, borderColor: palette.surface)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
                    ),
                    CommunityBadges(community: c, size: 14),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [kind, if (c.category != null && c.category!.label.isNotEmpty) c.category!.label].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(icon: AppIcons.users, value: Fmt.compact(c.memberCount), label: 'members'),
                    _MiniStat(icon: AppIcons.feed, value: Fmt.compact(c.discussionCount), label: 'posts'),
                    if (c.isPaid || c.paidRevenue > 0) _MiniStat(icon: AppIcons.wallet, value: Fmt.money(c.paidRevenue), label: 'earned'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _InkButton(label: 'Open', icon: AppIcons.arrowUpRight, outlined: true, onTap: () => _go(context, AppRoutes.communityDetail(c.slug)))),
                    const SizedBox(width: 8),
                    _SquareAction(
                      icon: AppIcons.users,
                      tooltip: 'Members',
                      badge: c.pendingRequestCount,
                      onTap: () => _go(context, AppRoutes.communityMembers, extra: c),
                    ),
                    if (c.chatEnabled) ...[
                      const SizedBox(width: 8),
                      _SquareAction(icon: AppIcons.messages, tooltip: 'Chat', badge: c.unreadChatCount, onTap: () => _go(context, AppRoutes.communityChat, extra: c)),
                    ],
                    const SizedBox(width: 8),
                    _SquareAction(icon: AppIcons.gear, tooltip: 'Settings', onTap: () => _go(context, AppRoutes.communityForm, extra: c)),
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

class _GlassTag extends StatelessWidget {
  const _GlassTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0x73101828), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: palette.textSecondary),
          const SizedBox(width: 5),
          Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        ],
      ),
    );
  }
}

/// Rounded button: orange for the one main action, or white with a grey
/// border ([outlined]) for everything else.
class _InkButton extends StatelessWidget {
  const _InkButton({required this.label, required this.icon, required this.onTap, this.small = false, this.outlined = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool small;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = outlined ? palette.textPrimary : Colors.white;
    return Material(
      color: outlined ? palette.surface : AppColors.primary,
      shape: StadiumBorder(side: outlined ? BorderSide(color: palette.border) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: small ? 36 : 44,
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: small ? 15 : 16, color: outlined ? palette.textSecondary : fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontSize: small ? 13 : 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 19, color: palette.textPrimary)),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(99), border: Border.all(color: palette.surface, width: 1.5)),
                child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ).animate().scale(begin: const Offset(0.5, 0.5), curve: Curves.easeOutBack, duration: 350.ms),
            ),
        ],
      ),
    );
  }
}

class _EmptyCommunities extends StatelessWidget {
  const _EmptyCommunities({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 15, color: palette.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: palette.textPrimary))),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(18)),
            child: Icon(AppIcons.users, size: 26, color: palette.textPrimary),
          ),
          const SizedBox(height: 16),
          Text('Start your community', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: palette.textPrimary)),
          const SizedBox(height: 4),
          Text('A home for your fans — free or paid.', style: TextStyle(fontSize: 13.5, color: palette.textSecondary)),
          const SizedBox(height: 6),
          point(AppIcons.feed, 'Posts, polls and announcements'),
          point(AppIcons.messages, 'A group chat that stays live'),
          point(AppIcons.broadcast, 'Members-only live streams'),
          point(AppIcons.crown, 'Monthly, yearly or one-time plans'),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: _InkButton(label: 'Create community', icon: AppIcons.plus, onTap: onCreate)),
        ],
      ),
    );
  }
}