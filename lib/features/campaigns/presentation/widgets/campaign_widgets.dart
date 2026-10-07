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
import '../../../content/data/content_repository.dart';
import '../../../feed/presentation/media_viewer_screen.dart';
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
/// A "brief ticket": brand on top, the offer as chips, a perforated tear
/// line, then applicants and spots.
class CampaignCard extends StatelessWidget {
  const CampaignCard({super.key, required this.campaign, required this.onTap, this.trailing, this.showStatus = false});

  final Campaign campaign;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = campaign;
    final spotsLeft = c.maxInfluencers > 0 ? (c.maxInfluencers - c.applicantCount).clamp(0, c.maxInfluencers) : null;

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppNetworkImage(url: c.campaignImageUrl ?? c.brand?.logoUrl, width: 64, height: 64, radius: 14, placeholderIcon: AppIcons.campaigns),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppNetworkImage(url: c.brand?.logoUrl, width: 18, height: 18, radius: 9, placeholderIcon: AppIcons.brand),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  c.brand?.name ?? c.category?.label ?? 'Brand',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.labelMedium?.copyWith(color: palette.textSecondary, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (c.isFeatured)
                                const _MiniBadge(label: 'Featured', color: AppColors.warning, icon: AppIcons.sparkle)
                              else if (c.isExclusive)
                                const _MiniBadge(label: 'Pro only', color: AppColors.info, icon: AppIcons.crown),
                              if (trailing != null) trailing!,
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _OfferChip(
                      icon: c.isPaid ? AppIcons.rupee : AppIcons.gift,
                      label: c.isPaid ? '${Fmt.money(c.costPerInfluencer)} / creator' : 'Barter',
                      color: c.isPaid ? AppColors.success : AppColors.warning,
                    ),
                    _OfferChip(icon: AppIcons.mapPin, label: c.locationLabel, color: palette.textSecondary),
                    if (!c.deliverables.isEmpty) _OfferChip(icon: AppIcons.videoCamera, label: c.deliverables.summary, color: AppColors.info),
                    if (showStatus) CampaignStatusChip(campaign: c),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 1, child: CustomPaint(painter: _DashLine(color: palette.border))),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(AppIcons.users, size: 14, color: palette.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ['${c.applicantCount} applied', if (spotsLeft != null) '$spotsLeft of ${c.maxInfluencers} spots left'].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ),
                    Text('View', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                    const Icon(AppIcons.chevronRight, size: 16, color: AppColors.primary),
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

class _OfferChip extends StatelessWidget {
  const _OfferChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DashLine extends CustomPainter {
  const _DashLine({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 14.0;
    while (x < size.width - 14) {
      canvas.drawLine(Offset(x, 0), Offset(x + 5, 0), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLine old) => old.color != color;
}

/// Everything a creator needs to decide: key facts as tiles, then neat
/// section cards (about, deliverables, who they want, do / don't, products,
/// references).
class CampaignBrief extends StatelessWidget {
  const CampaignBrief({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = campaign;
    final spots = c.maxInfluencers;

    Widget bullets(List<String> items, IconData icon, Color color) => Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 17, color: color)),
                const SizedBox(width: 10),
                Expanded(child: Text(item, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.4))),
              ],
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Key facts
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.15,
          children: [
            _FactTile(
              icon: c.isPaid ? AppIcons.rupee : AppIcons.gift,
              color: c.isPaid ? AppColors.success : AppColors.warning,
              value: c.isPaid ? Fmt.money(c.costPerInfluencer) : 'Barter',
              label: c.isPaid ? 'per creator' : 'products provided',
            ),
            _FactTile(icon: AppIcons.users, color: AppColors.info, value: '${c.applicantCount}${spots > 0 ? ' / $spots' : ''}', label: spots > 0 ? 'applied / spots' : 'applied'),
            _FactTile(icon: AppIcons.clock, color: const Color(0xFF7C4DFF), value: c.durationLabel.isEmpty ? 'Flexible' : c.durationLabel, label: 'duration'),
            _FactTile(icon: AppIcons.mapPin, color: AppColors.primary, value: c.locationLabel, label: 'location'),
          ],
        ),

        // Payment + audience
        _Section(
          icon: AppIcons.shieldCheck,
          title: 'Payment & audience',
          child: Column(
            children: [
              if (c.isPaid) _Line(label: 'Paid through', value: '${c.milestoneCount} milestone${c.milestoneCount == 1 ? '' : 's'} · escrow protected'),
              if (c.minFollowers != null && c.minFollowers! > 0) _Line(label: 'Minimum followers', value: Fmt.compact(c.minFollowers!)),
              _Line(label: 'Audience age', value: '${c.ageMin}–${c.ageMax}'),
              if (c.genderTarget.isNotEmpty) _Line(label: 'Audience gender', value: c.genderTarget.map(Fmt.titleCase).join(', ')),
              _Line(label: 'Creators needed', value: '$spots', last: true),
            ],
          ),
        ),

        if (c.description.isNotEmpty) _Section(icon: AppIcons.fileText, title: 'About the campaign', child: _ExpandableText(text: c.description)),

        if (!c.deliverables.isEmpty)
          _Section(
            icon: AppIcons.videoCamera,
            title: 'Deliverables per creator',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.deliverables.reel > 0) _CountTile(count: c.deliverables.reel, label: c.deliverables.reel == 1 ? 'Reel' : 'Reels', icon: AppIcons.video),
                if (c.deliverables.story > 0) _CountTile(count: c.deliverables.story, label: c.deliverables.story == 1 ? 'Story' : 'Stories', icon: AppIcons.broadcast),
                if (c.deliverables.post > 0) _CountTile(count: c.deliverables.post, label: c.deliverables.post == 1 ? 'Post' : 'Posts', icon: AppIcons.image),
              ],
            ),
          ),

