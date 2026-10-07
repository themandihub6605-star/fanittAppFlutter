import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Creator's Affiliate Store: products, collections and an earnings log.
class MyAffiliateScreen extends StatelessWidget {
  const MyAffiliateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<StoreRepository>();
    final palette = context.palette;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => LoadCubit<List<AffiliateProduct>>(repo.myAffiliateProducts)),
        BlocProvider(create: (_) => LoadCubit<List<AffiliateCollection>>(repo.myCollections)),
        BlocProvider(create: (_) => LoadCubit<AffiliateEarnings>(repo.affiliateEarnings)),
      ],
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Affiliate Store'),
            bottom: TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: palette.textSecondary,
              indicatorColor: AppColors.primary,
              dividerColor: palette.border,
              tabs: const [Tab(text: 'Products'), Tab(text: 'Collections'), Tab(text: 'Earnings')],
            ),
          ),
          body: const TabBarView(children: [_ProductsTab(), _CollectionsTab(), _EarningsTab()]),
        ),
      ),
    );
  }
}

// ---------- products ----------

class _ProductsTab extends StatelessWidget {
  const _ProductsTab();

  Future<void> _edit(BuildContext context, [AffiliateProduct? product]) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _ProductSheet(product: product)));
    if (saved == true && context.mounted) context.read<LoadCubit<List<AffiliateProduct>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<AffiliateProduct>>>();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-affiliate',
        onPressed: () => _edit(context),
        icon: const Icon(AppIcons.link),
        label: const Text('Add product'),
      ),
      body: AsyncView<List<AffiliateProduct>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (items) => AppRefresh(
          onRefresh: cubit.refresh,
          child: items.isEmpty
              ? const ScrollableMessage(
                  child: MessageView(
                    icon: AppIcons.link,
                    title: 'Share products you love',
                    message: 'Paste your affiliate link from Amazon, Nykaa, Flipkart and more. We count every click; the shop pays your commission.',
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return AppCard(
                      onTap: p.isRemoved ? null : () => _edit(context, p),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: SizedBox(width: 60, height: 60, child: StoreImage(url: p.imageUrl, icon: AppIcons.link, fit: BoxFit.contain)),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                                Text(
                                  [if (p.merchant.isNotEmpty) p.merchant, if (p.price != null) Fmt.money(p.price!), '${p.clicks} clicks'].join(' · '),
                                  style: context.text.bodySmall,
                                ),
                                if (p.isRemoved) Text('Removed by Fanitt: ${p.removedReason}', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
                              ],
                            ),
                          ),
                          if (p.isHidden) StatusChip(label: 'Hidden', color: context.palette.textSecondary),
                        ],
                      ),
                    ).animate(delay: (30 * i.clamp(0, 10)).ms).fadeIn(duration: 250.ms);
                  },
                ),
        ),
      ),
    );
  }
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet({this.product});

  final AffiliateProduct? product;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.product?.url ?? '');
  late final _title = TextEditingController(text: widget.product?.title ?? '');
  late final _merchant = TextEditingController(text: widget.product?.merchant ?? '');
  late final _price = TextEditingController(text: widget.product?.price == null ? '' : Fmt.paiseToRupeesInput(widget.product!.price!));
  late String _imageUrl = widget.product?.imageUrl ?? '';
  late String _description = widget.product?.description ?? '';
  PickedMedia? _image;
  bool _reading = false;

  bool get _isNew => widget.product == null;

  @override
  void dispose() {
    for (final c in [_url, _title, _merchant, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _autofill() async {
    final url = _url.text.trim();
    if (!url.startsWith('http')) {
      AppSnackbar.error(context, 'Paste the full link first');
      return;
    }
    setState(() => _reading = true);
    try {
      final p = await sl<StoreRepository>().previewLink(url);
      if (!mounted) return;
      setState(() {
        if (p.title.isNotEmpty) _title.text = p.title;
        if (p.merchant.isNotEmpty) _merchant.text = p.merchant;
        if (p.price != null) _price.text = Fmt.paiseToRupeesInput(p.price!);
        if (p.imageUrl.isNotEmpty) _imageUrl = p.imageUrl;
        if (p.description.isNotEmpty) _description = p.description;
      });
      if (!p.found) AppSnackbar.info(context, 'We couldn’t read that page — fill the details yourself');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = sl<StoreRepository>();
    final done = await context.read<ActionCubit>().run('save', () async {
      final saved = await repo.saveAffiliateProduct(
        id: widget.product?.id,
        url: _url.text.trim(),
        title: _title.text.trim(),
        description: _description,
        imageUrl: _image == null ? _imageUrl : (widget.product?.imageUrl ?? ''),
        price: Fmt.rupeesToPaise(_price.text),
        merchant: _merchant.text.trim(),
      );
      if (_image != null) await repo.uploadAffiliateImage(saved.id, _image!);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _toggleHidden() async {
    final p = widget.product!;
    final done = await context.read<ActionCubit>().run('hide', () async {
      await sl<StoreRepository>().setAffiliateHidden(p.id, !p.isHidden);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context, title: 'Delete this product?', message: 'It’s removed from your store and collections.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    final done = await context.read<ActionCubit>().run('delete', () async {
      await sl<StoreRepository>().deleteAffiliateProduct(widget.product!.id);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy || _reading;
    return SheetBody(
      title: _isNew ? 'Add affiliate product' : 'Edit product',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Your affiliate link',
              hint: 'https://amzn.to/…',
              controller: _url,
              keyboardType: TextInputType.url,
              prefixIcon: AppIcons.link,
              validator: (v) => (v?.trim().startsWith('http') ?? false) ? null : 'Enter a full link starting with https://',
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : _autofill,
                icon: _reading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.sparkle, size: 16),
                label: const Text('Auto-fill from link'),
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: busy
                      ? null
                      : () async {
                          final picked = await sl<MediaPicker>().image();
                          if (picked != null) setState(() => _image = picked);
                        },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _image != null
                          ? const ColoredBox(color: AppColors.success, child: Icon(AppIcons.checkCircle, color: Colors.white))
                          : StoreImage(url: _imageUrl, icon: AppIcons.camera, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_image != null ? 'New photo selected' : 'Tap to upload your own photo', style: context.text.bodySmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Product name', controller: _title, maxLength: 150, validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Add a product name' : null),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: AppTextField(label: 'Shop', hint: 'Amazon', controller: _merchant, maxLength: 60)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppTextField(
                    label: 'Price (₹)',
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const InlineActionError(),
            AppButton(label: _isNew ? 'Add to my store' : 'Save', isLoading: context.watch<ActionCubit>().state.busyKey == 'save', onPressed: busy ? null : _save),
            if (!_isNew) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(child: TextButton(onPressed: busy ? null : _toggleHidden, child: Text(widget.product!.isHidden ? 'Show in store' : 'Hide from store'))),
                  Expanded(child: TextButton(onPressed: busy ? null : _delete, child: const Text('Delete', style: TextStyle(color: AppColors.error)))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------- collections ----------

class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab();

  Future<void> _edit(BuildContext context, List<AffiliateProduct> products, [AffiliateCollection? c]) async {
    if (products.isEmpty) {
      AppSnackbar.info(context, 'Add some products first');
      return;
    }
    final saved = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _CollectionSheet(products: products, collection: c)));
    if (saved == true && context.mounted) context.read<LoadCubit<List<AffiliateCollection>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<AffiliateCollection>>>();
    final products = context.watch<LoadCubit<List<AffiliateProduct>>>().state.data ?? const <AffiliateProduct>[];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-collection',
        onPressed: () => _edit(context, products),
        icon: const Icon(AppIcons.plus),
        label: const Text('New collection'),
      ),
      body: AsyncView<List<AffiliateCollection>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (items) => AppRefresh(
          onRefresh: cubit.refresh,
          child: items.isEmpty
              ? const ScrollableMessage(child: MessageView(icon: AppIcons.package, title: 'No collections', message: 'Group products, like “My skincare picks” or “Travel gear”.'))
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => AppCard(
                    onTap: () => _edit(context, products, items[i]),
                    child: Row(
                      children: [
                        const Icon(AppIcons.package, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(items[i].title, style: context.text.titleSmall)),
                        Text('${items[i].productIds.length} products', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({required this.products, this.collection});

  final List<AffiliateProduct> products;
  final AffiliateCollection? collection;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late final _title = TextEditingController(text: widget.collection?.title ?? '');
  late final List<String> _selected = [...?widget.collection?.productIds];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      AppSnackbar.error(context, 'Give the collection a name');
      return;
    }
    final done = await context.read<ActionCubit>().run('save', () async {
      await sl<StoreRepository>().saveCollection(id: widget.collection?.id, title: _title.text.trim(), productIds: _selected);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final done = await context.read<ActionCubit>().run('delete', () async {
      await sl<StoreRepository>().deleteCollection(widget.collection!.id);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: widget.collection == null ? 'New collection' : 'Edit collection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(label: 'Name', controller: _title, maxLength: 80, textCapitalization: TextCapitalization.sentences),
          const FieldLabel('Products (in this order)'),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in widget.products.where((p) => !p.isRemoved))
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(p.id),
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(p.id);
                      } else {
                        _selected.remove(p.id);
                      }
                    }),
                    title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const InlineActionError(),
          AppButton(label: 'Save', isLoading: busy, onPressed: busy ? null : _save),
          if (widget.collection != null) TextButton(onPressed: busy ? null : _delete, child: const Text('Delete collection', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
  }
}

// ---------- earnings ----------

class _EarningsTab extends StatelessWidget {
  const _EarningsTab();

  Future<void> _add(BuildContext context) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _EarningSheet()));
    if (saved == true && context.mounted) context.read<LoadCubit<AffiliateEarnings>>().refresh();
  }

  Future<void> _setStatus(BuildContext context, AffiliateEarning e) async {
    final status = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetBody(
        title: 'Update earning',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in const ['pending', 'confirmed', 'reversed'])
              ListTile(title: Text(s[0].toUpperCase() + s.substring(1)), trailing: e.status == s ? const Icon(AppIcons.check, color: AppColors.primary) : null, onTap: () => Navigator.of(ctx).pop(s)),
            ListTile(
              title: const Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (status == null || status == e.status || !context.mounted) return;
    try {
      final repo = sl<StoreRepository>();
      if (status == 'delete') {
        await repo.deleteAffiliateEarning(e.id);
      } else {
        await repo.setAffiliateEarningStatus(e.id, status);
      }
      if (context.mounted) context.read<LoadCubit<AffiliateEarnings>>().refresh();
    } on ApiException catch (err) {
      if (context.mounted) AppSnackbar.error(context, err.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<AffiliateEarnings>>();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(heroTag: 'add-earning', onPressed: () => _add(context), icon: const Icon(AppIcons.plus), label: const Text('Record earning')),
      body: AsyncView<AffiliateEarnings>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) => AppRefresh(
          onRefresh: cubit.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 100),
            children: [
              Row(
                children: [
                  Expanded(child: StoreStat(label: 'Confirmed', value: Fmt.money(data.confirmed), icon: AppIcons.checkCircle, color: AppColors.success)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: StoreStat(label: 'Pending', value: Fmt.money(data.pending), icon: AppIcons.hourglass, color: AppColors.warning)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Shops pay you directly — record what their dashboards show to track it here.', style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              if (data.items.isEmpty)
                const MessageView(icon: AppIcons.rupee, title: 'No earnings recorded', message: 'Add your affiliate commissions to see them in analytics.')
              else
                for (final e in data.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppCard(
                      onTap: () => _setStatus(context, e),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.productTitle ?? (e.merchant.isEmpty ? 'Affiliate earning' : e.merchant), style: context.text.titleSmall),
                                Text([if (e.merchant.isNotEmpty) e.merchant, '${e.orders} orders', if (e.earnedAt != null) Fmt.date(e.earnedAt!.toLocal())].join(' · '), style: context.text.bodySmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Fmt.money(e.amount), style: context.text.titleSmall),
                              StatusChip(
                                label: e.status[0].toUpperCase() + e.status.substring(1),
                                color: switch (e.status) {
                                  'confirmed' => AppColors.success,
                                  'reversed' => AppColors.error,
                                  _ => AppColors.warning,
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningSheet extends StatefulWidget {
  const _EarningSheet();

  @override
  State<_EarningSheet> createState() => _EarningSheetState();
}

class _EarningSheetState extends State<_EarningSheet> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _orders = TextEditingController(text: '1');
  bool _confirmed = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _orders.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Fmt.rupeesToPaise(_amount.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.error(context, 'Enter the amount');
      return;
    }
    final done = await context.read<ActionCubit>().run('save', () async {
      await sl<StoreRepository>().addAffiliateEarning(
        amount: amount,
        merchant: _merchant.text.trim(),
        orders: int.tryParse(_orders.text.trim()) ?? 1,
        status: _confirmed ? 'confirmed' : 'pending',
      );
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Record an earning',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Amount (₹)',
            controller: _amount,
            prefixIcon: AppIcons.rupee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Shop', hint: 'Amazon', controller: _merchant, maxLength: 60),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Orders', controller: _orders, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _confirmed = v),
            title: Text('Already confirmed by the shop', style: context.text.titleSmall),
          ),
          const InlineActionError(),
          AppButton(label: 'Save', isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}
