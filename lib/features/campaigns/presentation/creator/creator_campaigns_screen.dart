// File: lib/features/campaigns/presentation/creator/creator_campaigns_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/models/common_models.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../common/data/categories_repository.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';
import '../widgets/campaign_widgets.dart';

typedef ProposalsData = (List<Proposal>, ProposalCounts);

const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

class CreatorCampaignsScreen extends StatelessWidget {
  const CreatorCampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<CampaignRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PagedCubit<Campaign>((page) => repo.list(page: page))),
        BlocProvider(create: (_) => LoadCubit<ProposalsData>(repo.myProposals)),
        BlocProvider(create: (_) => LoadCubit<List<Campaign>>(repo.saved)),
        BlocProvider(create: (_) => LoadCubit<List<Category>>(sl<CategoriesRepository>().getAll)),
      ],
      child: const DefaultTabController(
        length: 3,
        child: Scaffold(
          body: _CampaignsBody(),
        ),
      ),
    );
  }
}

class _CampaignsBody extends StatelessWidget {
  const _CampaignsBody();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Campaigns', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                const SizedBox(height: 2),
                Text('Work with brands and get paid for your content', style: context.text.bodySmall?.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          const _SegmentTabs(),
          const Expanded(child: TabBarView(children: [_ExploreTab(), _ProposalsTab(), _SavedTab()])),
        ],
      ),
    );
  }
}

/// Pill tabs with live counts. Each tab's content scales down instead of
/// overflowing (narrow phones / large system font).
class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final proposals = context.watch<LoadCubit<ProposalsData>>().state.data;
    final saved = context.watch<LoadCubit<List<Campaign>>>().state.data;

    Widget tab(String label, int? count) => Tab(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, maxLines: 1),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                // Badge takes the tab's own text colour (orange when selected).
                Builder(
                  builder: (context) {
                    final color = DefaultTextStyle.of(context).style.color ?? palette.textSecondary;
                    return Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color, height: 1.2),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 12),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: palette.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: EdgeInsets.zero,
          splashBorderRadius: BorderRadius.circular(11),
          indicator: BoxDecoration(
            color: context.isDark ? palette.surface : Colors.white,
            borderRadius: BorderRadius.circular(11),
            boxShadow: const [BoxShadow(color: Color(0x1A101828), blurRadius: 8, offset: Offset(0, 2))],
          ),
          labelColor: AppColors.primary,
          unselectedLabelColor: palette.textSecondary,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: [
            tab('Explore', null),
            tab('Applied', proposals?.$2.all),
            tab('Saved', saved?.length),
          ],
        ),
      ),
    );
  }
}

/// Opens a campaign and refreshes the lists when the creator comes back
/// (they may have applied or saved it).
Future<void> openCampaign(BuildContext context, String id) async {
  await context.push(AppRoutes.campaignDetail(id));
  if (!context.mounted) return;
  context.read<LoadCubit<ProposalsData>>().refresh();
  context.read<LoadCubit<List<Campaign>>>().refresh();
}

/// Save / unsave from any list — updates the Saved tab right away.
Future<void> _toggleSave(BuildContext context, Campaign campaign) async {
  final savedCubit = context.read<LoadCubit<List<Campaign>>>();
  final current = savedCubit.state.data ?? const <Campaign>[];
  final wasSaved = current.any((c) => c.id == campaign.id);
  HapticFeedback.lightImpact();
  // Optimistic: flip first, undo if the server says no.
  savedCubit.replace(wasSaved ? current.where((c) => c.id != campaign.id).toList() : [campaign, ...current]);
  try {
    final saved = await sl<CampaignRepository>().toggleSave(campaign.id);
    if (saved == wasSaved) {
      // Server state differs from what we showed — resync.
      await savedCubit.refresh();
    } else if (context.mounted) {
      AppSnackbar.info(context, saved ? 'Saved — find it in the Saved tab' : 'Removed from saved');
    }
  } on ApiException catch (error) {
    savedCubit.replace(current);
    if (context.mounted) AppSnackbar.error(context, error.displayMessage);
  } catch (_) {
    savedCubit.replace(current);
  }
}

