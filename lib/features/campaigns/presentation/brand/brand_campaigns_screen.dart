import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../dashboard/data/dashboard_repository.dart';
import '../../data/campaign_models.dart';
import '../widgets/campaign_widgets.dart';

enum _Filter { active, drafts, closed }

/// Opens a brand campaign: drafts go back into the editor, everything else
/// to the management screen.
Future<bool> openBrandCampaign(BuildContext context, Campaign campaign) async {
  final changed = campaign.status == CampaignStatus.draft
      ? await context.push<bool>(AppRoutes.campaignEditor(draftId: campaign.id))
      : await context.push<bool>(AppRoutes.manageCampaign(campaign.id));
  return changed ?? true;
}

class BrandCampaignsScreen extends StatelessWidget {
  const BrandCampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<BrandDashboard>(sl<DashboardRepository>().brand),
      child: const _BrandCampaignsView(),
    );
  }
}

class _BrandCampaignsView extends StatefulWidget {
  const _BrandCampaignsView();

  @override
  State<_BrandCampaignsView> createState() => _BrandCampaignsViewState();
}

class _BrandCampaignsViewState extends State<_BrandCampaignsView> {
  _Filter _filter = _Filter.active;

  bool _matches(Campaign c) => switch (_filter) {
        _Filter.active => c.status.isActive,
        _Filter.drafts => c.status == CampaignStatus.draft,
        _Filter.closed => !c.status.isActive && c.status != CampaignStatus.draft,
      };

  Future<void> _create() async {
    final created = await context.push<bool>(AppRoutes.campaignEditor());
    if ((created ?? false) && mounted) context.read<LoadCubit<BrandDashboard>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandDashboard>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Campaigns')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(AppIcons.plus),
        label: const Text('New campaign'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
            child: ChoicePills<_Filter>(
              scrollable: true,
              options: _Filter.values,
              selected: {_filter},
              labelOf: (f) => switch (f) { _Filter.active => 'Active', _Filter.drafts => 'Drafts', _Filter.closed => 'Closed' },
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
          Expanded(
            child: AsyncView<BrandDashboard>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (data) {
                final items = data.campaigns.where(_matches).toList();
                return AppRefresh(
                  onRefresh: cubit.refresh,
                  child: items.isEmpty
                      ? ScrollableMessage(
                          child: MessageView(
                            icon: AppIcons.campaigns,
                            title: switch (_filter) {
                              _Filter.active => 'No active campaigns',
                              _Filter.drafts => 'No drafts',
                              _Filter.closed => 'No closed campaigns',
                            },
                            message: 'Create a campaign to start receiving proposals from creators.',
                          ),
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) => CampaignCard(
                            campaign: items[index],
                            showStatus: true,
                            onTap: () async {
                              if (await openBrandCampaign(context, items[index]) && context.mounted) {
                                cubit.refresh();
                              }
                            },
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
