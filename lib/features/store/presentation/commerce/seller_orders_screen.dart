import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/models/common_models.dart';
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
import '../../../../core/widgets/user_avatar.dart';
import '../../data/shop_repository.dart';
import 'my_orders_screen.dart';
import 'shop_widgets.dart';

/// Seller: orders to confirm, ship and deliver.
class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  static const _tabs = <(String, String)>[('new', 'New'), ('to_ship', 'To ship'), ('shipped', 'Shipped'), ('delivered', 'Delivered'), ('cancelled', 'Cancelled')];

  /// Badge numbers, refreshed with every page load.
  final ValueNotifier<Map<String, int>> _counts = ValueNotifier(const {});

  @override
  void dispose() {
    _counts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      initialIndex: widget.initialTab.clamp(0, _tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shop orders'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            tabs: [
              for (final t in _tabs)
                Tab(
                  child: ValueListenableBuilder<Map<String, int>>(
                    valueListenable: _counts,
                    builder: (context, counts, _) {
                      final n = counts[t.$1] ?? 0;
                      final showBadge = n > 0 && (t.$1 == 'new' || t.$1 == 'to_ship' || t.$1 == 'shipped');
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.$2),
                          if (showBadge) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: t.$1 == 'new' ? AppColors.primary : context.palette.surfaceMuted, borderRadius: BorderRadius.circular(10)),
                              child: Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: t.$1 == 'new' ? Colors.white : context.palette.textPrimary)),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(children: [for (final t in _tabs) _SellerTab(tab: t.$1, counts: _counts)]),
      ),
    );
  }
}

class _SellerTab extends StatefulWidget {
  const _SellerTab({required this.tab, required this.counts});

  final String tab;
  final ValueNotifier<Map<String, int>> counts;

  @override
  State<_SellerTab> createState() => _SellerTabState();
}

class _SellerTabState extends State<_SellerTab> with AutomaticKeepAliveClientMixin {
  late final PagedCubit<ShopOrder> _cubit = PagedCubit<ShopOrder>(_fetch);

  Future<Paged<ShopOrder>> _fetch(int page) async {
    final result = await ShopRepository.i.sellerOrders(tab: widget.tab, page: page);
    if (mounted) widget.counts.value = result.tabCounts;
    return Paged(items: result.orders, page: result.page, pages: result.pages, total: result.total);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  String get _emptyText => switch (widget.tab) {
    'new' => 'New orders show up here. Confirm them quickly so buyers know you’re on it.',
    'to_ship' => 'Confirmed orders waiting to be shipped.',
    'shipped' => 'Orders on the way. Mark them delivered once they arrive.',
    'delivered' => 'Delivered orders — online payments reach your wallet on delivery.',
    _ => 'Cancelled orders show up here.',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PagedListView<ShopOrder>(
      cubit: _cubit,
      empty: MessageView(icon: ShopIcons.orders, title: 'Nothing here', message: _emptyText),
      itemBuilder: (context, o) => _SellerOrderCard(
        order: o,
        onTap: () async {
          await context.push(AppRoutes.sellerShopOrder(o.id));
          if (mounted) _cubit.refresh();
        },
      ),
    );
  }
}

class _SellerOrderCard extends StatelessWidget {
  const _SellerOrderCard({required this.order, required this.onTap});