// ---------------------------------------------------------------------------
// Explore
// ---------------------------------------------------------------------------

enum _PayFilter { all, paid, barter }

class _ExploreTab extends StatefulWidget {
  const _ExploreTab();

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> with AutomaticKeepAliveClientMixin {
  String? _categoryId;
  _PayFilter _pay = _PayFilter.all;
  final _search = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectCategory(String? id) {
    HapticFeedback.selectionClick();
    setState(() => _categoryId = id);
    final repo = sl<CampaignRepository>();
    context.read<PagedCubit<Campaign>>().updateQuery((page) => repo.list(page: page, categoryId: id));
  }

  bool _matches(Campaign c) {
    if (_pay == _PayFilter.paid && !c.isPaid) return false;
    if (_pay == _PayFilter.barter && c.isPaid) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return c.title.toLowerCase().contains(q) || (c.brand?.name.toLowerCase().contains(q) ?? false) || c.locationLabel.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    final paged = context.watch<PagedCubit<Campaign>>();
    final state = paged.state;
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    final savedIds = {for (final c in context.watch<LoadCubit<List<Campaign>>>().state.data ?? const <Campaign>[]) c.id};

    final visible = state.items.where(_matches).toList();
    final featured = visible.where((c) => c.isFeatured).toList();
    final filtering = _query.isNotEmpty || _pay != _PayFilter.all;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 500) paged.loadMore();
        return false;
      },
      child: AppRefresh(
        onRefresh: paged.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Search
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 10),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search campaigns, brands, cities…',
                    prefixIcon: Icon(AppIcons.search, size: 20, color: palette.textSecondary),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(AppIcons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
                    hintStyle: TextStyle(color: palette.textTertiary, fontSize: 14),
                    filled: true,
                    fillColor: palette.surfaceMuted,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.4)),
                  ),
                ),
              ),
            ),
            // Paid / barter + categories
            SliverToBoxAdapter(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  children: [
                    for (final p in _PayFilter.values)
                      _FilterChip(
                        label: switch (p) { _PayFilter.all => 'All', _PayFilter.paid => 'Paid', _PayFilter.barter => 'Barter' },
                        icon: switch (p) { _PayFilter.all => AppIcons.sparkle, _PayFilter.paid => AppIcons.rupee, _PayFilter.barter => AppIcons.gift },
                        selected: _pay == p,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _pay = p);
                        },
                      ),
                    if (categories.isNotEmpty)
                      Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), color: palette.border),
                    for (final c in categories)
                      _FilterChip(label: c.label, selected: _categoryId == c.id, onTap: () => _selectCategory(_categoryId == c.id ? null : c.id)),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            if (state.isFirstLoad)
              const SliverToBoxAdapter(child: _ListSkeleton())
            else if (state.items.isEmpty && state.errorMessage != null)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.errorMessage!, onRetry: paged.refresh))
            else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: AppIcons.campaigns,
                    title: filtering ? 'No campaigns match' : 'No open campaigns right now',
                    message: filtering ? 'Try another search or filter.' : 'New campaigns from brands show up here. Pull down to check again.',
                  ),
                )
              else ...[
                  if (featured.isNotEmpty && !filtering) ...[
                    SliverToBoxAdapter(child: _SectionTitle(icon: AppIcons.sparkle, title: 'Featured', subtitle: 'Hand-picked by Fanitt')),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 196,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                          itemCount: featured.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _FeaturedCard(
                            campaign: featured[i],
                            saved: savedIds.contains(featured[i].id),
                            onTap: () => openCampaign(context, featured[i].id),
                            onSave: () => _toggleSave(context, featured[i]),
                          ).animate(delay: (50 * i.clamp(0, 6)).ms).fadeIn(duration: 260.ms).slideX(begin: 0.08, curve: Curves.easeOutCubic),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
                  ],
                  SliverToBoxAdapter(
                    child: _SectionTitle(
                      icon: AppIcons.campaigns,
                      title: filtering ? 'Results' : 'Open campaigns',
                      subtitle: '${visible.length}${state.hasMore ? '+' : ''} to apply for',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 0),
                    sliver: SliverList.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) => _CampaignTile(
                        campaign: visible[i],
                        saved: savedIds.contains(visible[i].id),
                        onTap: () => openCampaign(context, visible[i].id),
                        onSave: () => _toggleSave(context, visible[i]),
                      ).animate(delay: (40 * i.clamp(0, 6)).ms).fadeIn(duration: 260.ms).slideY(begin: 0.04, curve: Curves.easeOutCubic),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: state.isLoading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : !state.hasMore && state.items.isNotEmpty
                            ? Text('You’re all caught up', style: context.text.bodySmall?.copyWith(color: palette.textTertiary))
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = selected ? AppColors.primary : palette.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.1) : palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? AppColors.primary.withValues(alpha: 0.6) : palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? AppColors.primary : palette.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3))),
          if (subtitle != null) Text(subtitle!, style: context.text.bodySmall?.copyWith(color: palette.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Round bookmark on top of a picture.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap, this.onImage = true});

  final bool saved;
  final VoidCallback onTap;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: saved ? 'Remove from saved' : 'Save campaign',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: saved ? AppColors.primary : (onImage ? Colors.black.withValues(alpha: 0.35) : palette.surfaceMuted),
            border: Border.all(color: onImage ? Colors.white.withValues(alpha: 0.35) : palette.border),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Icon(
              saved ? AppIcons.bookmarkFilled : AppIcons.bookmark,
              key: ValueKey(saved),
              size: 17,
              color: saved || onImage ? Colors.white : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

/// Cover picture — the campaign image, or a brand-coloured block with the logo.
class _Cover extends StatelessWidget {
  const _Cover({required this.campaign, this.height});

  final Campaign campaign;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final url = campaign.campaignImageUrl;
    if (url != null && url.isNotEmpty) return AppNetworkImage(url: url, height: height, width: double.infinity, placeholderIcon: AppIcons.campaigns);
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: _brandGradient),
      alignment: Alignment.center,
      child: campaign.brand?.logoUrl == null
          ? const Icon(AppIcons.campaigns, color: Colors.white, size: 38)
          : Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: AppNetworkImage(url: campaign.brand!.logoUrl, width: 64, height: 64, radius: 14, placeholderIcon: AppIcons.brand),
      ),
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.campaign, required this.saved, required this.onTap, required this.onSave});

  final Campaign campaign;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = campaign;
    // Applying ≠ hired: "creators needed" is how many the brand will hire.
    // Applications only close when the brand's applicant limit is reached.
    final limit = c.applicantLimit ?? 0;
    final hasLimit = limit > 0;
    final closed = hasLimit && c.applicantCount >= limit;
    final applied = c.applicantCount == 1 ? '1 applied' : '${c.applicantCount} applied';
    final needed = c.maxInfluencers > 0 ? (c.maxInfluencers == 1 ? '1 creator needed' : '${c.maxInfluencers} creators needed') : null;
    final hasImage = c.campaignImageUrl != null && c.campaignImageUrl!.isNotEmpty;
    final payColor = c.isPaid ? AppColors.success : AppColors.warning;

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.border.withValues(alpha: 0.7)),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand row
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: palette.border)),
                      child: AppNetworkImage(url: c.brand?.logoUrl, width: 40, height: 40, radius: 11, placeholderIcon: AppIcons.brand),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.brand?.name ?? 'Brand',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (c.category != null)
                            Text(c.category!.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: palette.textTertiary)),
                        ],
                      ),
                    ),
                    _SaveButton(saved: saved, onTap: onSave, onImage: false),
                  ],
                ),
                const SizedBox(height: 12),

                // Cover (only when the brand added one)
                if (hasImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _Cover(campaign: c, height: 150),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Row(
                              children: [
                                if (c.isFeatured) const _Badge(label: 'FEATURED', icon: AppIcons.sparkle, color: Color(0xFFF59E0B)),
                                if (c.isFeatured && c.isExclusive) const SizedBox(width: 6),
                                if (c.isExclusive) const _Badge(label: 'PRO ONLY', icon: AppIcons.crown, color: Color(0xFF6366F1)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else if (c.isFeatured || c.isExclusive) ...[
                  Row(
                    children: [
                      if (c.isFeatured) const _Badge(label: 'FEATURED', icon: AppIcons.sparkle, color: Color(0xFFF59E0B)),
                      if (c.isFeatured && c.isExclusive) const SizedBox(width: 6),
                      if (c.isExclusive) const _Badge(label: 'PRO ONLY', icon: AppIcons.crown, color: Color(0xFF6366F1)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Title + details
                Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InfoChip(icon: AppIcons.mapPin, label: c.locationLabel),
                    if (!c.deliverables.isEmpty) _InfoChip(icon: AppIcons.videoCamera, label: c.deliverables.summary),
                    if (c.minFollowers != null && c.minFollowers! > 0) _InfoChip(icon: AppIcons.users, label: '${Fmt.compact(c.minFollowers!)}+ followers'),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, thickness: 1, color: palette.border.withValues(alpha: 0.7)),
                ),

                // Pay + action
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.isPaid ? 'Pay per creator' : 'Barter collab', style: context.text.bodySmall?.copyWith(fontSize: 11, color: palette.textTertiary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Icon(c.isPaid ? AppIcons.rupee : AppIcons.gift, size: 16, color: payColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  c.isPaid ? Fmt.money(c.costPerInfluencer) : 'Free products',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: payColor, letterSpacing: -0.3),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: closed ? null : _brandGradient,
                        color: closed ? palette.surfaceMuted : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(closed ? 'Closed' : 'View', style: TextStyle(color: closed ? palette.textSecondary : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                          if (!closed) ...[
                            const SizedBox(width: 4),
                            const Icon(AppIcons.arrowRightSimple, color: Colors.white, size: 15),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Spots
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(AppIcons.users, size: 13, color: palette.textTertiary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        [if (needed != null) needed, applied].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: palette.textSecondary),
                      ),
                    ),
                    if (hasLimit)
                      Text(
                        closed ? 'Applications closed' : '${limit - c.applicantCount} left',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: closed ? AppColors.error : AppColors.primary),
                      ),
                  ],
                ),
                if (hasLimit) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (c.applicantCount / limit).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: palette.surfaceMuted,
                      valueColor: AlwaysStoppedAnimation(closed ? AppColors.error : AppColors.primary),
                    ),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.textSecondary),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.campaign, required this.saved, required this.onTap, required this.onSave});

  final Campaign campaign;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    return SizedBox(
      width: 290,
      child: Material(
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Cover(campaign: c),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0x11000000), Color(0xDD000000)],
                    stops: [0, 0.35, 1],
                  ),
                ),
              ),
              const Positioned(left: 12, top: 12, child: _Badge(label: 'FEATURED', icon: AppIcons.sparkle, color: Color(0xFFF59E0B))),
              Positioned(right: 10, top: 10, child: _SaveButton(saved: saved, onTap: onSave)),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.brand?.name ?? 'Brand',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            c.isPaid ? '${Fmt.money(c.costPerInfluencer)} / creator' : 'Barter',
                            style: TextStyle(color: c.isPaid ? AppColors.success : AppColors.warning, fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
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

/// Grey placeholder cards while the first page loads.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget box(double h, {double? w, double r = 10}) => Container(height: h, width: w, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(r)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: palette.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box(150, r: 22),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [box(16, w: 220), const SizedBox(height: 8), box(12, w: 160), const SizedBox(height: 14), box(44, r: 14)],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}

// ---------------------------------------------------------------------------
// Applied (my proposals)
// ---------------------------------------------------------------------------

class _ProposalsTab extends StatefulWidget {
  const _ProposalsTab();

  @override
  State<_ProposalsTab> createState() => _ProposalsTabState();
}

class _ProposalsTabState extends State<_ProposalsTab> with AutomaticKeepAliveClientMixin {
  ProposalStatus? _filter;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cubit = context.watch<LoadCubit<ProposalsData>>();

    return AsyncView<ProposalsData>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (data) {
        final (proposals, counts) = data;
        final visible = _filter == null ? proposals : proposals.where((p) => p.status == _filter).toList();
        int count(ProposalStatus? s) => switch (s) {
          null => counts.all,
          ProposalStatus.pending => counts.pending,
          ProposalStatus.accepted => counts.accepted,
          ProposalStatus.rejected => counts.rejected,
        };
        String label(ProposalStatus? s) => switch (s) {
          null => 'All',
          ProposalStatus.pending => 'Pending',
          ProposalStatus.accepted => 'Accepted',
          ProposalStatus.rejected => 'Declined',
        };

        return AppRefresh(
          onRefresh: cubit.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Summary strip
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 12),
                  child: Row(
                    children: [
                      _StatBox(label: 'Sent', value: counts.all, color: AppColors.info),
                      const SizedBox(width: 8),
                      _StatBox(label: 'Pending', value: counts.pending, color: AppColors.warning),
                      const SizedBox(width: 8),
                      _StatBox(label: 'Accepted', value: counts.accepted, color: AppColors.success),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                    children: [
                      for (final s in const [null, ProposalStatus.pending, ProposalStatus.accepted, ProposalStatus.rejected])
                        _FilterChip(
                          label: '${label(s)} ${count(s)}',
                          selected: _filter == s,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _filter = s);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              if (visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: AppIcons.paperPlane,
                    title: 'No proposals here',
                    message: 'Proposals you send to brands appear in this list.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.xxl),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _ProposalCard(proposal: visible[index])
                        .animate(delay: (35 * index.clamp(0, 6)).ms)
                        .fadeIn(duration: 240.ms)
                        .slideY(begin: 0.04, curve: Curves.easeOutCubic),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text('$value', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final campaign = proposal.campaign;
    final color = proposal.status.color;
    final meta = [
      if (proposal.quotedAmount != null) 'Quote ${Fmt.money(proposal.quotedAmount!)}',
      if (proposal.createdAt != null) 'Sent ${Fmt.relative(proposal.createdAt!)}',
    ].join(' · ');
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: campaign == null ? null : () => openCampaign(context, campaign.id),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border.withValues(alpha: 0.7)),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x08101828), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppNetworkImage(url: campaign?.campaignImageUrl ?? campaign?.brand?.logoUrl, width: 56, height: 56, radius: 14, placeholderIcon: AppIcons.campaigns),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            campaign?.brand?.name ?? 'Campaign',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: palette.textTertiary, fontSize: 11.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            campaign?.title ?? 'This campaign is no longer available',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: palette.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(label: proposal.status.label, color: color),
                  ],
                ),
                if (proposal.status == ProposalStatus.rejected && proposal.rejectionReason != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Text('Reason: ${proposal.rejectionReason}', style: context.text.bodySmall?.copyWith(color: AppColors.error, fontSize: 12)),
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

// ---------------------------------------------------------------------------
// Saved
// ---------------------------------------------------------------------------

class _SavedTab extends StatefulWidget {
  const _SavedTab();

  @override
  State<_SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<_SavedTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cubit = context.watch<LoadCubit<List<Campaign>>>();
    return AsyncView<List<Campaign>>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (saved) => AppRefresh(
        onRefresh: cubit.refresh,
        child: saved.isEmpty
            ? const ScrollableMessage(
          child: MessageView(
            icon: AppIcons.bookmark,
            title: 'Nothing saved yet',
            message: 'Tap the bookmark on any campaign to keep it here for later.',
          ),
        )
            : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, AppSpacing.xxl),
          itemCount: saved.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) => _CampaignTile(
            campaign: saved[index],
            saved: true,
            onTap: () => openCampaign(context, saved[index].id),
            onSave: () => _toggleSave(context, saved[index]),
          ),
        ),
      ),
    );
  }
}