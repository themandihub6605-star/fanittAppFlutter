import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/data/chat_repository.dart';
import '../../../chat/presentation/chat_screen.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';
import '../../../reviews/presentation/review_sheet.dart';
import '../../../../core/services/share_service.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/campaign_widgets.dart';

class ManageView {
  const ManageView({required this.campaign, required this.proposals, required this.milestones});

  final Campaign campaign;
  final List<Proposal> proposals;
  final List<Milestone> milestones;
}

Future<ManageView> _load(String id) async {
  final repo = sl<CampaignRepository>();
  final campaign = await repo.owned(id);
  final results = await Future.wait<Object>([
    repo.applications(id),
    if (campaign.assignedCreatorId != null) repo.milestones(id),
  ]);
  return ManageView(
    campaign: campaign,
    proposals: results[0] as List<Proposal>,
    milestones: results.length > 1 ? results[1] as List<Milestone> : const [],
  );
}

class CampaignManageScreen extends StatelessWidget {
  const CampaignManageScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<ManageView>(() => _load(campaignId)),
        child: const _ManageView(),
      ),
    );
  }
}

class _ManageView extends StatelessWidget {
  const _ManageView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<ManageView>>();
    final palette = context.palette;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage campaign'),
          actions: [
            if (cubit.state.data != null)
              ShareIconButton(
                size: 44,
                message: () {
                  final c = cubit.state.data!.campaign;
                  return ShareService.campaign(
                    id: c.id,
                    title: c.title,
                    brand: c.brand?.name ?? 'Our brand',
                    isPaid: c.isPaid,
                    pay: c.costPerInfluencer,
                    location: c.locationLabel,
                    mine: true,
                  );
                },
              ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: palette.textSecondary,
            labelStyle: context.text.labelLarge,
            indicatorColor: AppColors.primary,
            dividerColor: palette.border,
            tabs: [
              const Tab(text: 'Payments'),
              Tab(text: 'Proposals${cubit.state.data == null ? '' : ' ${cubit.state.data!.proposals.length}'}'),
              const Tab(text: 'Details'),
            ],
          ),
        ),
        body: AsyncView<ManageView>(
          state: cubit.state,
          onRetry: cubit.load,
          builder: (view) => TabBarView(
            children: [
              _PaymentsTab(view: view),
              _ProposalsTab(view: view),
              AppRefresh(
                onRefresh: cubit.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
                  children: [CampaignHeader(campaign: view.campaign), const SizedBox(height: AppSpacing.md), CampaignBrief(campaign: view.campaign)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Payments / milestones -----------------------------------------------------

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.view});

  final ManageView view;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LoadCubit<ManageView>>();
    final campaign = view.campaign;

    Widget body;
    if (campaign.assignedCreatorId == null) {
      body = MessageView(
        icon: AppIcons.handshake,
        title: 'No creator hired yet',
        message: view.proposals.isEmpty
            ? 'Proposals from creators will appear in the Proposals tab.'
            : 'Accept a proposal to set up escrow payments.',
      );
      return AppRefresh(onRefresh: cubit.refresh, child: ScrollableMessage(child: body));
    }
    if (!campaign.isPaid) {
      body = MessageView(
        icon: AppIcons.gift,
        title: 'Barter campaign',
        message: '${campaign.assignedCreatorName ?? 'Your creator'} receives the listed products. There are no payments to manage.',
      );
      return AppRefresh(onRefresh: cubit.refresh, child: ScrollableMessage(child: body));
    }

    final funded = view.milestones.where((m) => m.status != MilestoneStatus.pending).fold<int>(0, (s, m) => s + m.amount);
    final released = view.milestones.where((m) => m.status == MilestoneStatus.released).fold<int>(0, (s, m) => s + m.amount);

    return AppRefresh(
      onRefresh: cubit.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          AppCard(
            child: Column(
              children: [
                KeyValueRow(label: 'Creator', value: campaign.assignedCreatorName ?? 'Hired creator'),
                KeyValueRow(label: 'Deal value', value: Fmt.money(campaign.budget), emphasize: true),
                KeyValueRow(label: 'In escrow', value: Fmt.money(funded - released)),
                KeyValueRow(label: 'Released', value: Fmt.money(released)),
              ],
            ),
          ),
          if (campaign.status == CampaignStatus.completed) ...[
            const SizedBox(height: AppSpacing.md),
            _ReviewCreatorButton(view: view),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader(title: 'Milestones'),
          for (final milestone in view.milestones) ...[
            MilestoneTile(milestone: milestone, actions: _actions(context, milestone)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  bool _isUnlocked(Milestone milestone) {
    if (milestone.order == 1) return true;
    final previous = view.milestones.where((m) => m.order == milestone.order - 1).firstOrNull;
    return previous?.status == MilestoneStatus.released;
  }

  List<Widget> _actions(BuildContext context, Milestone milestone) {
    final actions = context.watch<ActionCubit>().state;
    final cubit = context.read<LoadCubit<ManageView>>();

    switch (milestone.status) {
      case MilestoneStatus.pending:
        if (!_isUnlocked(milestone)) {
          return [Text('Unlocks after the previous milestone is paid', style: context.text.bodySmall)];
        }
        return [
          AppButton(
            label: 'Fund ${Fmt.money(milestone.amount)}',
            icon: AppIcons.lock,
            expand: false,
            height: 44,
            isLoading: actions.isBusyWith('fund-${milestone.id}'),
            onPressed: actions.isBusy ? null : () => _fund(context, milestone),
          ),
        ];
      case MilestoneStatus.submitted:
        return [
          AppButton(
            label: 'Approve & release',
            icon: AppIcons.checkCircle,
            expand: false,
            height: 44,
            isLoading: actions.isBusyWith('approve-${milestone.id}'),
            onPressed: actions.isBusy ? null : () => _approve(context, milestone),
          ),
          AppButton.secondary(
            label: 'Request changes',
            expand: false,
            height: 44,
            onPressed: actions.isBusy
                ? null
                : () async {
              final done = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _FeedbackSheet(milestone: milestone, isDispute: false)));
              if ((done ?? false) && context.mounted) {
                AppSnackbar.success(context, 'Change request sent');
                cubit.refresh();
              }
            },
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: actions.isBusy
                ? null
                : () async {
              final done = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _FeedbackSheet(milestone: milestone, isDispute: true)));
              if ((done ?? false) && context.mounted) {
                AppSnackbar.success(context, 'Dispute raised. The Fanitt team will review it.');
                cubit.refresh();
              }
            },
            child: const Text('Raise dispute'),
          ),
        ];
      default:
        return const [];
    }
  }

  Future<void> _fund(BuildContext context, Milestone milestone) async {
    final repo = sl<CampaignRepository>();
    final auth = context.read<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final ok = await context.read<ActionCubit>().run(
      'fund-${milestone.id}',
          () async {
        final order = await repo.fundMilestone(milestone.id);
        final payment = await sl<PaymentService>().checkout(
          orderId: order.id,
          amount: order.amount,
          description: '${milestone.title} · ${view.campaign.title}',
          prefill: CheckoutPrefill(name: user?.name, email: user?.email, contact: user?.phone),
        );
        await repo.verifyMilestonePayment(
          milestone.id,
          orderId: payment.orderId ?? order.id,
          paymentId: payment.paymentId,
          signature: payment.signature,
        );
        return true;
      },
      success: 'Milestone funded. The creator can start work.',
    );
    if (ok != null && context.mounted) context.read<LoadCubit<ManageView>>().refresh();
  }

  Future<void> _approve(BuildContext context, Milestone milestone) async {
    final confirmed = await confirmAction(
      context,
      title: 'Release ${Fmt.money(milestone.amount)}?',
      message: 'The payment for “${milestone.title}” goes to the creator. This can’t be undone.',
      confirmLabel: 'Release payment',
    );
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<ActionCubit>().run(
      'approve-${milestone.id}',
          () async {
        await sl<CampaignRepository>().approveMilestone(milestone.id);
        return true;
      },
      success: 'Payment released',
    );
    if (ok != null && context.mounted) context.read<LoadCubit<ManageView>>().refresh();
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.milestone, required this.isDispute});

  final Milestone milestone;
  final bool isDispute;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  final _link = TextEditingController();
  List<PickedMedia> _files = const [];

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = sl<CampaignRepository>();
    final link = _link.text.trim();
    final ok = await context.read<ActionCubit>().run('send', () async {
      if (widget.isDispute) {
        await repo.raiseDispute(widget.milestone.id, reason: _text.text.trim(), files: _files);
      } else {
        await repo.requestChanges(
          widget.milestone.id,
          description: _text.text.trim(),
          links: link.isEmpty ? const [] : [link],
          files: _files,
        );
      }
      return true;
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: widget.isDispute ? 'Raise a dispute' : 'Request changes',
      subtitle: widget.isDispute
          ? 'Payment stays in escrow while the Fanitt team reviews both sides.'
          : 'The creator revises and resubmits. No money moves.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: widget.isDispute ? 'What went wrong?' : 'What should change?',
              controller: _text,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Add some details' : null,
            ),
            if (!widget.isDispute) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'Reference link (optional)', hint: 'https://', controller: _link, prefixIcon: AppIcons.link, keyboardType: TextInputType.url),
            ],
            const SizedBox(height: AppSpacing.md),
            AttachmentPicker(
              label: widget.isDispute ? 'Evidence (optional)' : 'Files (optional)',
              files: _files,
              onChanged: (f) => setState(() => _files = f),
            ),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(
              label: widget.isDispute ? 'Raise dispute' : 'Send request',
              variant: widget.isDispute ? AppButtonVariant.danger : AppButtonVariant.primary,
              isLoading: busy,
              onPressed: busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Proposals -------------------------------------------------------------------

class _ProposalsTab extends StatelessWidget {
  const _ProposalsTab({required this.view});

  final ManageView view;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LoadCubit<ManageView>>();
    return AppRefresh(
      onRefresh: cubit.refresh,
      child: view.proposals.isEmpty
          ? const ScrollableMessage(
        child: MessageView(
          icon: AppIcons.paperPlane,
          title: 'No proposals yet',
          message: 'Creators who apply to this campaign show up here.',
        ),
      )
          : ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
        itemCount: view.proposals.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => _ProposalCard(proposal: view.proposals[index], campaign: view.campaign),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.campaign});

  final Proposal proposal;
  final Campaign campaign;

  Future<void> _message(BuildContext context) async {
    final conversation = await context.read<ActionCubit>().run(
      'chat-${proposal.id}',
          () => sl<ChatRepository>().startForApplication(proposal.id),
    );
    if (conversation != null && context.mounted) {
      context.push(
        AppRoutes.chat(conversation.id),
        extra: ChatArgs(title: proposal.creator?.name ?? 'Creator', avatarUrl: proposal.creator?.avatarUrl),
      );
    }
  }

  Future<void> _accept(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Hire ${proposal.creator?.name ?? 'this creator'}?',
      message: campaign.isPaid
          ? 'The deal is split into ${campaign.milestoneCount} milestone${campaign.milestoneCount == 1 ? '' : 's'}. '
          'You’ll fund the first one into escrow before work starts.'
          : 'They’ll be assigned to this campaign.',
      confirmLabel: 'Hire',
    );
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<ActionCubit>().run(
      'decide-${proposal.id}',
          () async {
        await sl<CampaignRepository>().decide(campaign.id, proposal.id, accept: true);
        return true;
      },
      success: 'Creator hired',
    );
    if (ok != null && context.mounted) {
      final cubit = context.read<LoadCubit<ManageView>>();
      await cubit.refresh();
      if (context.mounted) DefaultTabController.of(context).animateTo(0);
    }
  }

  Future<void> _decline(BuildContext context) async {
    final reason = await showAppSheet<String>(context, builder: (_) => const _DeclineSheet());
    if (reason == null || !context.mounted) return;
    final ok = await context.read<ActionCubit>().run(
      'decide-${proposal.id}',
          () async {
        await sl<CampaignRepository>().decide(campaign.id, proposal.id, accept: false, reason: reason);
        return true;
      },
      success: 'Proposal declined',
    );
    if (ok != null && context.mounted) context.read<LoadCubit<ManageView>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final creator = proposal.creator;
    final actions = context.watch<ActionCubit>().state;
    final canDecide = proposal.status == ProposalStatus.pending && campaign.assignedCreatorId == null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: creator == null || creator.slug.isEmpty ? null : () => context.push(AppRoutes.creatorProfile(creator.slug)),
            child: Row(
              children: [
                UserAvatar(initials: creator?.initials ?? '?', imageUrl: creator?.avatarUrl, size: 44),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(creator?.name ?? 'Creator', style: context.text.titleSmall),
                      Text(
                        [if (creator != null && creator.title.isNotEmpty) creator.title, if (proposal.createdAt != null) Fmt.relative(proposal.createdAt!)].join(' · '),
                        style: context.text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                StatusChip(label: proposal.status.label, color: proposal.status.color),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(proposal.pitch, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            children: [
              Text('Quote: ${proposal.quotedAmount == null ? campaign.payLabel : Fmt.money(proposal.quotedAmount!)}', style: context.text.labelMedium),
              if (proposal.deliveryTimeline.isNotEmpty) Text('Delivery: ${proposal.deliveryTimeline}', style: context.text.labelMedium),
            ],
          ),
          for (final link in proposal.portfolioLinks) LinkText(url: link),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (canDecide)
                AppButton(
                  label: 'Hire',
                  expand: false,
                  height: 42,
                  isLoading: actions.isBusyWith('decide-${proposal.id}'),
                  onPressed: actions.isBusy ? null : () => _accept(context),
                ),
              AppButton.secondary(
                label: 'Message',
                icon: AppIcons.messages,
                expand: false,
                height: 42,
                isLoading: actions.isBusyWith('chat-${proposal.id}'),
                onPressed: actions.isBusy ? null : () => _message(context),
              ),
              if (canDecide)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  onPressed: actions.isBusy ? null : () => _decline(context),
                  child: const Text('Decline'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet();

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  final _reason = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Decline proposal',
      subtitle: 'The creator sees this reason.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Reason',
              hint: 'e.g. We’re looking for creators based in Mumbai',
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Add a short reason' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Decline',
              variant: AppButtonVariant.danger,
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) Navigator.of(context).pop(_reason.text.trim());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCreatorButton extends StatelessWidget {
  const _ReviewCreatorButton({required this.view});

  final ManageView view;

  @override
  Widget build(BuildContext context) {
    final hired = view.proposals.where((p) => p.status == ProposalStatus.accepted && p.creatorId == view.campaign.assignedCreatorId).firstOrNull;
    final creator = hired?.creator;
    if (creator == null || creator.userId.isEmpty) return const SizedBox.shrink();
    return AppButton.secondary(
      label: 'Review ${creator.name}',
      icon: AppIcons.star,
      onPressed: () async {
        final sent = await showReviewSheet(context, toUserId: creator.userId, campaignId: view.campaign.id, name: creator.name);
        if (sent && context.mounted) AppSnackbar.success(context, 'Thanks for your review');
      },
    );
  }
}