        if (c.creatorRequirement.isNotEmpty || c.influencerCategories.isNotEmpty)
          _Section(
            icon: AppIcons.user,
            title: 'Who they’re looking for',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.creatorRequirement.isNotEmpty) Text(c.creatorRequirement, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.45)),
                if (c.creatorRequirement.isNotEmpty && c.influencerCategories.isNotEmpty) const SizedBox(height: 10),
                if (c.influencerCategories.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in c.influencerCategories)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(tag, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
              ],
            ),
          ),

        if (c.dos.isNotEmpty) _Section(icon: AppIcons.checkCircle, title: 'Do', tint: AppColors.success, child: bullets(c.dos, AppIcons.checkCircle, AppColors.success)),
        if (c.donts.isNotEmpty) _Section(icon: AppIcons.xCircle, title: 'Don’t', tint: AppColors.error, child: bullets(c.donts, AppIcons.xCircle, AppColors.error)),

        if (c.products.isNotEmpty)
          _Section(
            icon: AppIcons.gift,
            title: 'Products included',
            child: Column(
              children: [
                for (final (i, product) in c.products.indexed) ...[
                  if (i > 0) Divider(height: 20, color: palette.border),
                  Row(
                    children: [
                      AppNetworkImage(url: product.imageUrl, width: 52, height: 52, radius: 12, placeholderIcon: AppIcons.gift),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, style: context.text.titleSmall),
                            const SizedBox(height: 2),
                            Text('Qty ${product.quantity} · Worth ${Fmt.money(product.price)}', style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

        if (c.sampleMedia.isNotEmpty) _Section(icon: AppIcons.link, title: 'Reference', child: _ReferenceMedia(urls: c.sampleMedia)),
      ],
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.icon, required this.color, required this.value, required this.label});

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, maxLines: 1, style: context.text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child, this.tint});

  final IconData icon;
  final String title;
  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tint ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint == null ? palette.surface : tint!.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tint == null ? palette.border : tint!.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: context.text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: palette.border))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.count, required this.label, required this.icon});

  final int count;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Text('$count', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Text(label, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

/// Long text shown as 4 lines with "Read more".
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
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

/// Header: big cover with badges, the brand (tap to open) and the title.
class CampaignHeader extends StatelessWidget {
  const CampaignHeader({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final palette = context.palette;
    final image = c.campaignImageUrl;
    final canOpen = image != null && image.isNotEmpty;
    // Full-screen, pinch-to-zoom view of the campaign image.
    void openImage() => MediaViewerScreen.open(context, media: [PostMedia(url: image!, isVideo: false)], index: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: canOpen ? openImage : null,
                  child: AppNetworkImage(url: c.campaignImageUrl, placeholderIcon: AppIcons.campaigns),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x55000000), Color(0x00000000), Color(0xAA000000)], stops: [0, 0.4, 1]),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Row(
                    children: [
                      if (c.isFeatured) const _OnImageBadge(label: 'Featured', icon: AppIcons.sparkle),
                      if (c.isExclusive) const _OnImageBadge(label: 'Pro creators only', icon: AppIcons.crown),
                    ],
                  ),
                ),
                Positioned(right: 12, top: 12, child: CampaignStatusChip(campaign: c)),
                Positioned(
                  left: 14,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: c.isPaid ? const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]) : null,
                      color: c.isPaid ? null : Colors.black54,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      c.isPaid ? '${Fmt.money(c.costPerInfluencer)} per creator' : 'Barter collaboration',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
                if (canOpen)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: openImage,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.open_in_full_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (c.brand != null)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: c.brand!.slug.isEmpty ? null : () => context.push(AppRoutes.brandProfile(c.brand!.slug)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  AppNetworkImage(url: c.brand!.logoUrl, width: 40, height: 40, radius: 12, placeholderIcon: AppIcons.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.brand!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(c.category?.label ?? 'Brand', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Text('View brand', style: context.text.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  const Icon(AppIcons.chevronRight, size: 16, color: AppColors.primary),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(c.title, style: context.text.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(AppIcons.users, size: 15, color: palette.textTertiary),
            const SizedBox(width: 4),
            Text('${c.applicantCount} creators applied', style: context.text.bodySmall),
            if (c.createdAt != null) ...[
              Text('  ·  ', style: context.text.bodySmall),
              Text('Posted ${Fmt.relative(c.createdAt!)}', style: context.text.bodySmall),
            ],
          ],
        ),
        if (c.isPendingReview || c.isRejectedByReview) ...[
          const SizedBox(height: AppSpacing.md),
          CampaignReviewBanner(campaign: c),
        ],
      ],
    );
  }
}

