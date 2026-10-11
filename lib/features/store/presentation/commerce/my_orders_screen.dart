import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';
import 'shop_widgets.dart';

/// Buyer: every physical order, in tabs.
class MyShopOrdersScreen extends StatelessWidget {
  const MyShopOrdersScreen({super.key});

  static const _tabs = <(String?, String)>[(null, 'All'), ('active', 'Active'), ('delivered', 'Delivered'), ('cancelled', 'Cancelled')];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My orders'),
          actions: [const CartIconButton(), const SizedBox(width: 4)],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            tabs: [for (final t in _tabs) Tab(text: t.$2)],
          ),
        ),
        body: TabBarView(children: [for (final t in _tabs) _OrdersTab(status: t.$1)]),
      ),
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.status});

  final String? status;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> with AutomaticKeepAliveClientMixin {
  late final PagedCubit<ShopOrder> _cubit = PagedCubit<ShopOrder>((page) => ShopRepository.i.myOrders(page: page, status: widget.status));

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PagedListView<ShopOrder>(
      cubit: _cubit,
      empty: MessageView(
        icon: ShopIcons.orders,
        title: widget.status == null ? 'No orders yet' : 'Nothing here',
        message: 'Things you buy from creators show up here.',
        action: widget.status == null ? AppButton(label: 'Start shopping', expand: false, onPressed: () => context.push(AppRoutes.shop)) : null,
      ),
      itemBuilder: (context, o) => BuyerOrderCard(
        order: o,
        onTap: () async {
          await context.push(AppRoutes.shopOrder(o.id));
          if (mounted) _cubit.refresh();
        },
      ),
    );
  }
}

class BuyerOrderCard extends StatelessWidget {
  const BuyerOrderCard({super.key, required this.order, required this.onTap});

