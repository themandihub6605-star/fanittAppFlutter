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
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_sheet.dart';
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
      child: Scaffold(
        // Light grey page so the white campaign cards stand out.
        backgroundColor: context.isDark ? null : context.palette.surfaceMuted,
        body: const _CampaignsBody(),
      ),
    );
  }
}

/// Which list is showing. Switched from the filter sheet (no tabs on top).
enum _View { explore, applied, saved }

enum _PayFilter { all, paid, barter }

String _payLabel(_PayFilter p) => switch (p) { _PayFilter.all => 'All', _PayFilter.paid => 'Paid', _PayFilter.barter => 'Barter' };

String _statusLabel(ProposalStatus? s) => switch (s) {
  null => 'All',
  ProposalStatus.pending => 'Pending',
  ProposalStatus.accepted => 'Accepted',
  ProposalStatus.rejected => 'Declined',
};

/// What the filter sheet hands back.
typedef _Filters = ({_View view, _PayFilter pay, String? categoryId, ProposalStatus? status});

class _CampaignsBody extends StatefulWidget {
  const _CampaignsBody();

  @override
  State<_CampaignsBody> createState() => _CampaignsBodyState();
}

class _CampaignsBodyState extends State<_CampaignsBody> {
  _View _view = _View.explore;
  _PayFilter _pay = _PayFilter.all;
  String? _categoryId;
  ProposalStatus? _status;

  bool _searchOpen = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int get _activeFilters => switch (_view) {
    _View.explore => (_pay != _PayFilter.all ? 1 : 0) + (_categoryId != null ? 1 : 0),
    _View.applied => _status != null ? 1 : 0,
    _View.saved => 0,
  };

  void _setCategory(String? id) {
    if (id == _categoryId) return;
    setState(() => _categoryId = id);
    final repo = sl<CampaignRepository>();
    context.read<PagedCubit<Campaign>>().updateQuery((page) => repo.list(page: page, categoryId: id));
  }

  void _setView(_View view) {
    HapticFeedback.selectionClick();
    setState(() {
      _view = view;
      if (view != _View.explore) _closeSearch();
    });
  }

