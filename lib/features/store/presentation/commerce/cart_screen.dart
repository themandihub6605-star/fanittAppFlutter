import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';
import 'checkout_screen.dart';
import 'shop_widgets.dart';

/// The cart, grouped by store (each store ships its own parcel).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<Cart>(ShopRepository.i.cart),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<Cart>>();
          final cart = cubit.state.data;
          return Scaffold(
            appBar: AppBar(title: Text(cart == null || cart.count == 0 ? 'My cart' : 'My cart (${cart.count})')),
            body: AsyncView<Cart>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (cart) => cart.isEmpty ? const _EmptyCart() : _CartBody(cart: cart),
            ),
            bottomNavigationBar: cart == null || cart.isEmpty ? null : _CheckoutBar(cart: cart),
          );
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return MessageView(
      icon: ShopIcons.cart,
      iconColor: AppColors.primary,
      title: 'Your cart is empty',
      message: 'Find something you love in Fanitt Store.',
      action: AppButton(label: 'Start shopping', expand: false, onPressed: () => context.pushReplacement(AppRoutes.shop)),
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final s = cart.summary;
    final unavailable = cart.unavailable;
    return AppRefresh(
      onRefresh: context.read<LoadCubit<Cart>>().refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          for (final group in s.sellers) ...[
            ShopSection(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: group.store.slug.isEmpty ? null : () => context.push(AppRoutes.storePage(group.store.slug)),
                    child: Row(
                      children: [
                        StoreLogo(name: group.store.name, url: group.store.logoUrl, size: 24),
                        const SizedBox(width: 8),
                        Expanded(child: Text(group.store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                        Text(
                          group.deliveryCharge == 0 ? 'Free delivery' : 'Delivery ${Fmt.money(group.deliveryCharge)}',
                          style: context.text.bodySmall?.copyWith(color: group.deliveryCharge == 0 ? AppColors.success : null, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 18),
                  for (var i = 0; i < group.lines.length; i++) ...[
                    _CartLineRow(line: group.lines[i]),
                    if (i < group.lines.length - 1) const Divider(height: 18),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            ).animate().fadeIn(duration: 250.ms),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (unavailable.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Not available right now', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.error)),
            const SizedBox(height: AppSpacing.xs),
            ShopSection(
              child: Column(
                children: [
                  for (var i = 0; i < unavailable.length; i++) ...[
                    _CartLineRow(line: unavailable[i]),
                    if (i < unavailable.length - 1) const Divider(height: 18),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (s.sellers.isNotEmpty) ...[
            ShopSection(
              title: 'Price details',
              child: Column(
                children: [
                  PriceLine(label: 'Price (${s.itemCount} item${s.itemCount == 1 ? '' : 's'})', value: Fmt.money(s.mrpTotal)),
                  if (s.savings > 0) PriceLine(label: 'Discount', value: '− ${Fmt.money(s.savings)}', valueColor: AppColors.success),
                  PriceLine(label: 'Delivery', value: s.deliveryCharge == 0 ? 'FREE' : Fmt.money(s.deliveryCharge), valueColor: s.deliveryCharge == 0 ? AppColors.success : null),
                  const Divider(height: 18),
                  PriceLine(label: 'Total amount', value: Fmt.money(s.total), bold: true),
                  if (s.savings > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Text('You save ${Fmt.money(s.savings)} on this order', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(ShopIcons.shield, size: 16, color: context.palette.textTertiary),
                const SizedBox(width: 6),
                Expanded(child: Text('Safe payments · Cancel free before shipping', style: context.text.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CartLineRow extends StatefulWidget {
  const _CartLineRow({required this.line});

  final CartLine line;

  @override
  State<_CartLineRow> createState() => _CartLineRowState();
}

class _CartLineRowState extends State<_CartLineRow> {
  bool _busy = false;

  Future<void> _run(Future<Cart> Function() task) async {
    setState(() => _busy = true);
    try {
      final cart = await task();
      if (mounted) context.read<LoadCubit<Cart>>().replace(cart);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final palette = context.palette;
    return Opacity(
      opacity: l.available || l.problem.startsWith('Only') ? 1 : 0.6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(onTap: () => context.push(AppRoutes.shopProduct(l.productId)), child: ShopThumb(url: l.imageUrl, size: 76)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.25)),
                if (l.optionText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(l.optionText, style: context.text.bodySmall),
                ],
                const SizedBox(height: 4),
                if (l.price > 0) ShopPrice(price: l.price, mrp: l.mrp, size: 14.5),
                if (l.problem.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(l.problem, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (l.available || l.problem.startsWith('Only'))
                      QtyStepper(
                        compact: true,
                        value: l.qty,
                        max: (l.stock ?? 10).clamp(1, 10),
                        busy: _busy,
                        onChanged: (v) => _run(() => ShopRepository.i.setQty(l.id, v)),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _busy
                          ? null
                          : () {
                        HapticFeedback.selectionClick();
                        _run(() => ShopRepository.i.removeLine(l.id));
                      },
                      icon: Icon(AppIcons.trash, size: 20, color: palette.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final s = cart.summary;
    final blocked = cart.unavailable.isNotEmpty;
    return ShopBottomBar(
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.money(s.total), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(blocked ? 'Remove unavailable items to continue' : 'Total incl. delivery', style: context.text.bodySmall?.copyWith(color: blocked ? AppColors.error : null, fontSize: 11.5)),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: GradientButton(
              label: 'Checkout',
              onPressed: blocked || s.sellers.isEmpty
                  ? null
                  : () async {
                await context.push(AppRoutes.shopCheckout, extra: const CheckoutArgs());
                if (context.mounted) context.read<LoadCubit<Cart>>().refresh();
              },
            ),
          ),
        ],
      ),
    );
  }
}