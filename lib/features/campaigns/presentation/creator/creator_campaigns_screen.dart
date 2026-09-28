import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/models/common_models.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../common/data/categories_repository.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';
import '../widgets/campaign_widgets.dart';

typedef ProposalsData = (List<Proposal>, ProposalCounts);

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
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Campaigns'),
            bottom: const _Tabs(),
          ),
          body: const TabBarView(children: [_ExploreTab(), _ProposalsTab(), _SavedTab()]),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget implements PreferredSizeWidget {
  const _Tabs();

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      labelColor: AppColors.primary,
      unselectedLabelColor: palette.textSecondary,
      labelStyle: context.text.labelLarge,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: palette.border,
      tabs: const [Tab(text: 'Explore'), Tab(text: 'My proposals'), Tab(text: 'Saved')],
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

class _ExploreTab extends StatefulWidget {
  const _ExploreTab();

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> with AutomaticKeepAliveClientMixin {
  String? _categoryId;

  @override
  bool get wantKeepAlive => true;

  void _selectCategory(String? id) {
    setState(() => _categoryId = id);
    final repo = sl<CampaignRepository>();
    context.read<PagedCubit<Campaign>>().updateQuery((page) => repo.list(page: page, categoryId: id));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];

    return Column(
      children: [
        if (categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
            child: ChoicePills<String?>(
              scrollable: true,
              options: [null, ...categories.map((c) => c.id)],
              selected: {_categoryId},
              labelOf: (id) => id == null ? 'All' : categories.firstWhere((c) => c.id == id).label,
              onChanged: _selectCategory,
            ),
          ),
        Expanded(
          child: PagedListView<Campaign>(
            cubit: context.read<PagedCubit<Campaign>>(),
            empty: const MessageView(
              icon: AppIcons.campaigns,
              title: 'No open campaigns right now',
              message: 'New campaigns from brands show up here. Pull down to check again.',
            ),
            itemBuilder: (context, campaign) => CampaignCard(campaign: campaign, onTap: () => openCampaign(context, campaign.id)),
          ),
        ),
      ],
    );
  }
}

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
        String label(ProposalStatus? s) => switch (s) {
              null => 'All ${counts.all}',
              ProposalStatus.pending => 'Pending ${counts.pending}',
              ProposalStatus.accepted => 'Accepted ${counts.accepted}',
              ProposalStatus.rejected => 'Declined ${counts.rejected}',
            };

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
              child: ChoicePills<ProposalStatus?>(
                scrollable: true,
                options: const [null, ProposalStatus.pending, ProposalStatus.accepted, ProposalStatus.rejected],
                selected: {_filter},
                labelOf: label,
                onChanged: (s) => setState(() => _filter = s),
              ),
            ),
            Expanded(
              child: AppRefresh(
                onRefresh: cubit.refresh,
                child: visible.isEmpty
                    ? const ScrollableMessage(
                        child: MessageView(
                          icon: AppIcons.paperPlane,
                          title: 'No proposals here',
                          message: 'Proposals you send to brands appear in this list.',
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _ProposalCard(proposal: visible[index]),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    final campaign = proposal.campaign;
    return AppCard(
      onTap: campaign == null ? null : () => openCampaign(context, campaign.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(campaign?.brand?.name ?? 'Campaign', style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
              ),
              StatusChip(label: proposal.status.label, color: proposal.status.color),
            ],
          ),
          const SizedBox(height: 2),
          Text(campaign?.title ?? 'This campaign is no longer available', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              if (proposal.quotedAmount != null) 'Your quote ${Fmt.money(proposal.quotedAmount!)}',
              if (proposal.createdAt != null) 'Sent ${Fmt.relative(proposal.createdAt!)}',
            ].join(' · '),
            style: context.text.bodySmall,
          ),
          if (proposal.status == ProposalStatus.rejected && proposal.rejectionReason != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Reason: ${proposal.rejectionReason}', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
          ],
        ],
      ),
    );
  }
}

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
                  message: 'Tap the bookmark on a campaign to keep it here for later.',
                ),
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
                itemCount: saved.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => CampaignCard(
                  campaign: saved[index],
                  onTap: () => openCampaign(context, saved[index].id),
                ),
              ),
      ),
    );
  }
}