  void _closeSearch() {
    _searchOpen = false;
    _search.clear();
    _query = '';
    _searchFocus.unfocus();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_searchOpen) {
        _closeSearch();
      } else {
        _searchOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
      }
    });
  }

  Future<void> _openFilters() async {
    HapticFeedback.selectionClick();
    final categories = context.read<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    final counts = context.read<LoadCubit<ProposalsData>>().state.data?.$2;
    final savedCount = context.read<LoadCubit<List<Campaign>>>().state.data?.length;
    final result = await showAppSheet<_Filters>(
      context,
      builder: (_) => _FilterSheet(
        initial: (view: _view, pay: _pay, categoryId: _categoryId, status: _status),
        categories: categories,
        counts: counts,
        savedCount: savedCount,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.view != _View.explore) _closeSearch();
      _view = result.view;
      _pay = result.pay;
      _status = result.status;
    });
    _setCategory(result.categoryId);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    final categoryLabel = _categoryId == null ? null : categories.where((c) => c.id == _categoryId).map((c) => c.label).firstOrNull;

    final (title, subtitle) = switch (_view) {
      _View.explore => ('Campaigns', 'Work with brands and get paid for your content'),
      _View.applied => ('Applied', 'Proposals you’ve sent to brands'),
      _View.saved => ('Saved', 'Campaigns you kept for later'),
    };

    // Small removable chips for whatever is switched on — only when something is.
    final active = <Widget>[
      if (_view != _View.explore)
        _ActiveChip(label: _view == _View.applied ? 'Applied' : 'Saved', onRemove: () => _setView(_View.explore)),
      if (_view == _View.explore && _pay != _PayFilter.all)
        _ActiveChip(label: _payLabel(_pay), onRemove: () => setState(() => _pay = _PayFilter.all)),
      if (_view == _View.explore && categoryLabel != null) _ActiveChip(label: categoryLabel, onRemove: () => _setCategory(null)),
      if (_view == _View.applied && _status != null) _ActiveChip(label: _statusLabel(_status), onRemove: () => setState(() => _status = null)),
    ];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: title + two quiet icons (search, filter).
          Padding(
            padding: EdgeInsets.fromLTRB(_view == _View.explore ? AppSpacing.gutter : 6, 10, 10, 8),
            child: Row(
              children: [
                if (_view != _View.explore)
                  IconButton(
                    tooltip: 'Back to campaigns',
                    icon: Icon(AppIcons.back, size: 22, color: palette.textPrimary),
                    onPressed: () => _setView(_View.explore),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: palette.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_view == _View.explore) ...[
                  _HeaderIcon(icon: _searchOpen ? AppIcons.close : AppIcons.search, tooltip: _searchOpen ? 'Close search' : 'Search', onTap: _toggleSearch),
                  const SizedBox(width: 8),
                ],
                _HeaderIcon(icon: AppIcons.sliders, tooltip: 'Filter & lists', badge: _activeFilters, onTap: _openFilters),
              ],
            ),
          ),

          // Search — only when the search icon is tapped.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_searchOpen
                ? const SizedBox(width: double.infinity)
                : Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 2, AppSpacing.gutter, 10),
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
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
                  fillColor: palette.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.borderStrong, width: 1.4)),
                ),
              ),
            ),
          ),

          if (active.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: active),
            ),

          Expanded(
            child: IndexedStack(
              index: _view.index,
              children: [
                _ExploreTab(query: _query, pay: _pay, categoryId: _categoryId),
                _ProposalsTab(filter: _status),
                const _SavedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round, quiet header icon with an optional count badge.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

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
            color: palette.surface,
            shape: CircleBorder(side: BorderSide(color: palette.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 20, color: palette.textPrimary)),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -2,
              top: -2,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: palette.surface, width: 2),
                  ),
                  child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Paid ×" style chip under the header for a filter that's switched on.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onRemove();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
              const SizedBox(width: 4),
              Icon(AppIcons.close, size: 14, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything that used to sit on top of the list: which list to show,
/// paid / barter, category, proposal status.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.categories, required this.counts, required this.savedCount});

  final _Filters initial;
  final List<Category> categories;
  final ProposalCounts? counts;
  final int? savedCount;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _View _view = widget.initial.view;
  late _PayFilter _pay = widget.initial.pay;
  late String? _categoryId = widget.initial.categoryId;
  late ProposalStatus? _status = widget.initial.status;

  int? _statusCount(ProposalStatus? s) {
    final c = widget.counts;
    if (c == null) return null;
    return switch (s) {
      null => c.all,
      ProposalStatus.pending => c.pending,
      ProposalStatus.accepted => c.accepted,
      ProposalStatus.rejected => c.rejected,
    };
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _pay = _PayFilter.all;
      _categoryId = null;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 10),
      child: Text(text, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: palette.textPrimary)),
    );

    return SheetBody(
      title: 'Filter campaigns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Show'),
          _ViewOption(icon: AppIcons.campaigns, label: 'Explore', hint: 'Open campaigns to apply for', selected: _view == _View.explore, onTap: () => setState(() => _view = _View.explore)),
          const SizedBox(height: 8),
          _ViewOption(icon: AppIcons.paperPlane, label: 'Applied', hint: 'Proposals you’ve sent', count: widget.counts?.all, selected: _view == _View.applied, onTap: () => setState(() => _view = _View.applied)),
          const SizedBox(height: 8),
          _ViewOption(icon: AppIcons.bookmark, label: 'Saved', hint: 'Kept for later', count: widget.savedCount, selected: _view == _View.saved, onTap: () => setState(() => _view = _View.saved)),

          if (_view == _View.explore) ...[
            heading('Pay type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _PayFilter.values)
                  _FilterChip(
                    label: _payLabel(p),
                    icon: switch (p) { _PayFilter.all => AppIcons.sparkle, _PayFilter.paid => AppIcons.rupee, _PayFilter.barter => AppIcons.gift },
                    selected: _pay == p,
                    onTap: () => setState(() => _pay = p),
                  ),
              ],
            ),
            if (widget.categories.isNotEmpty) ...[
              heading('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(label: 'Any', selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
                  for (final c in widget.categories)
                    _FilterChip(label: c.label, selected: _categoryId == c.id, onTap: () => setState(() => _categoryId = _categoryId == c.id ? null : c.id)),
                ],
              ),
            ],
          ],

          if (_view == _View.applied) ...[
            heading('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in const [null, ProposalStatus.pending, ProposalStatus.accepted, ProposalStatus.rejected])
                  _FilterChip(
                    label: _statusCount(s) == null ? _statusLabel(s) : '${_statusLabel(s)} ${_statusCount(s)}',
                    selected: _status == s,
                    onTap: () => setState(() => _status = s),
                  ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: AppButton.secondary(label: 'Reset', onPressed: _reset)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Show results',
                  onPressed: () => Navigator.of(context).pop<_Filters>((view: _view, pay: _pay, categoryId: _categoryId, status: _status)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({required this.icon, required this.label, required this.hint, required this.selected, required this.onTap, this.count});

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfaceMuted : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? palette.textPrimary.withValues(alpha: 0.5) : palette.border, width: selected ? 1.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: palette.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(hint, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  ],
                ),
              ),
              if (count != null && count! > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(count! > 99 ? '99+' : '$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.textSecondary)),
                ),
              Icon(selected ? AppIcons.checkCircle : null, size: 20, color: palette.textPrimary),
            ],
          ),
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
      AppSnackbar.info(context, saved ? 'Saved — open Filter › Saved to see it' : 'Removed from saved');
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

/// Search, pay type and category now come from the header (search icon +
/// filter sheet), so the list starts right at the top.
class _ExploreTab extends StatelessWidget {
  const _ExploreTab({required this.query, required this.pay, required this.categoryId});

  final String query;
  final _PayFilter pay;
  final String? categoryId;

  bool _matches(Campaign c) {
    if (pay == _PayFilter.paid && !c.isPaid) return false;
    if (pay == _PayFilter.barter && c.isPaid) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return c.title.toLowerCase().contains(q) || (c.brand?.name.toLowerCase().contains(q) ?? false) || c.locationLabel.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final paged = context.watch<PagedCubit<Campaign>>();
    final state = paged.state;
    final savedIds = {for (final c in context.watch<LoadCubit<List<Campaign>>>().state.data ?? const <Campaign>[]) c.id};

    final visible = state.items.where(_matches).toList();
    final featured = visible.where((c) => c.isFeatured).toList();
    final filtering = query.isNotEmpty || pay != _PayFilter.all || categoryId != null;

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
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
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
    // Calm: selected = dark outline + soft grey fill (orange stays for the main button).
    final fg = selected ? palette.textPrimary : palette.textSecondary;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? palette.surfaceMuted : palette.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: selected ? palette.textPrimary.withValues(alpha: 0.55) : palette.border, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: fg)),
          ],
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
            // Clear outline so every campaign reads as its own card.
            border: Border.all(color: palette.borderStrong, width: 1.2),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 14, offset: Offset(0, 4))],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: context.palette.borderStrong, width: 1.2)),
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
              decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: palette.borderStrong, width: 1.2)),
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

/// Status filter comes from the header filter sheet.
class _ProposalsTab extends StatelessWidget {
  const _ProposalsTab({required this.filter});

  final ProposalStatus? filter;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<ProposalsData>>();

    return AsyncView<ProposalsData>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (data) {
        final (proposals, counts) = data;
        final visible = filter == null ? proposals : proposals.where((p) => p.status == filter).toList();

        return AppRefresh(
          onRefresh: cubit.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Summary strip
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, AppSpacing.md),
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
            border: Border.all(color: palette.borderStrong, width: 1.2),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0F101828), blurRadius: 12, offset: Offset(0, 4))],
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

class _SavedTab extends StatelessWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context) {
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