import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/shop_repository.dart';
import 'address_form_screen.dart';
import 'order_placed_screen.dart';
import 'shop_widgets.dart';

/// What to buy: the whole cart (default) or one product ("Buy now").
class CheckoutArgs {
  const CheckoutArgs({this.productId, this.variantId, this.qty = 1});

  final String? productId;
  final String? variantId;
  final int qty;

  bool get isBuyNow => productId != null;
}

/// Address → items → payment (Cash on Delivery / online) → Place order.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, this.args = const CheckoutArgs()});

  final CheckoutArgs args;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutSummary? _summary;
  List<ShopAddress>? _addresses;
  ShopAddress? _address;
  String? _method; // cod | online
  String? _error;
  bool _placing = false;

  CheckoutArgs get a => widget.args;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        ShopRepository.i.previewCheckout(productId: a.productId, variantId: a.variantId, qty: a.qty),
        ShopRepository.i.addresses(),
      ]);
      if (!mounted) return;
      final summary = results[0] as CheckoutSummary;
      final addresses = results[1] as List<ShopAddress>;
      setState(() {
        _summary = summary;
        _addresses = addresses;
        _address ??= addresses.where((x) => x.isDefault).firstOrNull ?? addresses.firstOrNull;
        if (_address != null && !addresses.any((x) => x.id == _address!.id)) _address = addresses.firstOrNull;
        _method = _pickMethod(summary, _method);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    }
  }

  String? _pickMethod(CheckoutSummary s, String? current) {
    if (current == 'cod' && s.codAvailable) return 'cod';
    if (current == 'online' && s.onlineAvailable) return 'online';
    if (s.onlineAvailable) return 'online';
    if (s.codAvailable) return 'cod';
    return null;
  }

  Future<void> _addAddress() async {
    final saved = await Navigator.of(context).push<ShopAddress>(MaterialPageRoute(builder: (_) => const AddressFormScreen()));
    if (saved == null || !mounted) return;
    setState(() {
      _addresses = [saved, ...?_addresses?.where((x) => x.id != saved.id)];
      _address = saved;
    });
  }

  Future<void> _changeAddress() async {
    final picked = await showAppSheet<ShopAddress>(
      context,
      builder: (_) => _AddressPicker(addresses: _addresses ?? const [], selectedId: _address?.id),
    );
    if (!mounted) return;
    // The sheet may have added or edited addresses.
    final fresh = await ShopRepository.i.addresses().catchError((_) => _addresses ?? <ShopAddress>[]);
    if (!mounted) return;
    setState(() {
      _addresses = fresh;
      if (picked != null) _address = fresh.where((x) => x.id == picked.id).firstOrNull ?? picked;
      if (_address != null && !fresh.any((x) => x.id == _address!.id)) _address = fresh.firstOrNull;
    });
  }

  Future<void> _place() async {
    final address = _address;
    final method = _method;
    if (address == null) {
      AppSnackbar.error(context, 'Add a delivery address first');
      return;
    }
    if (method == null) return;
    setState(() => _placing = true);
    try {
      final result = await ShopRepository.i.checkout(addressId: address.id, paymentMethod: method, productId: a.productId, variantId: a.variantId, qty: a.qty);
      var orders = result.orders;
      if (!result.placed) {
        final rzp = result.razorpay;
        if (rzp == null) throw const ApiException('Could not start the payment — please try again');
        final paid = await sl<PaymentService>().checkout(
          orderId: rzp.orderId,
          amount: rzp.amount,
          description: rzp.description,
          keyId: rzp.keyId,
          prefill: CheckoutPrefill(name: rzp.name, email: rzp.email, contact: rzp.contact),
        );
        orders = await ShopRepository.i.verifyCheckout(result.checkoutId, razorpayOrderId: paid.orderId ?? rzp.orderId, paymentId: paid.paymentId, signature: paid.signature);
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ShopRepository.i.refreshCartCount();
      context.read<AuthBloc>().add(const AuthRefreshRequested());
      context.pushReplacement(AppRoutes.shopOrderPlaced, extra: OrderPlacedArgs(orders: orders, method: method));
    } on PaymentCancelled {
      if (mounted) AppSnackbar.info(context, 'Payment cancelled — your order is not placed. You can try again.');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.displayMessage);
      if (e.errorCode == 'CART_CHANGED') _load();
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: _error != null && s == null
          ? ErrorView(message: _error!, onRetry: _load)
          : s == null || _addresses == null
          ? const LoadingView()
          : _body(context, s),
      bottomNavigationBar: s == null || s.sellers.isEmpty
          ? null
          : ShopBottomBar(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Fmt.money(s.total), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(_method == 'cod' ? 'Pay on delivery' : 'Pay now', style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: GradientButton(
                label: _method == 'cod' ? 'Place order' : 'Pay ${Fmt.money(s.total)}',
                isLoading: _placing,
                onPressed: _address == null || _method == null || s.unavailable.isNotEmpty ? null : _place,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CheckoutSummary s) {
    final palette = context.palette;
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          _Steps(),
          const SizedBox(height: AppSpacing.md),

          // 1. Address
          if (_address == null)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _addAddress,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(ShopIcons.mapPin, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('Add a delivery address', style: context.text.titleSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800))),
                    const Icon(AppIcons.plus, color: AppColors.primary),
                  ],
                ),
              ),
            )
          else
            ShopSection(
              title: 'Deliver to',
              trailing: TextButton(onPressed: _changeAddress, child: const Text('Change')),
              child: _AddressText(address: _address!),
            ),
          const SizedBox(height: AppSpacing.sm),

          // Problems (stock changed etc.)
          if (s.unavailable.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in s.unavailable) Text('• ${l.title}: ${l.problem}', style: const TextStyle(color: AppColors.error, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(a.isBuyNow ? 'Go back and choose again.' : 'Fix these in your cart to continue.', style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 2. Items, per store
          for (final g in s.sellers) ...[
            ShopSection(
              title: g.store.name.isEmpty ? 'Items' : 'Sold by ${g.store.name}',
              trailing: Text(g.deliveryCharge == 0 ? 'Free delivery' : '+ ${Fmt.money(g.deliveryCharge)} delivery', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              child: Column(
                children: [
                  for (final l in g.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        children: [
                          ShopThumb(url: l.imageUrl, size: 54),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                                Text([if (l.optionText.isNotEmpty) l.optionText, 'Qty ${l.qty}'].join(' · '), style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Text(Fmt.money(l.lineTotal), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // 3. Payment
          ShopSection(
            title: 'Payment method',
            child: Column(
              children: [
                if (s.onlineAvailable)
                  _MethodTile(
                    icon: ShopIcons.card,
                    title: 'Pay online',
                    subtitle: 'UPI, cards, netbanking · secure by Razorpay',
                    selected: _method == 'online',
                    onTap: () => setState(() => _method = 'online'),
                  ),
                if (s.onlineAvailable) const SizedBox(height: AppSpacing.xs),
                _MethodTile(
                  icon: ShopIcons.cash,
                  title: 'Cash on Delivery',
                  subtitle: s.codAvailable ? 'Pay in cash or UPI when it arrives' : s.codNote,
                  selected: _method == 'cod',
                  enabled: s.codAvailable,
                  onTap: () => setState(() => _method = 'cod'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // 4. Price details
          ShopSection(
            title: 'Price details',
            child: Column(
              children: [
                PriceLine(label: 'Price (${s.itemCount} item${s.itemCount == 1 ? '' : 's'})', value: Fmt.money(s.mrpTotal)),
                if (s.savings > 0) PriceLine(label: 'Discount', value: '− ${Fmt.money(s.savings)}', valueColor: AppColors.success),
                PriceLine(label: 'Delivery', value: s.deliveryCharge == 0 ? 'FREE' : Fmt.money(s.deliveryCharge), valueColor: s.deliveryCharge == 0 ? AppColors.success : null),
                const Divider(height: 18),
                PriceLine(label: 'Order total', value: Fmt.money(s.total), bold: true),
              ],
            ),
          ),
          if (s.sellers.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Items from ${s.sellers.length} stores arrive as ${s.sellers.length} separate parcels.', style: context.text.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(ShopIcons.shield, size: 16, color: palette.textTertiary),
              const SizedBox(width: 6),
              Expanded(child: Text('By placing the order you agree to Fanitt’s Terms. Cancel free before it ships.', style: context.text.bodySmall?.copyWith(fontSize: 11.5))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget step(String n, String label, bool done) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: done ? AppColors.primary : palette.surfaceMuted,
          child: Text(n, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: done ? Colors.white : palette.textSecondary)),
        ),
        const SizedBox(width: 5),
        Text(label, style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
    Widget line() => Expanded(child: Container(height: 1.5, margin: const EdgeInsets.symmetric(horizontal: 6), color: palette.border));
    return Row(children: [step('1', 'Address', true), line(), step('2', 'Summary', true), line(), step('3', 'Payment', true)]);
  }
}

class _AddressText extends StatelessWidget {
  const _AddressText({required this.address});

  final ShopAddress address;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(address.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(5)),
              child: Text(address.labelText.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: palette.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(address.singleLine, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.4)),
        const SizedBox(height: 4),
        Text('Phone: ${address.phone}', style: context.text.bodySmall),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap, this.enabled = true});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.07) : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? AppColors.primary : palette.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: enabled
              ? () {
            HapticFeedback.selectionClick();
            onTap();
          }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Icon(icon, color: selected ? AppColors.primary : palette.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(subtitle, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(selected ? AppIcons.checkCircle : AppIcons.chevronRight, color: selected ? AppColors.primary : palette.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: choose one of the saved addresses, edit or add one.
class _AddressPicker extends StatefulWidget {
  const _AddressPicker({required this.addresses, required this.selectedId});

  final List<ShopAddress> addresses;
  final String? selectedId;

  @override
  State<_AddressPicker> createState() => _AddressPickerState();
}

class _AddressPickerState extends State<_AddressPicker> {
  late List<ShopAddress> _list = widget.addresses;

  Future<void> _edit([ShopAddress? address]) async {
    final saved = await Navigator.of(context).push<ShopAddress>(MaterialPageRoute(builder: (_) => AddressFormScreen(address: address)));
    if (saved == null || !mounted) return;
    if (address == null) {
      Navigator.of(context).pop(saved); // a new address is used right away
      return;
    }
    setState(() => _list = [for (final x in _list) x.id == saved.id ? saved : x]);
  }

  Future<void> _delete(ShopAddress address) async {
    try {
      await ShopRepository.i.deleteAddress(address.id);
      if (mounted) setState(() => _list = _list.where((x) => x.id != address.id).toList());
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SheetBody(
      title: 'Choose delivery address',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) {
                final x = _list[i];
                final selected = x.id == widget.selectedId;
                return Material(
                  color: selected ? AppColors.primary.withValues(alpha: 0.06) : palette.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    side: BorderSide(color: selected ? AppColors.primary : palette.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => Navigator.of(context).pop(x),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, 0, AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(selected ? AppIcons.checkCircle : ShopIcons.mapPin, size: 20, color: selected ? AppColors.primary : palette.textSecondary),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _AddressText(address: x)),
                          PopupMenuButton<String>(
                            icon: Icon(AppIcons.dotsThree, color: palette.textSecondary),
                            onSelected: (v) => v == 'edit' ? _edit(x) : _delete(x),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Add a new address', icon: AppIcons.plus, onPressed: () => _edit()),
        ],
      ),
    );
  }
}