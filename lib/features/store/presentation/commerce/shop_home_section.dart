import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';
import 'shop_widgets.dart';

/// Home: "Fanitt Store" — up to 5 popular products (swipe) and "See all" into the shop.
/// Hidden when no creator is selling anything yet.
class ShopHomeSection extends StatefulWidget {
  const ShopHomeSection({super.key, this.title = 'Fanitt Store', this.subtitle = 'Merch & products from creators — Cash on Delivery', this.refresh});

  final String title;
  final String subtitle;

  /// Fires when the home is pulled to refresh.
  final Listenable? refresh;

  @override
  State<ShopHomeSection> createState() => _ShopHomeSectionState();
}

class _ShopHomeSectionState extends State<ShopHomeSection> with AutomaticKeepAliveClientMixin {
  List<ShopProduct>? _items;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh?.addListener(_load);
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await ShopRepository.i.products(limit: 5, sort: 'popular');
      if (mounted) setState(() => _items = page.items);
    } catch (e) {
      debugPrint('ShopHomeSection: $e');
      if (mounted && _items == null) setState(() => _items = const []);
    }
    ShopRepository.i.refreshCartCount();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(AppRoutes.shop),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See all', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 2),
                        const Icon(AppIcons.chevronRight, size: 14, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Up to 5 products, swipe sideways. The row is as tall as the
          // tallest card — no fixed height, no gaps.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    SizedBox(width: 128, child: _MiniCard(product: items[i])),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Material(
              color: palette.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: palette.border)),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => context.push(AppRoutes.shop),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(ShopIcons.bag, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('Explore Fanitt Store', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card: square photo, title, price.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.product});

  final ShopProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.shopProduct(p.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StoreImage(url: p.imageUrl, icon: ShopIcons.bag),
                  if (p.discountPercent > 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(gradient: shopGradient, borderRadius: BorderRadius.circular(5)),
                        child: Text('${p.discountPercent}% OFF', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600, height: 1.25)),
                    const SizedBox(height: 4),
                    ShopPrice(price: p.price, mrp: p.mrp, size: 13.5, showOff: false),
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