import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/shop_repository.dart';
import 'shop_widgets.dart';

class OrderPlacedArgs {
  const OrderPlacedArgs({required this.orders, required this.method});

  final List<ShopOrder> orders;
  final String method;
}

/// "Order placed" — shown right after checkout.
class OrderPlacedScreen extends StatelessWidget {
  const OrderPlacedScreen({super.key, required this.args});

  final OrderPlacedArgs args;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final orders = args.orders;
    final total = orders.fold<int>(0, (s, o) => s + o.total);
    final cod = args.method == 'cod';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xxl, AppSpacing.gutter, AppSpacing.xl),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF12A150), Color(0xFF34D399)])),
                child: const Icon(AppIcons.check, color: Colors.white, size: 52),
              ).animate().scale(begin: const Offset(0.3, 0.3), duration: 500.ms, curve: Curves.easeOutBack),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Order placed!', textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 6),
            Text(
              cod ? 'Keep ${Fmt.money(total)} ready — pay in cash or UPI when it arrives.' : 'Payment of ${Fmt.money(total)} received. The seller will ship it soon.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: AppSpacing.xl),
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ShopSection(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: InkWell(
                    onTap: () => context.pushReplacement(AppRoutes.shopOrder(o.id)),
                    child: Row(
                      children: [
                        ShopThumb(url: o.firstImage, size: 56),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              Text('Order ${o.orderNumber}${o.store.name.isEmpty ? '' : ' · ${o.store.name}'}', style: context.text.bodySmall),
                            ],
                          ),
                        ),
                        Text(Fmt.money(o.total), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
            if (orders.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                  children: [
                    const Icon(ShopIcons.mapPin, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Delivering to ${orders.first.address.name}, ${orders.first.address.city} - ${orders.first.address.pincode}', style: context.text.bodySmall)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'View my orders',
              icon: ShopIcons.orders,
              onPressed: () => context.pushReplacement(AppRoutes.shopOrders),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton.secondary(label: 'Continue shopping', onPressed: () => context.pushReplacement(AppRoutes.shop)),
          ],
        ),
      ),
    );
  }
}