  final ShopOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final palette = context.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: o.status == 'placed' ? AppColors.primary.withValues(alpha: 0.5) : palette.border),
      ),
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
                  Text('#${o.orderNumber}', style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text(Fmt.relative(o.placedAt ?? o.createdAt), style: context.text.bodySmall),
                  const Spacer(),
                  OrderStatusChip(status: o.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ShopThumb(url: o.firstImage, size: 60),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                        const SizedBox(height: 2),
                        Text('${o.address.name} · ${o.address.city}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Fmt.money(o.total), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: (o.isCod ? AppColors.warning : AppColors.success).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
                        child: Text(o.isCod ? 'COD' : 'PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: o.isCod ? AppColors.warning : AppColors.success)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seller: one order — buyer address, items, money and the next step.
class SellerOrderDetailScreen extends StatelessWidget {
  const SellerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<ShopOrder>(() => ShopRepository.i.sellerOrder(orderId)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<ShopOrder>>();
          final order = cubit.state.data;
          return Scaffold(
            appBar: AppBar(title: Text(order == null ? 'Order' : '#${order.orderNumber}')),
            body: AsyncView<ShopOrder>(state: cubit.state, onRetry: cubit.load, builder: (o) => _SellerOrderBody(order: o)),
            bottomNavigationBar: order == null || order.nextActions.isEmpty ? null : _SellerActions(order: order),
          );
        },
      ),
    );
  }
}

class _SellerOrderBody extends StatelessWidget {
  const _SellerOrderBody({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final palette = context.palette;
    final a = o.address;
    return AppRefresh(
      onRefresh: context.read<LoadCubit<ShopOrder>>().refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          // What to do now
          if (o.status == 'placed' || o.status == 'confirmed')
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(
                children: [
                  const Icon(AppIcons.info, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      o.status == 'placed'
                          ? 'Confirm this order, pack it and ship it to the address below.'
                          : 'Pack and ship it, then tap “Mark as shipped” and add the tracking ID.',
                      style: context.text.bodySmall?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ShopSection(title: 'Status', child: OrderProgress(order: o)),
          const SizedBox(height: AppSpacing.sm),

          // Ship to
          ShopSection(
            title: 'Ship to',
            trailing: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${a.name}\n${a.singleLine}\nPhone: ${a.phone}'));
                AppSnackbar.success(context, 'Address copied');
              },
              icon: const Icon(AppIcons.copy, size: 16),
              label: const Text('Copy'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (o.buyer != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        UserAvatar(initials: _initials(o.buyer!.name), imageUrl: o.buyer!.avatar, size: 26),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Ordered by ${o.buyer!.name}', style: context.text.bodySmall)),
                      ],
                    ),
                  ),
                Text(a.name, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(a.singleLine, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.4)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => LinkOpener.open('tel:${a.phone}').catchError((Object _) {}),
                  icon: const Icon(AppIcons.phone, size: 16),
                  label: Text('Call ${a.phone}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ShopSection(title: 'Items to pack', child: Column(children: [for (final i in o.items) OrderItemRow(item: i)])),
          const SizedBox(height: AppSpacing.sm),

          // Money
          ShopSection(
            title: 'Payment',
            child: Column(
              children: [
                if (o.isCod && !o.isCancelled)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Text(
                      o.isDelivered ? 'Cash on Delivery — collected ${Fmt.money(o.total)}' : 'Cash on Delivery — collect ${Fmt.money(o.total)} from the buyer',
                      style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                PriceLine(label: 'Items', value: Fmt.money(o.itemsTotal)),
                PriceLine(label: 'Delivery charge', value: o.deliveryCharge == 0 ? 'FREE' : Fmt.money(o.deliveryCharge)),
                PriceLine(label: 'Order total', value: Fmt.money(o.total), bold: true),
                if (o.isDelivered) ...[
                  const Divider(height: 18),
                  PriceLine(label: 'Fanitt fee (${o.feePercent % 1 == 0 ? o.feePercent.toInt() : o.feePercent}% of items)', value: '− ${Fmt.money(o.feeAmount)}'),
                  PriceLine(label: 'You earn', value: Fmt.money(o.creatorEarning), bold: true, valueColor: AppColors.success),
                  const SizedBox(height: 4),
                  Text(
                    o.isCod ? 'You collected the cash; the fee was taken from your Fanitt wallet.' : 'Added to your Fanitt wallet.',
                    style: context.text.bodySmall,
                  ),
                ] else if (!o.isCancelled) ...[
                  const SizedBox(height: 4),
                  Text(
                    o.isCod
                        ? 'After delivery, Fanitt’s fee is taken from your wallet.'
                        : 'Paid online — your earning reaches your Fanitt wallet once it is delivered.',
                    style: context.text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Placed ${Fmt.dateTime(o.placedAt ?? o.createdAt)}', style: context.text.bodySmall),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

class _SellerActions extends StatefulWidget {
  const _SellerActions({required this.order});

  final ShopOrder order;

  @override
  State<_SellerActions> createState() => _SellerActionsState();
}

class _SellerActionsState extends State<_SellerActions> {
  String? _busy;

  Future<void> _run(String key, Future<ShopOrder> Function() task, String message) async {
    setState(() => _busy = key);
    try {
      final updated = await task();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.read<LoadCubit<ShopOrder>>().replace(updated);
      AppSnackbar.success(context, message);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _ship({bool updateOnly = false}) async {
    final o = widget.order;
    final details = await showAppSheet<({String courier, String trackingId, String trackingUrl, String note})>(
      context,
      builder: (_) => _ShipSheet(order: o, updateOnly: updateOnly),
    );
    if (details == null || !mounted) return;
    await _run(
      'ship',
          () => ShopRepository.i.shipOrder(o.id, courier: details.courier, trackingId: details.trackingId, trackingUrl: details.trackingUrl, note: details.note),
      updateOnly ? 'Tracking updated' : 'Marked as shipped — the buyer is notified',
    );
  }

  Future<void> _deliver() async {
    final o = widget.order;
    final ok = await confirmAction(
      context,
      title: 'Mark as delivered?',
      message: o.isCod ? 'Confirm the buyer received it and you collected ${Fmt.money(o.total)}.' : 'Confirm the buyer received the parcel. Your earning goes to your wallet.',
      confirmLabel: 'Delivered',
    );
    if (!ok || !mounted) return;
    await _run('deliver', () => ShopRepository.i.deliverOrder(o.id), 'Marked as delivered');
  }

  Future<void> _cancel() async {
    final reason = await askCancelReason(context, buyer: false);
    if (reason == null || !mounted) return;
    await _run('cancel', () => ShopRepository.i.sellerCancel(widget.order.id, reason), 'Order cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final actions = o.nextActions;
    final busy = _busy != null;
    final Widget primary;
    if (actions.contains('confirm')) {
      primary = GradientButton(label: 'Confirm order', isLoading: _busy == 'confirm', onPressed: busy ? null : () => _run('confirm', () => ShopRepository.i.confirmOrder(o.id), 'Order confirmed'));
    } else if (actions.contains('ship')) {
      primary = GradientButton(label: 'Mark as shipped', icon: ShopIcons.truck, isLoading: _busy == 'ship', onPressed: busy ? null : _ship);
    } else {
      primary = GradientButton(label: 'Mark as delivered', icon: AppIcons.checkCircle, isLoading: _busy == 'deliver', onPressed: busy ? null : _deliver);
    }
    return ShopBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          primary,
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (actions.contains('confirm') && actions.contains('ship'))
                TextButton(onPressed: busy ? null : _ship, child: const Text('Ship directly')),
              if (actions.contains('update_tracking'))
                TextButton(onPressed: busy ? null : () => _ship(updateOnly: true), child: const Text('Update tracking')),
              if (actions.contains('cancel'))
                TextButton(
                  onPressed: busy ? null : _cancel,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: _busy == 'cancel' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Cancel order'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShipSheet extends StatefulWidget {
  const _ShipSheet({required this.order, required this.updateOnly});

  final ShopOrder order;
  final bool updateOnly;

  @override
  State<_ShipSheet> createState() => _ShipSheetState();
}

class _ShipSheetState extends State<_ShipSheet> {
  static const _couriers = ['India Post', 'Delhivery', 'Blue Dart', 'DTDC', 'Ekart', 'Xpressbees', 'Shadowfax', 'Self delivery'];

  late final _courier = TextEditingController(text: widget.order.courier);
  late final _tracking = TextEditingController(text: widget.order.trackingId);
  late final _url = TextEditingController(text: widget.order.trackingUrl);
  late final _note = TextEditingController(text: widget.order.sellerNote);
  String? _urlError;

  @override
  void dispose() {
    for (final c in [_courier, _tracking, _url, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isNotEmpty && !(Uri.tryParse(url)?.hasScheme ?? false)) {
      setState(() => _urlError = 'Enter a full link starting with https://');
      return;
    }
    Navigator.of(context).pop((courier: _courier.text.trim(), trackingId: _tracking.text.trim(), trackingUrl: url, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: widget.updateOnly ? 'Update tracking' : 'Mark as shipped',
      subtitle: 'Tracking details are optional, but buyers love them.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _couriers)
                ChoiceChip(
                  label: Text(c),
                  selected: _courier.text == c,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  onSelected: (_) => setState(() => _courier.text = c),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Courier', controller: _courier, maxLength: 60, onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Tracking ID / AWB', controller: _tracking, maxLength: 80),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Tracking link', controller: _url, hint: 'https://…', keyboardType: TextInputType.url, helperText: _urlError, onChanged: (_) => setState(() => _urlError = null)),
          if (_urlError != null) Text(_urlError!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Note for the buyer', controller: _note, maxLength: 300, hint: 'Optional'),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: widget.updateOnly ? 'Save' : 'Mark as shipped', onPressed: _submit),
        ],
      ),
    );
  }
}