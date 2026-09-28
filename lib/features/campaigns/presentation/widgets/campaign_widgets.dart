import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/campaign_models.dart';

extension CampaignStatusColor on CampaignStatus {
  Color color(BuildContext context) => switch (this) {
    CampaignStatus.open => AppColors.success,
    CampaignStatus.inProgress || CampaignStatus.submitted => AppColors.info,
    CampaignStatus.disputed => AppColors.error,
    CampaignStatus.completed || CampaignStatus.approved => AppColors.primary,
    _ => context.palette.textSecondary,
  };
}

extension ProposalStatusColor on ProposalStatus {
  Color get color => switch (this) {
    ProposalStatus.accepted => AppColors.success,
    ProposalStatus.rejected => AppColors.error,
    ProposalStatus.pending => AppColors.warning,
  };
}

extension MilestoneStatusColor on MilestoneStatus {
  Color color(BuildContext context) => switch (this) {
    MilestoneStatus.released => AppColors.success,
    MilestoneStatus.funded => AppColors.info,
    MilestoneStatus.submitted => AppColors.primary,
    MilestoneStatus.changesRequested => AppColors.warning,
    MilestoneStatus.disputed => AppColors.error,
    MilestoneStatus.pending => context.palette.textSecondary,
  };
}

/// List card for a campaign — used in discovery, saved and brand lists.
class CampaignCard extends StatelessWidget {
  const CampaignCard({super.key, required this.campaign, required this.onTap, this.trailing, this.showStatus = false});

  final Campaign campaign;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppNetworkImage(url: campaign.campaignImageUrl, width: 84, height: 84, radius: AppRadius.md, placeholderIcon: AppIcons.campaigns),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          campaign.brand?.name ?? campaign.category?.label ?? '',
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (campaign.isFeatured) const StatusChip(label: 'Featured', color: AppColors.primary),
                      if (campaign.isExclusive && !campaign.isFeatured) const StatusChip(label: 'Exclusive', color: AppColors.info),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(campaign.title, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Meta(icon: campaign.isPaid ? AppIcons.wallet : AppIcons.gift, text: campaign.payLabel, strong: true),
                      _Meta(icon: AppIcons.mapPin, text: campaign.locationLabel),
                      _Meta(icon: AppIcons.users, text: '${campaign.applicantCount} applied'),
                      if (showStatus) StatusChip(label: campaign.status.label, color: campaign.status.color(context)),
                    ],
                  ),
                  if (!campaign.deliverables.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(campaign.deliverables.summary, style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.strong = false});

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: strong ? AppColors.primary : palette.textTertiary),
        const SizedBox(width: 4),
        Text(
          text,
          style: strong
              ? context.text.labelMedium?.copyWith(color: palette.textPrimary)
              : context.text.bodySmall,
        ),
      ],
    );
  }
}

/// Everything a creator needs to know about a campaign's brief.
class CampaignBrief extends StatelessWidget {
  const CampaignBrief({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = campaign;

    Widget block(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title, style: context.text.titleMedium), const SizedBox(height: AppSpacing.xs), child],
      ),
    );

    Widget bullets(List<String> items, IconData icon, Color color) => Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(item, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
              ],
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            children: [
              KeyValueRow(label: c.isPaid ? 'Pay per creator' : 'Campaign type', value: c.payLabel, emphasize: true),
              if (c.isPaid) KeyValueRow(label: 'Paid in', value: '${c.milestoneCount} milestone${c.milestoneCount == 1 ? '' : 's'} via escrow'),
              KeyValueRow(label: 'Creators needed', value: '${c.maxInfluencers}'),
              KeyValueRow(label: 'Location', value: c.locationLabel),
              if (c.durationLabel.isNotEmpty) KeyValueRow(label: 'Duration', value: c.durationLabel),
              if (c.minFollowers != null && c.minFollowers! > 0) KeyValueRow(label: 'Minimum followers', value: Fmt.compact(c.minFollowers!)),
              KeyValueRow(label: 'Audience age', value: '${c.ageMin}–${c.ageMax}'),
              if (c.genderTarget.isNotEmpty) KeyValueRow(label: 'Audience gender', value: c.genderTarget.map(Fmt.titleCase).join(', ')),
            ],
          ),
        ),
        if (c.description.isNotEmpty) block('About the campaign', Text(c.description, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
        if (!c.deliverables.isEmpty) block('Deliverables per creator', Text(c.deliverables.summary, style: context.text.titleSmall)),
        if (c.creatorRequirement.isNotEmpty) block('Who they’re looking for', Text(c.creatorRequirement, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
        if (c.influencerCategories.isNotEmpty)
          block(
            'Creator categories',
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [for (final tag in c.influencerCategories) StatusChip(label: tag, color: palette.textSecondary)],
            ),
          ),
        if (c.dos.isNotEmpty) block('Do', bullets(c.dos, AppIcons.checkCircle, AppColors.success)),
        if (c.donts.isNotEmpty) block('Don’t', bullets(c.donts, AppIcons.xCircle, AppColors.error)),
        if (c.products.isNotEmpty)
          block(
            'Products included',
            Column(
              children: [
                for (final product in c.products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        children: [
                          AppNetworkImage(url: product.imageUrl, width: 52, height: 52, radius: AppRadius.sm, placeholderIcon: AppIcons.gift),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(product.name, style: context.text.titleSmall),
                                Text('Qty ${product.quantity} · Worth ${Fmt.money(product.price)}', style: context.text.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (c.sampleMedia.isNotEmpty) block('Reference', _ReferenceMedia(urls: c.sampleMedia)),
      ],
    );
  }
}

/// Brand reference material. New campaigns store links (Instagram, YouTube…),
/// older ones may hold uploaded images or videos — each is shown the right way.
class _ReferenceMedia extends StatelessWidget {
  const _ReferenceMedia({required this.urls});

  final List<String> urls;

  static bool _isUploadedVideo(String url) =>
      url.contains('.m3u8') || url.contains('videodelivery') || url.contains('cloudflarestream');

  static bool _isImage(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png') || path.endsWith('.webp') || path.endsWith('.gif');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final media = urls.where((u) => _isImage(u) || _isUploadedVideo(u)).toList();
    final links = urls.where((u) => !_isImage(u) && !_isUploadedVideo(u)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: media.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (_, i) => _isUploadedVideo(media[i])
                  ? Container(
                width: 96,
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(AppIcons.video, color: palette.textSecondary),
              )
                  : AppNetworkImage(url: media[i], width: 96, height: 96, radius: AppRadius.sm),
            ),
          ),
        if (media.isNotEmpty && links.isNotEmpty) const SizedBox(height: AppSpacing.sm),
        for (final link in links)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
              child: LinkText(url: link, fullUrl: true),
            ),
          ),
      ],
    );
  }
}