class _OnImageBadge extends StatelessWidget {
  const _OnImageBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.sunrise),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Campaign status, or the admin-review state while it isn't public.
class CampaignStatusChip extends StatelessWidget {
  const CampaignStatusChip({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    if (campaign.isPendingReview) return const StatusChip(label: 'In review', color: AppColors.warning, icon: AppIcons.hourglass);
    if (campaign.isRejectedByReview) return const StatusChip(label: 'Not approved', color: AppColors.error, icon: AppIcons.xCircle);
    return StatusChip(label: campaign.status.label, color: campaign.status.color(context));
  }
}

/// Shown to the brand while a campaign waits for review or after rejection.
class CampaignReviewBanner extends StatelessWidget {
  const CampaignReviewBanner({super.key, required this.campaign});

  final Campaign campaign;

  @override
  Widget build(BuildContext context) {
    final pending = campaign.isPendingReview;
    final color = pending ? AppColors.warning : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(pending ? AppIcons.hourglass : AppIcons.xCircle, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending ? 'Waiting for review' : 'Not approved', style: context.text.titleSmall?.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(
                  pending
                      ? 'Our team is checking this campaign. It goes live for creators as soon as it’s approved — we’ll notify you.'
                      : [
                    if (campaign.rejectionReason.isNotEmpty) 'Reason: ${campaign.rejectionReason}.',
                    'Edit the draft and submit it again — your campaign slot has been returned.',
                  ].join(' '),
                  style: context.text.bodySmall?.copyWith(color: context.palette.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
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