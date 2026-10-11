import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';

/// Icons used only by the shop screens.
abstract final class ShopIcons {
  static const IconData cart = PhosphorIconsRegular.shoppingCartSimple;
  static const IconData cartFilled = PhosphorIconsFill.shoppingCartSimple;
  static const IconData bag = PhosphorIconsRegular.shoppingBagOpen;
  static const IconData truck = PhosphorIconsRegular.truck;
  static const IconData tag = PhosphorIconsRegular.tag;
  static const IconData cash = PhosphorIconsRegular.money;
  static const IconData card = PhosphorIconsRegular.creditCard;
  static const IconData mapPin = PhosphorIconsRegular.mapPinLine;
  static const IconData orders = PhosphorIconsRegular.package;
  static const IconData returnBox = PhosphorIconsRegular.arrowUUpLeft;
  static const IconData shield = PhosphorIconsRegular.shieldCheck;
  static const IconData star = PhosphorIconsFill.star;
}

/// Brand gradient used on shop buttons and badges.
const shopGradient = LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Cart icon with a live item-count badge. Opens the cart.
class CartIconButton extends StatelessWidget {
  const CartIconButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ShopRepository.i.cartCount,
      builder: (context, count, _) => IconButton(
        tooltip: 'Cart',
        onPressed: () => context.push(AppRoutes.shopCart),
        icon: Badge(
          isLabelVisible: count > 0,
          backgroundColor: AppColors.primary,
          label: Text(count > 99 ? '99+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
          child: Icon(ShopIcons.cart, color: color),
        ),
      ),
    );
  }
}

/// ₹499  ₹799  37% off
class ShopPrice extends StatelessWidget {
  const ShopPrice({super.key, required this.price, required this.mrp, this.size = 15, this.showOff = true});

  final int price;
  final int mrp;
  final double size;
  final bool showOff;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hasMrp = mrp > price;
    final off = hasMrp ? (((mrp - price) / mrp) * 100).round() : 0;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(Fmt.money(price), style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: palette.textPrimary)),
        if (hasMrp)
          Text(
            Fmt.money(mrp),
            style: TextStyle(fontSize: size - 3, color: palette.textTertiary, decoration: TextDecoration.lineThrough, decorationColor: palette.textTertiary),
          ),
        if (hasMrp && showOff && off > 0) Text('$off% off', style: TextStyle(fontSize: size - 3, fontWeight: FontWeight.w800, color: AppColors.success)),
      ],
    );
  }
}

/// Grid card: square photo, title, price, store.
class ShopProductCard extends StatelessWidget {
  const ShopProductCard({super.key, required this.product, this.index = 0, this.showStore = true, this.onTap});

  final ShopProduct product;
  final int index;
  final bool showStore;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final palette = context.palette;
    final low = p.lowStockLabel;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ??
                () {
              HapticFeedback.selectionClick();
              context.push(AppRoutes.shopProduct(p.id));
            },
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(AppRadius.md)),
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
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(gradient: shopGradient, borderRadius: BorderRadius.circular(6)),
                          child: Text('${p.discountPercent}% OFF', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    if (!p.inStock)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.55),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(AppRadius.pill)),
                              child: const Text('Out of stock', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 13.5, height: 1.25, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      ShopPrice(price: p.price, mrp: p.mrp, size: 14.5),
                      const Spacer(),
                      if (low != null && p.inStock)
                        Text(low, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning))
                      else if (showStore && p.store.name.isNotEmpty)
                        Row(
                          children: [
                            StoreLogo(name: p.store.name, url: p.store.logoUrl, size: 16),
                            const SizedBox(width: 5),
                            Expanded(child: Text(p.store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11))),
                          ],
                        )
                      else
                        Text(p.deliveryCharge == 0 ? 'Free delivery' : '+ ${Fmt.money(p.deliveryCharge)} delivery', style: context.text.bodySmall?.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (40 * (index % 10)).ms).fadeIn(duration: 260.ms).slideY(begin: 0.04);
  }
}

/// Grid layout that fits [ShopProductCard] (square photo + 3 lines).
const shopGridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  mainAxisSpacing: AppSpacing.sm,
  crossAxisSpacing: AppSpacing.sm,
  childAspectRatio: 0.56,
);

/// – 2 + quantity picker.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 10, this.busy = false, this.compact = false});

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = compact ? 30.0 : 38.0;
    Widget button(IconData icon, int next, bool enabled) => SizedBox(
      width: size,
      height: size,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: compact ? 15 : 18,
        onPressed: enabled && !busy
            ? () {
          HapticFeedback.selectionClick();
          onChanged(next);
        }
            : null,
        icon: Icon(icon),
      ),
    );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(PhosphorIconsRegular.minus, value - 1, value > min),
          SizedBox(
            width: compact ? 26 : 32,
            child: Center(
              child: busy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('$value', style: TextStyle(fontWeight: FontWeight.w800, fontSize: compact ? 13 : 15, color: palette.textPrimary)),
            ),
          ),
          button(PhosphorIconsRegular.plus, value + 1, value < max),
        ],
      ),
    );
  }
}

