import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/guards/profile_gate.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/media_picker.dart';
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
import '../../../chat/data/chat_models.dart';
import '../../../chat/data/chat_repository.dart';
import '../../../chat/presentation/chat_screen.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';
import '../../../reviews/presentation/review_sheet.dart';
import '../../../../core/services/share_service.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/campaign_widgets.dart';

class CreatorCampaignView {
  const CreatorCampaignView({
    required this.campaign,
    required this.isSaved,
    this.proposal,
    this.milestones = const [],
    this.conversation,
  });

  final Campaign campaign;
  final bool isSaved;
  final Proposal? proposal;
  final List<Milestone> milestones;
  final Conversation? conversation;

  bool get isHired =>
      proposal?.status == ProposalStatus.accepted && campaign.assignedCreatorId != null && campaign.assignedCreatorId == proposal!.creatorId;
}

Future<CreatorCampaignView> _loadView(String id) async {
  final repo = sl<CampaignRepository>();
  final results = await Future.wait<Object>([repo.byId(id), repo.myProposals(), repo.saved()]);
  final campaign = results[0] as Campaign;
  final (proposals, _) = results[1] as (List<Proposal>, ProposalCounts);
  final saved = results[2] as List<Campaign>;

  final proposal = proposals.where((p) => p.campaignId == id).firstOrNull;
  var view = CreatorCampaignView(campaign: campaign, isSaved: saved.any((c) => c.id == id), proposal: proposal);

  if (proposal != null) {
    final conversation = await sl<ChatRepository>().forApplication(proposal.id);
    final milestones = view.isHired ? await repo.milestones(id) : const <Milestone>[];
    view = CreatorCampaignView(
      campaign: campaign,
      isSaved: view.isSaved,
      proposal: proposal,
      milestones: milestones,
      conversation: conversation,
    );
  }
  return view;
}

class CampaignDetailScreen extends StatelessWidget {
  const CampaignDetailScreen({super.key, required this.campaignId});

  final String campaignId;

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<CreatorCampaignView>(() => _loadView(campaignId)),
        child: const _CampaignDetailView(),
      ),
    );
  }
}

class _CampaignDetailView extends StatelessWidget {
  const _CampaignDetailView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorCampaignView>>();
    final view = cubit.state.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign'),
        actions: [
          if (view != null)
            ShareIconButton(
              size: 44,
              message: () => ShareService.campaign(
                id: view.campaign.id,
                title: view.campaign.title,
                brand: view.campaign.brand?.name ?? 'A brand',
                isPaid: view.campaign.isPaid,
                pay: view.campaign.costPerInfluencer,
                location: view.campaign.locationLabel,
              ),
            ),
          if (view != null)
            BlocBuilder<ActionCubit, ActionState>(
              builder: (context, action) => IconButton(
                tooltip: view.isSaved ? 'Remove from saved' : 'Save',
                icon: Icon(view.isSaved ? AppIcons.bookmarkFilled : AppIcons.bookmark, color: view.isSaved ? AppColors.primary : null),
                onPressed: action.isBusy
                    ? null
                    : () async {
                  final saved = await context.read<ActionCubit>().run('save', () => sl<CampaignRepository>().toggleSave(view.campaign.id));
                  if (saved != null && context.mounted) {
                    HapticFeedback.lightImpact();
                    cubit.replace(CreatorCampaignView(
                      campaign: view.campaign,
                      isSaved: saved,
                      proposal: view.proposal,
                      milestones: view.milestones,
                      conversation: view.conversation,
                    ));
                  }
                },
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncView<CreatorCampaignView>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (view) => AppRefresh(
          onRefresh: cubit.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge * 2),
            children: [
              CampaignHeader(campaign: view.campaign).animate().fadeIn(duration: 300.ms),
              if (view.proposal != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _ProposalStatusCard(view: view),
              ],
              if (view.isHired && view.campaign.status == CampaignStatus.completed && view.campaign.brand?.userId != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppButton.secondary(
                  label: 'Review ${view.campaign.brand!.name}',
                  icon: AppIcons.star,
                  onPressed: () async {
                    final sent = await showReviewSheet(
                      context,
                      toUserId: view.campaign.brand!.userId!,
                      campaignId: view.campaign.id,
                      name: view.campaign.brand!.name,
                    );
                    if (sent && context.mounted) AppSnackbar.success(context, 'Thanks for your review');
                  },
                ),
              ],
              if (view.isHired) ...[
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Milestones'),
                if (view.milestones.isEmpty)
                  Text('Milestones appear once the brand sets up payment.', style: context.text.bodyMedium)
                else
                  for (final milestone in view.milestones) ...[
                    MilestoneTile(milestone: milestone, actions: _creatorActions(context, milestone)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
              const SizedBox(height: AppSpacing.lg),
              CampaignBrief(campaign: view.campaign).animate().fadeIn(delay: 120.ms, duration: 350.ms).slideY(begin: 0.04),
            ],
          ),
        ),
      ),
      bottomNavigationBar: view == null || view.proposal != null || view.campaign.status != CampaignStatus.open
          ? null
          : _ApplyBar(campaign: view.campaign),
    );
  }

  List<Widget> _creatorActions(BuildContext context, Milestone milestone) {
    final canSubmit = milestone.status == MilestoneStatus.funded || milestone.status == MilestoneStatus.changesRequested;
    if (!canSubmit) return const [];
    return [
      AppButton(
        label: milestone.status == MilestoneStatus.changesRequested ? 'Submit revision' : 'Submit work',
        icon: AppIcons.upload,
        expand: false,
        height: 44,
        onPressed: () => _openSubmitSheet(context, milestone),
      ),
    ];
  }

  Future<void> _openSubmitSheet(BuildContext context, Milestone milestone) async {
    final submitted = await showAppSheet<bool>(
      context,
      builder: (_) => SheetActionScope(child: _SubmitWorkSheet(milestone: milestone)),
    );
    if ((submitted ?? false) && context.mounted) {
      AppSnackbar.success(context, 'Work submitted to the brand');
      context.read<LoadCubit<CreatorCampaignView>>().refresh();
    }
  }
}

class _ProposalStatusCard extends StatelessWidget {
  const _ProposalStatusCard({required this.view});