/// Header with the cover image, brand and title.
class CampaignHeader extends StatelessWidget {
  const CampaignHeader({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: AppNetworkImage(url: campaign.campaignImageUrl, radius: AppRadius.lg, placeholderIcon: AppIcons.campaigns),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (campaign.brand != null) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: campaign.brand!.slug.isEmpty ? null : () => context.push(AppRoutes.brandProfile(campaign.brand!.slug)),
                  child: Row(
                    children: [
                      AppNetworkImage(url: campaign.brand!.logoUrl, width: 28, height: 28, radius: 14, placeholderIcon: AppIcons.brand),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(child: Text(campaign.brand!.name, style: context.text.labelMedium, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            StatusChip(label: campaign.status.label, color: campaign.status.color(context)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(campaign.title, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (campaign.category != null && campaign.category!.label.isNotEmpty)
              StatusChip(label: campaign.category!.label, color: context.palette.textSecondary),
            StatusChip(label: '${campaign.applicantCount} applied', color: context.palette.textSecondary, icon: AppIcons.users),
            if (campaign.isExclusive) const StatusChip(label: 'Pro creators only', color: AppColors.info, icon: AppIcons.crown),
          ],
        ),
      ],
    );
  }
}

class MilestoneTile extends StatelessWidget {
  const MilestoneTile({super.key, required this.milestone, this.actions = const []});

  final Milestone milestone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = milestone;
    final statusColor = m.status.color(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: m.status == MilestoneStatus.released
                    ? Icon(AppIcons.check, size: 16, color: statusColor)
                    : Text('${m.order}', style: context.text.labelMedium?.copyWith(color: statusColor)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title, style: context.text.titleSmall),
                    Text(m.status.label, style: context.text.bodySmall?.copyWith(color: statusColor)),
                  ],
                ),
              ),
              Text(Fmt.money(m.amount), style: context.text.titleMedium),
            ],
          ),
          if (m.submissionDescription.isNotEmpty || m.submissionLinks.isNotEmpty || m.submissionAttachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Note(
              title: 'Submitted work${m.submittedAt == null ? '' : ' · ${Fmt.dateTime(m.submittedAt!)}'}',
              body: m.submissionDescription,
              links: [...m.submissionLinks, ...m.submissionAttachments.map((a) => a.url)],
            ),
          ],
          if (m.status == MilestoneStatus.changesRequested && m.changeDescription.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Note(
              title: 'Changes requested',
              body: m.changeDescription,
              links: [...m.changeReferenceLinks, ...m.changeAttachments.map((a) => a.url)],
              color: AppColors.warning,
            ),
          ],
          if (m.status == MilestoneStatus.submitted && m.autoReleaseAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Releases automatically on ${Fmt.date(m.autoReleaseAt!)} if not reviewed.',
              style: context.text.bodySmall?.copyWith(color: palette.textTertiary),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: actions),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body, required this.links, this.color});

  final String title;
  final String body;
  final List<String> links;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: (color ?? palette.textSecondary).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.labelSmall?.copyWith(color: color ?? palette.textSecondary)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
          ],
          for (final link in links) LinkText(url: link),
        ],
      ),
    );
  }
}

class LinkText extends StatelessWidget {
  const LinkText({super.key, required this.url, this.fullUrl = false});

  final String url;

  /// Show the whole link (host + path) instead of just the file name.
  final bool fullUrl;

  Future<void> _open(BuildContext context) async {
    try {
      await LinkOpener.open(url);
    } on ApiException catch (error) {
      if (context.mounted) AppSnackbar.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final label = fullUrl
        ? '${uri?.host.replaceFirst('www.', '') ?? ''}${uri?.path ?? ''}'
        : (uri?.pathSegments.lastOrNull ?? url);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => _open(context),
        child: Row(
          children: [
            const Icon(AppIcons.link, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label.isEmpty ? url : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}