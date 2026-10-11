import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/guards/profile_gate.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';
import 'checkout_screen.dart';
import 'shop_widgets.dart';

/// One physical product: photos, price, options (size / colour), delivery
/// info, Add to cart and Buy now.
class ShopProductScreen extends StatelessWidget {
  const ShopProductScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<ShopProductPage>(() => ShopRepository.i.productPage(productId)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<ShopProductPage>>();
          final page = cubit.state.data;
          if (page != null) return _ProductView(page: page);
          return Scaffold(
            appBar: AppBar(),
            body: AsyncView<ShopProductPage>(state: cubit.state, onRetry: cubit.load, builder: (_) => const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}

class _ProductView extends StatefulWidget {
  const _ProductView({required this.page});

  final ShopProductPage page;

  @override
  State<_ProductView> createState() => _ProductViewState();
}

class _ProductViewState extends State<_ProductView> {
  final _pager = PageController();
  int _photo = 0;
  String? _variantId;
  int _qty = 1;
  bool _adding = false;

  ShopProduct get p => widget.page.product;

  @override
  void initState() {
    super.initState();
    // Pre-select the only option, or the first one in stock.
    if (p.variants.length == 1 && p.variants.first.inStock) _variantId = p.variants.first.id;
    ShopRepository.i.refreshCartCount();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  ShopVariant? get _variant => p.variants.where((v) => v.id == _variantId).firstOrNull;

  int get _maxQty {
    final stock = p.hasVariants ? _variant?.stock : p.totalStock;
    return (stock ?? 10).clamp(1, 10);
  }

  bool _checkOption() {
    if (p.hasVariants && _variant == null) {
      HapticFeedback.heavyImpact();
      AppSnackbar.error(context, 'Choose a ${(p.variantName.isEmpty ? 'option' : p.variantName).toLowerCase()} first');
      return false;
    }
    return true;
  }

  Future<void> _addToCart() async {
    if (!_checkOption()) return;
    if (!await ensureProfileComplete(context) || !mounted) return;
    setState(() => _adding = true);
    try {
      await ShopRepository.i.addToCart(p.id, variantId: _variantId, qty: _qty);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Added to cart'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'VIEW CART', textColor: AppColors.sunrise, onPressed: () => context.push(AppRoutes.shopCart)),
          ),
        );
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _buyNow() async {
    if (!_checkOption()) return;
    if (!await ensureProfileComplete(context) || !mounted) return;
    context.push(AppRoutes.shopCheckout, extra: CheckoutArgs(productId: p.id, variantId: _variantId, qty: _qty));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final page = widget.page;
    final images = p.images.isEmpty ? [''] : p.images;
    final width = MediaQuery.sizeOf(context).width;
    final low = p.hasVariants ? (_variant?.stock != null && _variant!.stock! <= 5 && _variant!.stock! > 0 ? 'Only ${_variant!.stock} left' : null) : p.lowStockLabel;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: width,
            backgroundColor: palette.surface,
            foregroundColor: palette.textPrimary,
            actions: [if (!page.isOwner) const CartIconButton(), const SizedBox(width: 4)],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pager,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _photo = i),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: images[i].isEmpty ? null : () => _openGallery(context, images, i),
                      child: StoreImage(url: images[i], icon: ShopIcons.bag),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < images.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _photo ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(color: i == _photo ? AppColors.primary : Colors.black26, borderRadius: BorderRadius.circular(4)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.huge),
            sliver: SliverList.list(
              children: [
                if (page.isOwner && !p.isPublished)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Text(
                      p.isRemoved ? 'Removed by Fanitt: ${p.removedReason}' : 'Only you can see this — publish it to start selling.',
                      style: context.text.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700),
                    ),
                  ),
                Text(p.categoryLabel.toUpperCase(), style: context.text.labelSmall?.copyWith(color: AppColors.primary, letterSpacing: 0.8, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(p.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: AppSpacing.xs),
                ShopPrice(price: p.price, mrp: p.mrp, size: 22),
                const SizedBox(height: 2),
                Text('Inclusive of all taxes', style: context.text.bodySmall?.copyWith(fontSize: 11)),
                if (p.salesCount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(ShopIcons.bag, size: 15, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('${Fmt.compact(p.salesCount)} sold', style: context.text.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],

                // Options
                if (p.hasVariants) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Select ${p.variantName.isEmpty ? 'option' : p.variantName}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in p.variants)
                        _OptionChip(
                          label: v.label,
                          selected: v.id == _variantId,
                          enabled: v.inStock,
                          onTap: () => setState(() {
                            _variantId = v.id;
                            _qty = 1;
                          }),
                        ),
                    ],
                  ),
                ],
                if (low != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(low, style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ],
                if (p.inStock && !page.isOwner) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Text('Quantity', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      QtyStepper(value: _qty.clamp(1, _maxQty), max: _maxQty, onChanged: (v) => setState(() => _qty = v)),
                    ],
                  ),
                ],

                // Delivery
                const SizedBox(height: AppSpacing.lg),
                ShopSection(
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: ShopIcons.truck,
                        title: p.deliveryCharge == 0 ? 'Free delivery' : 'Delivery ${Fmt.money(p.deliveryCharge)}',
                        subtitle: p.deliveryDays.isEmpty ? 'Shipped by the seller' : 'Usually delivered in ${p.deliveryDays}',
                      ),
                      const Divider(height: 20),
                      _InfoRow(
                        icon: ShopIcons.cash,
                        title: p.codAvailable ? 'Cash on Delivery available' : 'Online payment only',
                        subtitle: p.codAvailable ? 'Pay when it arrives, or pay online' : 'UPI, cards and netbanking',
                      ),
                      const Divider(height: 20),
                      _InfoRow(
                        icon: ShopIcons.returnBox,
                        title: p.returnPolicy.isEmpty ? 'Cancel any time before it ships' : 'Returns',
                        subtitle: p.returnPolicy.isEmpty ? 'Full refund if you cancel before shipping' : p.returnPolicy,
                      ),
                    ],
                  ),
                ),