  final CreatorCampaignView view;

  @override
  Widget build(BuildContext context) {
    final proposal = view.proposal!;
    final palette = context.palette;
    final message = switch (proposal.status) {
      ProposalStatus.pending => 'The brand is reviewing your proposal.',
      ProposalStatus.accepted => view.isHired
          ? 'You’re hired. Start each milestone once the brand funds it.'
          : 'Your proposal was accepted.',
      ProposalStatus.rejected => proposal.rejectionReason == null ? 'The brand went with someone else.' : 'Reason: ${proposal.rejectionReason}',
    };

    return AppCard(
      color: palette.primarySoft,
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Your proposal', style: context.text.titleSmall)),
              StatusChip(label: proposal.status.label, color: proposal.status.color),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
          if (proposal.quotedAmount != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Quoted ${Fmt.money(proposal.quotedAmount!)}', style: context.text.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),
          if (view.conversation != null)
            AppButton.secondary(
              label: 'Message brand',
              icon: AppIcons.messages,
              height: 46,
              onPressed: () => context.push(
                AppRoutes.chat(view.conversation!.id),
                extra: ChatArgs(title: view.campaign.brand?.name ?? 'Brand', avatarUrl: view.campaign.brand?.logoUrl),
              ),
            )
          else if (proposal.status != ProposalStatus.rejected)
            Row(
              children: [
                Icon(AppIcons.info, size: 16, color: palette.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text('You can chat once the brand replies to your proposal.', style: context.text.bodySmall)),
              ],
            ),
        ],
      ),
    );
  }
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.campaign});

  final Campaign campaign;

  Future<void> _apply(BuildContext context) async {
    if (!await ensureProfileComplete(context)) return;
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    final sent = await showAppSheet<bool>(
      context,
      builder: (_) => SheetActionScope(child: _ApplySheet(campaign: campaign)),
    );
    if ((sent ?? false) && context.mounted) {
      AppSnackbar.success(context, 'Proposal sent');
      context.read<LoadCubit<CreatorCampaignView>>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final spotsLeft = campaign.maxInfluencers > 0 ? (campaign.maxInfluencers - campaign.applicantCount).clamp(0, campaign.maxInfluencers) : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(campaign.payLabel, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [campaign.isPaid ? 'per creator' : 'products provided', if (spotsLeft != null) '$spotsLeft spots left'].join(' · '),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
                  child: InkWell(
                    onTap: () => _apply(context),
                    child: const SizedBox(
                      height: 52,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Apply now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                            SizedBox(width: 6),
                            Icon(AppIcons.arrowRightSimple, color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ).animate(onPlay: (c) => c.repeat()).shimmer(delay: 2200.ms, duration: 1100.ms, color: Colors.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplySheet extends StatefulWidget {
  const _ApplySheet({required this.campaign});

  final Campaign campaign;

  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends State<_ApplySheet> {
  final _formKey = GlobalKey<FormState>();
  final _pitch = TextEditingController();
  final _quote = TextEditingController();
  final _timeline = TextEditingController();
  final _links = [TextEditingController()];

  @override
  void dispose() {
    for (final c in [_pitch, _quote, _timeline, ..._links]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final links = _links.map((c) => c.text.trim()).where((l) => l.isNotEmpty).toList();
    final result = await context.read<ActionCubit>().run(
      'apply',
          () => sl<CampaignRepository>().apply(
        widget.campaign.id,
        pitch: _pitch.text.trim(),
        quotedAmount: Fmt.rupeesToPaise(_quote.text),
        portfolioLinks: links,
        deliveryTimeline: _timeline.text.trim(),
      ),
    );
    if (result != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusyWith('apply');
    return SheetBody(
      title: 'Send a proposal',
      subtitle: 'Tell ${widget.campaign.brand?.name ?? 'the brand'} why you’re a good fit.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Your pitch',
              hint: 'Your audience, past work and how you’d approach this',
              controller: _pitch,
              minLines: 4,
              maxLines: 8,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().length ?? 0) < 20 ? 'Write at least 20 characters' : null,
            ),
            if (widget.campaign.isPaid) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Your price (optional)',
                hint: 'Leave empty to accept ${widget.campaign.payLabel}',
                controller: _quote,
                prefixIcon: AppIcons.rupee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Delivery time (optional)', hint: 'e.g. 5 days', controller: _timeline, prefixIcon: AppIcons.clock),
            const SizedBox(height: AppSpacing.md),
            for (final (index, controller) in _links.indexed) ...[
              AppTextField(
                label: index == 0 ? 'Links to your work (optional)' : 'Another link',
                hint: 'https://',
                controller: controller,
                prefixIcon: AppIcons.link,
                keyboardType: TextInputType.url,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  final uri = Uri.tryParse(value);
                  return uri == null || !uri.hasScheme ? 'Enter a full link starting with https://' : null;
                },
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (_links.length < 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _links.add(TextEditingController())),
                  icon: const Icon(AppIcons.plus, size: 18),
                  label: const Text('Add another link'),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            const InlineActionError(),
            AppButton(label: 'Send proposal', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _SubmitWorkSheet extends StatefulWidget {
  const _SubmitWorkSheet({required this.milestone});

  final Milestone milestone;

  @override
  State<_SubmitWorkSheet> createState() => _SubmitWorkSheetState();
}

class _SubmitWorkSheetState extends State<_SubmitWorkSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _link = TextEditingController();
  List<PickedMedia> _files = const [];

  @override
  void dispose() {
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit(ActionCubit actions) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final link = _link.text.trim();
    final done = await actions.run('submit', () async {
      await sl<CampaignRepository>().submitMilestone(
        widget.milestone.id,
        description: _description.text.trim(),
        links: link.isEmpty ? const [] : [link],
        files: _files,
      );
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<ActionCubit>();
    return SheetBody(
      title: 'Submit ${widget.milestone.title}',
      subtitle: 'The brand reviews it and releases ${Fmt.money(widget.milestone.amount)} when approved.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'What you’re delivering',
              hint: 'Describe the work and anything the brand should check',
              controller: _description,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Describe the work' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Link (optional)',
              hint: 'Drive, Instagram post, etc.',
              controller: _link,
              prefixIcon: AppIcons.link,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: AppSpacing.md),
            AttachmentPicker(files: _files, onChanged: (files) => setState(() => _files = files)),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(
              label: 'Submit work',
              isLoading: actions.state.isBusyWith('submit'),
              onPressed: actions.state.isBusy ? null : () => _submit(actions),
            ),
          ],
        ),
      ),
    );
  }
}