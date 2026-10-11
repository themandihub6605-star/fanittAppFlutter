import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/shop_repository.dart';
import 'shop_widgets.dart';

/// Seller: all physical products with stock and status.
class SellerProductsScreen extends StatelessWidget {
  const SellerProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<ShopProduct>>(() => ShopRepository.i.myProducts()),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<ShopProduct>>>();
          return Scaffold(
            appBar: AppBar(title: const Text('My shop products')),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _openEditor(context),
              icon: const Icon(AppIcons.plus),
              label: const Text('Add product', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            body: AsyncView<List<ShopProduct>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (items) => AppRefresh(
                onRefresh: cubit.refresh,
                child: items.isEmpty
                    ? ScrollableMessage(
                  child: MessageView(
                    icon: ShopIcons.bag,
                    iconColor: AppColors.primary,
                    title: 'Sell your first product',
                    message: 'T-shirts, hoodies, merch, art — add photos, a price and stock. Buyers pay online or Cash on Delivery.',
                    action: AppButton(label: 'Add product', icon: AppIcons.plus, expand: false, onPressed: () => _openEditor(context)),
                  ),
                )
                    : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _SellerProductTile(product: items[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _openEditor(BuildContext context, [String? id]) async {
    final saved = await context.push<bool>(AppRoutes.shopProductEditor(id));
    if (saved == true && context.mounted) context.read<LoadCubit<List<ShopProduct>>>().refresh();
  }
}

class _SellerProductTile extends StatefulWidget {
  const _SellerProductTile({required this.product});

  final ShopProduct product;

  @override
  State<_SellerProductTile> createState() => _SellerProductTileState();
}

class _SellerProductTileState extends State<_SellerProductTile> {
  bool _busy = false;

  Future<void> _run(Future<Object?> Function() task, String message) async {
    setState(() => _busy = true);
    try {
      final result = await task();
      if (!mounted) return;
      // Delete returns the server's own wording ("deleted" vs "hidden").
      AppSnackbar.success(context, result is String && result.isNotEmpty ? result : message);
      await context.read<LoadCubit<List<ShopProduct>>>().refresh();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(String action) async {
    final p = widget.product;
    final repo = ShopRepository.i;
    switch (action) {
      case 'edit':
        await SellerProductsScreen._openEditor(context, p.id);
      case 'view':
        await context.push(AppRoutes.shopProduct(p.id));
      case 'publish':
        await _run(() => repo.publish(p.id), 'Your product is live');
      case 'unpublish':
        await _run(() => repo.unpublish(p.id), 'Product hidden from buyers');
      case 'delete':
        final ok = await confirmAction(context, title: 'Delete this product?', message: 'Buyers will no longer see it. Past orders are not affected.', confirmLabel: 'Delete', destructive: true);
        if (ok && mounted) await _run(() => repo.deleteProduct(p.id), 'Product deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final palette = context.palette;
    final stock = p.totalStock ?? 0;
    final (statusText, statusColor) = switch (p.status) {
      'published' => ('Live', AppColors.success),
      'unpublished' => ('Hidden', AppColors.warning),
      'removed' => ('Removed', AppColors.error),
      _ => ('Draft', const Color(0xFF8A8FA0)),
    };
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy || p.isRemoved ? null : () => _menu('edit'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ShopThumb(url: p.imageUrl, size: 72),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                    const SizedBox(height: 3),
                    ShopPrice(price: p.price, mrp: p.mrp, size: 14),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          stock == 0 ? 'Out of stock' : '$stock in stock${p.hasVariants ? ' · ${p.variants.length} ${p.variantName.toLowerCase()}s' : ''}',
                          style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: stock == 0 ? AppColors.error : null, fontWeight: stock == 0 ? FontWeight.w700 : null),
                        ),
                        if (p.salesCount > 0) Text('· ${Fmt.compact(p.salesCount)} sold', style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
                      ],
                    ),
                    if (p.isRemoved && p.removedReason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(p.removedReason, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.error, fontSize: 11.5)),
                      ),
                  ],
                ),
              ),
              _busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : PopupMenuButton<String>(
                icon: Icon(AppIcons.dotsThree, color: palette.textSecondary),
                onSelected: (v) {
                  HapticFeedback.selectionClick();
                  _menu(v);
                },
                itemBuilder: (_) => [
                  if (!p.isRemoved) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'view', child: Text('Preview')),
                  if (!p.isRemoved && !p.isPublished) const PopupMenuItem(value: 'publish', child: Text('Publish')),
                  if (p.isPublished) const PopupMenuItem(value: 'unpublish', child: Text('Hide from buyers')),
                  if (!p.isRemoved) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}