                // Highlights
                if (p.highlights.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Highlights', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.xs),
                  for (final h in p.highlights)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(padding: EdgeInsets.only(top: 3), child: Icon(AppIcons.checkCircle, size: 16, color: AppColors.success)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(h, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                        ],
                      ),
                    ),
                ],

                // Description
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('About this product', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.xs),
                  _ExpandableText(text: p.description),
                ],

                // Sold by
                const SizedBox(height: AppSpacing.lg),
                if (p.store.slug.isNotEmpty)
                  ShopSection(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: InkWell(
                      onTap: () => context.push(AppRoutes.storePage(p.store.slug)),
                      child: Row(
                        children: [
                          StoreLogo(name: p.store.name, url: p.store.logoUrl, size: 44),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Sold by', style: context.text.bodySmall?.copyWith(fontSize: 11)),
                                Text(p.store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                if (p.store.tagline.isNotEmpty) Text(p.store.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Text('Visit store ›', style: context.text.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),

                // More from this store
                if (page.moreFromStore.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(child: Text('More from ${p.store.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      TextButton(
                        onPressed: () => context.push(AppRoutes.shopBrowse(storeId: p.store.id, storeName: p.store.name)),
                        child: const Text('See all'),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 285,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: page.moreFromStore.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, i) => SizedBox(width: 158, child: ShopProductCard(product: page.moreFromStore[i], index: i, showStore: false)),
                    ),
                  ),
                ],
              ].animate(interval: 30.ms).fadeIn(duration: 260.ms),
            ),
          ),
        ],
      ),
      bottomNavigationBar: page.isOwner
          ? ShopBottomBar(
        child: GradientButton(
          label: 'Edit product',
          icon: AppIcons.pencil,
          onPressed: () async {
            await context.push(AppRoutes.shopProductEditor(p.id));
            if (context.mounted) context.read<LoadCubit<ShopProductPage>>().refresh();
          },
        ),
      )
          : ShopBottomBar(
        child: !p.inStock
            ? const SizedBox(height: 50, child: Center(child: Text('Out of stock', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.error, fontSize: 15))))
            : Row(
          children: [
            Expanded(child: OutlineShopButton(label: 'Add to cart', icon: ShopIcons.cart, isLoading: _adding, onPressed: _addToCart)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: GradientButton(label: 'Buy now', onPressed: _adding ? null : _buyNow)),
          ],
        ),
      ),
    );
  }

  void _openGallery(BuildContext context, List<String> images, int start) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _Gallery(images: images, start: start),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label, required this.selected, required this.enabled, required this.onTap});

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.1) : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: selected ? AppColors.primary : palette.border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: enabled
              ? () {
            HapticFeedback.selectionClick();
            onTap();
          }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 42),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? AppColors.primary : palette.textPrimary,
                    decoration: enabled ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 19, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

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
    final long = widget.text.length > 260;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Text(widget.text, style: style, maxLines: _open || !long ? null : 5, overflow: _open || !long ? null : TextOverflow.ellipsis),
        ),
        if (long)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }
}

/// Full-screen photos with pinch to zoom.
class _Gallery extends StatelessWidget {
  const _Gallery({required this.images, required this.start});

  final List<String> images;
  final int start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView.builder(
        controller: PageController(initialPage: start),
        itemCount: images.length,
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(child: StoreImage(url: images[i], fit: BoxFit.contain, icon: ShopIcons.bag)),
        ),
      ),
    );
  }
}