  final ShopOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OrderStatusChip(status: o.status),
                  const Spacer(),
                  Text(Fmt.shortDate(o.placedAt ?? o.createdAt), style: context.text.bodySmall),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ShopThumb(url: o.firstImage, size: 64),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                        const SizedBox(height: 2),
                        Text('${o.store.name} · ${o.itemCount} item${o.itemCount == 1 ? '' : 's'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        const SizedBox(height: 2),
                        Text('${Fmt.money(o.total)} · ${o.isCod ? 'Cash on Delivery' : 'Paid online'}', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: palette.textPrimary)),
                      ],
                    ),
                  ),
                  Icon(AppIcons.chevronRight, color: palette.textTertiary, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Buyer: one order — progress, tracking, items, address, payment, cancel.
class ShopOrderDetailScreen extends StatelessWidget {
  const ShopOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<ShopOrder>(() => ShopRepository.i.myOrder(orderId)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<ShopOrder>>();
          final order = cubit.state.data;
          return Scaffold(
            appBar: AppBar(title: Text(order == null ? 'Order' : 'Order ${order.orderNumber}')),
            body: AsyncView<ShopOrder>(state: cubit.state, onRetry: cubit.load, builder: (o) => _OrderBody(order: o)),
            bottomNavigationBar: order == null || (!order.canCancel && !order.canMarkReceived) ? null : _OrderActions(order: order),
          );
        },
      ),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final palette = context.palette;
    return AppRefresh(
      onRefresh: context.read<LoadCubit<ShopOrder>>().refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          ShopSection(title: 'Order status', child: OrderProgress(order: o)),
          if (o.isShipped && o.trackingUrl.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton.secondary(label: 'Track package', icon: ShopIcons.truck, onPressed: () async {
              try {
                await LinkOpener.open(o.trackingUrl);
              } on ApiException catch (e) {
                if (context.mounted) AppSnackbar.error(context, e.displayMessage);
              }
            },
            ),
          ],
          if (o.isShipped && o.trackingId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: o.trackingId));
                  AppSnackbar.success(context, 'Tracking ID copied');
                },
                icon: const Icon(AppIcons.copy, size: 16),
                label: Text('Copy tracking ID ${o.trackingId}'),
              ),
            ),
          ],
          if (o.sellerNote.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ShopSection(title: 'Note from the seller', child: Text(o.sellerNote, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
          ],
          const SizedBox(height: AppSpacing.sm),
          ShopSection(
            title: 'Items',
            trailing: o.store.slug.isEmpty
                ? null
                : InkWell(
              onTap: () => context.push(AppRoutes.storePage(o.store.slug)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StoreLogo(name: o.store.name, url: o.store.logoUrl, size: 18),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(o.store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            child: Column(children: [for (final i in o.items) OrderItemRow(item: i)]),
          ),
          const SizedBox(height: AppSpacing.sm),
          ShopSection(
            title: 'Delivery address',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.address.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(o.address.singleLine, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.4)),
                const SizedBox(height: 2),
                Text('Phone: ${o.address.phone}', style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ShopSection(
            title: 'Payment',
            child: Column(
              children: [
                PriceLine(label: 'Items', value: Fmt.money(o.itemsTotal)),
                PriceLine(label: 'Delivery', value: o.deliveryCharge == 0 ? 'FREE' : Fmt.money(o.deliveryCharge), valueColor: o.deliveryCharge == 0 ? AppColors.success : null),
                const Divider(height: 18),
                PriceLine(label: 'Total', value: Fmt.money(o.total), bold: true),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(o.isCod ? ShopIcons.cash : ShopIcons.card, size: 16, color: palette.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(o.paymentLabel, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Ordered ${Fmt.dateTime(o.placedAt ?? o.createdAt)} · Order ${o.orderNumber}', style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// One line of an order (photo, title, option, qty, price).
class OrderItemRow extends StatelessWidget {
  const OrderItemRow({super.key, required this.item});

  final ShopOrderItem item;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: item.productId.isEmpty ? null : () => context.push(AppRoutes.shopProduct(item.productId)),
        child: Row(
          children: [
            ShopThumb(url: item.imageUrl, size: 56),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                  Text([if (item.optionText.isNotEmpty) item.optionText, 'Qty ${item.qty}', '${Fmt.money(item.price)} each'].join(' · '), style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(Fmt.money(item.price * item.qty), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _OrderActions extends StatefulWidget {
  const _OrderActions({required this.order});

  final ShopOrder order;

  @override
  State<_OrderActions> createState() => _OrderActionsState();
}

class _OrderActionsState extends State<_OrderActions> {
  bool _busy = false;

  Future<void> _run(Future<ShopOrder> Function() task, String message) async {
    setState(() => _busy = true);
    try {
      final updated = await task();
      if (!mounted) return;
      context.read<LoadCubit<ShopOrder>>().replace(updated);
      AppSnackbar.success(context, message);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await askCancelReason(context, buyer: true);
    if (reason == null || !mounted) return;
    await _run(() => ShopRepository.i.cancelMyOrder(widget.order.id, reason), 'Order cancelled');
  }

  Future<void> _received() async {
    final ok = await confirmAction(context, title: 'Got your order?', message: 'Confirm only after the parcel has reached you.', confirmLabel: 'Yes, I received it');
    if (!ok || !mounted) return;
    await _run(() => ShopRepository.i.markReceived(widget.order.id), 'Thanks for confirming!');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return ShopBottomBar(
      child: o.canMarkReceived
          ? GradientButton(label: 'I received my order', icon: AppIcons.checkCircle, isLoading: _busy, onPressed: _received)
          : AppButton.secondary(label: 'Cancel order', isLoading: _busy, onPressed: _busy ? null : _cancel),
    );
  }
}

/// Asks why an order is being cancelled. Returns null when dismissed.
Future<String?> askCancelReason(BuildContext context, {required bool buyer}) {
  final reasons = buyer
      ? const ['Ordered by mistake', 'Found a better price', 'Delivery is taking too long', 'Want to change size or address', 'Other']
      : const ['Out of stock', 'Can’t deliver to this pincode', 'Buyer asked to cancel', 'Product damaged', 'Other'];
  return showAppSheet<String>(context, builder: (_) => _CancelSheet(reasons: reasons, buyer: buyer));
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.reasons, required this.buyer});

  final List<String> reasons;
  final bool buyer;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  String? _picked;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _reason => _picked == 'Other' ? (_other.text.trim().length >= 3 ? _other.text.trim() : null) : _picked;

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Cancel this order?',
      subtitle: widget.buyer ? 'If you paid online, the money is refunded in 5–7 working days.' : 'The buyer is told and refunded if they paid online.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in widget.reasons)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                _picked == r ? AppIcons.checkCircle : PhosphorIconsRegular.circle,
                color: _picked == r ? AppColors.primary : context.palette.textTertiary,
              ),
              title: Text(r),
              onTap: () => setState(() => _picked = r),
            ),
          if (_picked == 'Other') ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextField(label: 'Tell us more', controller: _other, maxLength: 300, onChanged: (_) => setState(() {})),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Cancel order',
            variant: AppButtonVariant.danger,
            onPressed: _reason == null ? null : () => Navigator.of(context).pop(_reason),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Keep order', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}