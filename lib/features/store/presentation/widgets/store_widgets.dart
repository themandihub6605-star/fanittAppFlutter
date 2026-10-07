import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/store_models.dart';

// Shared Fanitt Store widgets.

/// Bytes → "12.4 MB".
String fileSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Network image with a soft brand-gradient placeholder.
class StoreImage extends StatelessWidget {
  const StoreImage({super.key, required this.url, this.fit = BoxFit.cover, this.icon = AppIcons.store});

  final String url;
  final BoxFit fit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x55F4511E), Color(0x33EC2A78), Color(0x22101828)]),
      ),
      child: Center(child: Icon(icon, color: Colors.white.withValues(alpha: 0.45), size: 28)),
    );
    if (url.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

class StoreLogo extends StatelessWidget {
  const StoreLogo({super.key, required this.name, required this.url, this.size = 56, this.borderColor});

  final String name;
  final String url;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: radius, border: borderColor == null ? null : Border.all(color: borderColor!, width: 3)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3 - (borderColor == null ? 0 : 3)),
        child: url.isEmpty
            ? Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
                child: Text(
                  name.trim().isEmpty ? 'F' : name.trim()[0].toUpperCase(),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
                ),
              )
            : StoreImage(url: url),
      ),
    );
  }
}

class StoreStatusChip extends StatelessWidget {
  const StoreStatusChip({super.key, required this.status});

  final StoreStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StoreStatus.active => AppColors.success,
      StoreStatus.pendingReview => AppColors.warning,
      StoreStatus.rejected || StoreStatus.suspended => AppColors.error,
      StoreStatus.draft => context.palette.textSecondary,
    };
    return StatusChip(label: status.label, color: color);
  }
}

class ProductStatusChip extends StatelessWidget {
  const ProductStatusChip({super.key, required this.status});

  final ProductStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProductStatus.published => AppColors.success,
      ProductStatus.removed => AppColors.error,
      _ => context.palette.textSecondary,
    };
    return StatusChip(label: status.label, color: color);
  }
}

/// "₹499" / "Free" pill.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.price, this.owned = false});

  final int price;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final text = owned ? 'Owned' : (price == 0 ? 'Free' : Fmt.money(price));
    final color = owned ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(text, style: context.text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

/// Product tile used in store pages and the creator's product list.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.onTap, this.showStatus = false, this.index = 0});

  final DigitalProduct product;
  final VoidCallback onTap;
  final bool showStatus;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoreImage(url: product.coverUrl, icon: AppIcons.package),
                  Positioned(left: 8, top: 8, child: PriceTag(price: product.price, owned: product.owned)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${product.categoryLabel} · ${product.fileCount} file${product.fileCount == 1 ? '' : 's'}',
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showStatus) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ProductStatusChip(status: product.status),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (40 * index.clamp(0, 12)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }
}

/// Small stat box for store dashboards.
class StoreStat extends StatelessWidget {
  const StoreStat({super.key, required this.label, required this.value, required this.icon, this.color = AppColors.primary});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: context.text.titleLarge)),
          Text(label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}


/// Live or upcoming live card (store pages, fan home).
class LiveCard extends StatelessWidget {
  const LiveCard({super.key, required this.live, this.width = 220});

  final LiveStream live;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.liveDetail(live.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StoreImage(url: live.coverUrl, icon: AppIcons.broadcast),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: live.isLive ? AppColors.error : Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          live.isLive ? 'LIVE · ${live.viewers}' : (live.scheduledAt == null ? 'Soon' : Fmt.shortDate(live.scheduledAt!.toLocal())),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                      ),
                    ),
                    Positioned(right: 8, top: 8, child: PriceTag(price: live.price)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(live.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                    if (live.storeName != null) Text(live.storeName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
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