/// Coloured pill for an order status.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final String status;

  static Color colorOf(String status) => switch (status) {
    'placed' => AppColors.info,
    'confirmed' => const Color(0xFF7C4DFF),
    'shipped' => AppColors.warning,
    'delivered' => AppColors.success,
    'cancelled' || 'payment_failed' => AppColors.error,
    _ => const Color(0xFF8A8FA0),
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(orderStatusLabel(status), style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }
}

/// Placed → Confirmed → Shipped → Delivered progress line.
class OrderProgress extends StatelessWidget {
  const OrderProgress({super.key, required this.order});

  final ShopOrder order;

  static const _steps = ['placed', 'confirmed', 'shipped', 'delivered'];

  DateTime? _when(String status) {
    for (final e in order.timeline.reversed) {
      if (e.status == status) return e.at;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (order.isCancelled) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(PhosphorIconsRegular.xCircle, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order cancelled', style: context.text.titleSmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w800)),
                  if (order.cancelReason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${switch (order.cancelledBy) { 'buyer' => 'By buyer', 'seller' => 'By seller', 'admin' => 'By Fanitt', _ => '' }}${order.cancelledBy.isEmpty ? '' : ': '}${order.cancelReason}',
                      style: context.text.bodySmall,
                    ),
                  ],
                  if (order.paymentStatus == 'refunded') ...[
                    const SizedBox(height: 4),
                    Text('Refund of ${Fmt.money(order.total)} started — it reaches the original payment method in 5–7 working days.', style: context.text.bodySmall?.copyWith(color: AppColors.success)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    final current = _steps.indexOf(order.status).clamp(0, _steps.length - 1);
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Column(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= current ? AppColors.success : palette.surfaceMuted,
                          border: Border.all(color: i <= current ? AppColors.success : palette.border, width: 2),
                        ),
                        child: i <= current ? const Icon(PhosphorIconsBold.check, size: 11, color: Colors.white) : null,
                      ),
                      if (i < _steps.length - 1)
                        Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: i < current ? AppColors.success : palette.border)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < _steps.length - 1 ? 18 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderStatusLabel(_steps[i]),
                          style: context.text.titleSmall?.copyWith(fontWeight: i == current ? FontWeight.w800 : FontWeight.w600, color: i <= current ? palette.textPrimary : palette.textTertiary),
                        ),
                        if (_when(_steps[i]) != null) Text(Fmt.weekdayDateTime(_when(_steps[i])!), style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
                        if (_steps[i] == 'shipped' && i <= current && (order.courier.isNotEmpty || order.trackingId.isNotEmpty))
                          Text(
                            [if (order.courier.isNotEmpty) order.courier, if (order.trackingId.isNotEmpty) 'Tracking ID ${order.trackingId}'].join(' · '),
                            style: context.text.bodySmall?.copyWith(fontSize: 11.5, color: palette.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small rounded card section with a title.
class ShopSection extends StatelessWidget {
  const ShopSection({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(AppSpacing.md)});

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// "Label ........ ₹value" row for price details.
class PriceLine extends StatelessWidget {
  const PriceLine({super.key, required this.label, required this.value, this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = bold
        ? context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: palette.textPrimary)
        : context.text.bodyMedium?.copyWith(color: palette.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style?.copyWith(color: valueColor ?? (bold ? palette.textPrimary : palette.textPrimary))),
        ],
      ),
    );
  }
}

/// Small product photo used in cart and order rows.
class ShopThumb extends StatelessWidget {
  const ShopThumb({super.key, required this.url, this.size = 72});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(width: size, height: size, child: StoreImage(url: url, icon: ShopIcons.bag)),
    );
  }
}

/// Bottom bar wrapper with a top border and safe-area padding.
class ShopBottomBar extends StatelessWidget {
  const ShopBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.sm), child: child),
      ),
    );
  }
}

/// Gradient primary button used for Buy now / Place order.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.isLoading = false, this.icon, this.height = 50});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Opacity(
      opacity: enabled || isLoading ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: shopGradient),
          child: InkWell(
            onTap: enabled
                ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
                : null,
            child: SizedBox(
              height: height,
              child: Center(
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined button matching [GradientButton]'s size (Add to cart).
class OutlineShopButton extends StatelessWidget {
  const OutlineShopButton({super.key, required this.label, required this.onPressed, this.icon, this.isLoading = false, this.height = 50});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        child: isLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ],
        ),
      ),
    );
  }
}