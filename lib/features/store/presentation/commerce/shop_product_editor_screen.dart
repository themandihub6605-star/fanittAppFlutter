import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../data/shop_repository.dart';
import '../widgets/store_widgets.dart';
import 'shop_widgets.dart';

/// Create or edit a physical product: 1–4 photos, price & MRP, stock or
/// options (size / colour) with their own stock, delivery and COD.
/// Pops with `true` when something was saved.
class ShopProductEditorScreen extends StatefulWidget {
  const ShopProductEditorScreen({super.key, this.productId});

  final String? productId;

  @override
  State<ShopProductEditorScreen> createState() => _ShopProductEditorScreenState();
}

/// A photo already uploaded ([url]) or picked and waiting to upload ([file]).
class _Photo {
  const _Photo.url(String this.url) : file = null;
  const _Photo.file(PickedMedia this.file) : url = null;

  final String? url;
  final PickedMedia? file;
}

class _OptionRow {
  _OptionRow({this.id, String label = '', int stock = 0})
      : label = TextEditingController(text: label),
        stock = TextEditingController(text: stock == 0 && label.isEmpty ? '' : '$stock');

  final String? id;
  final TextEditingController label;
  final TextEditingController stock;

  void dispose() {
    label.dispose();
    stock.dispose();
  }
}

class _ShopProductEditorScreenState extends State<ShopProductEditorScreen> {
  static const _maxPhotos = 4;
  static const _variantNames = ['Size', 'Colour', 'Pack', 'Style'];

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _mrp = TextEditingController();
  final _stock = TextEditingController();
  final _variantName = TextEditingController(text: 'Size');
  final _delivery = TextEditingController(text: '0');
  final _deliveryDays = TextEditingController(text: '3–7 days');
  final _returnPolicy = TextEditingController();

  ShopProduct? _product;
  List<_Photo> _photos = [];
  List<String> _highlights = [];
  final List<_OptionRow> _options = [];
  String _category = 'fashion';
  bool _hasOptions = false;
  bool _cod = true;
  bool _loading = false;
  String? _loadError;
  String? _busy; // 'draft' | 'publish'

  bool get _isNew => widget.productId == null && _product == null;
  bool get _isLive => _product?.isPublished ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) _load();
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _mrp, _stock, _variantName, _delivery, _deliveryDays, _returnPolicy]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final p = await ShopRepository.i.myProduct(widget.productId!);
      if (!mounted) return;
      _fill(p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.displayMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(ShopProduct p) {
    _product = p;
    _title.text = p.title;
    _description.text = p.description;
    _price.text = Fmt.paiseToRupeesInput(p.price);
    _mrp.text = p.mrp > 0 ? Fmt.paiseToRupeesInput(p.mrp) : '';
    _stock.text = '${p.stock}';
    _delivery.text = Fmt.paiseToRupeesInput(p.deliveryCharge);
    _deliveryDays.text = p.deliveryDays;
    _returnPolicy.text = p.returnPolicy;
    _category = shopCategories.containsKey(p.category) ? p.category : 'other';
    _cod = p.codAvailable;
    _highlights = [...p.highlights];
    _photos = [for (final u in p.images) _Photo.url(u)];
    for (final o in _options) {
      o.dispose();
    }
    _options
      ..clear()
      ..addAll([for (final v in p.variants) _OptionRow(id: v.id, label: v.label, stock: v.stock ?? 0)]);
    _hasOptions = p.variants.isNotEmpty;
    if (p.variantName.isNotEmpty) _variantName.text = p.variantName;
  }

  // ---------- photos ----------

  Future<void> _addPhotos() async {
    final room = _maxPhotos - _photos.length;
    if (room <= 0) return;
    final picker = sl<MediaPicker>();
    final List<PickedMedia> picked;
    if (room >= 2) {
      picked = await picker.images(limit: room);
    } else {
      final one = await picker.image();
      picked = one == null ? const [] : [one];
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _photos = [..._photos, ...picked.take(room).map(_Photo.file)]);
  }

  Future<void> _photoMenu(int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0) ListTile(leading: const Icon(ShopIcons.star), title: const Text('Make cover photo'), onTap: () => Navigator.of(ctx).pop('cover')),
            ListTile(leading: const Icon(AppIcons.trash, color: AppColors.error), title: const Text('Remove photo'), onTap: () => Navigator.of(ctx).pop('remove')),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() {
      final list = [..._photos];
      final photo = list.removeAt(index);
      if (action == 'cover') list.insert(0, photo);
      _photos = list;
    });
  }

  // ---------- options ----------

  void _toggleOptions(bool on) {
    setState(() {
      _hasOptions = on;
      if (on && _options.isEmpty) _options.addAll([_OptionRow(), _OptionRow()]);
    });
  }

  void _quickSizes() {
    const sizes = ['S', 'M', 'L', 'XL', 'XXL'];
    setState(() {
      final existing = _options.map((o) => o.label.text.trim().toUpperCase()).toSet();
      final empty = _options.where((o) => o.label.text.trim().isEmpty).toList();
      _options.removeWhere(empty.contains);
      _disposeLater(empty);
      for (final s in sizes) {
        if (!existing.contains(s)) _options.add(_OptionRow(label: s));
      }
      _variantName.text = 'Size';
    });
  }

  /// Rows leave the screen this frame — free their controllers after it.
  void _disposeLater(List<_OptionRow> rows) {
    if (rows.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in rows) {
        r.dispose();
      }
    });
  }

  // ---------- save ----------

  ShopProductInput? _buildInput() {
    if (!(_form.currentState?.validate() ?? false)) return null;
    if (_photos.isEmpty) {
      AppSnackbar.error(context, 'Add at least one photo');
      return null;
    }
    final options = <({String? id, String label, int stock})>[];
    if (_hasOptions) {
      for (final o in _options) {
        final label = o.label.text.trim();
        if (label.isEmpty) continue;
        options.add((id: o.id, label: label, stock: int.tryParse(o.stock.text.trim()) ?? 0));
      }
      if (options.isEmpty) {
        AppSnackbar.error(context, 'Add at least one ${_variantName.text.trim().toLowerCase().isEmpty ? 'option' : _variantName.text.trim().toLowerCase()}');
        return null;
      }
      final names = options.map((o) => o.label.toLowerCase()).toList();
      if (names.toSet().length != names.length) {
        AppSnackbar.error(context, 'Each option must have a different name');
        return null;
      }
    }
    return ShopProductInput(
      title: _title.text.trim(),
      description: _description.text.trim(),
      highlights: _highlights,
      category: _category,
      price: Fmt.rupeesToPaise(_price.text) ?? 0,
      mrp: Fmt.rupeesToPaise(_mrp.text) ?? 0,
      stock: _hasOptions ? 0 : int.tryParse(_stock.text.trim()) ?? 0,
      variantName: _variantName.text.trim(),
      variants: options,
      deliveryCharge: Fmt.rupeesToPaise(_delivery.text) ?? 0,
      deliveryDays: _deliveryDays.text.trim(),
      codAvailable: _cod,
      returnPolicy: _returnPolicy.text.trim(),
    );
  }

  Future<void> _save({required bool publish}) async {
    FocusScope.of(context).unfocus();
    final input = _buildInput();
    if (input == null) return;
    setState(() => _busy = publish ? 'publish' : 'draft');
    final repo = ShopRepository.i;
    try {
      // 1. Details
      var product = _product == null ? await repo.createProduct(input) : await repo.updateProduct(_product!.id, input);
      _product = product; // so a retry edits instead of creating a second one

      // 2. Removed photos first, so new ones fit in the 4-photo limit. A live
      //    product must always keep one photo, so if every old one is being
      //    replaced, the last old one is removed after the upload.
      final keep = _photos.map((p) => p.url).whereType<String>().toSet();
      final toRemove = product.images.where((u) => !keep.contains(u)).toList();
      final deferred = product.isPublished && keep.isEmpty && toRemove.isNotEmpty ? toRemove.removeLast() : null;
      for (final url in toRemove) {
        product = await repo.removeImage(product.id, url);
      }

      // 3. New photos
      final before = product.images.toSet();
      final files = [for (final p in _photos) if (p.file != null) p.file!];
      if (files.isNotEmpty) {
        product = await repo.uploadImages(product.id, files);
        final uploaded = product.images.where((u) => !before.contains(u)).toList();
        var next = 0;
        _photos = [
          for (final p in _photos)
            if (p.url != null) p else if (next < uploaded.length) _Photo.url(uploaded[next++]),
        ];
        if (uploaded.length < files.length && mounted) {
          AppSnackbar.error(context, 'Only ${uploaded.length} of ${files.length} new photos were added — a product can have 4');
        }
      }
      if (deferred != null) product = await repo.removeImage(product.id, deferred);

      // 4. Order (first = cover)
      final wanted = _photos.map((p) => p.url).whereType<String>().where(product.images.contains).toList();
      if (wanted.length == product.images.length && wanted.join('|') != product.images.join('|')) {
        product = await repo.reorderImages(product.id, wanted);
      }

      // 5. Publish
      if (publish && !product.isPublished) product = await repo.publish(product.id);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      AppSnackbar.success(context, publish ? 'Your product is live' : (product.isPublished ? 'Changes saved' : 'Saved as draft'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.displayMessage);
      setState(() {}); // photos may now be partly uploaded
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew ? 'Add product' : 'Edit product';
    if (_loading || (_loadError != null && _product == null)) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _loadError != null ? ErrorView(message: _loadError!, onRetry: _load) : const LoadingView(),
      );
    }
    final palette = context.palette;
    final busy = _busy != null;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xxl),
            children: [
              if (_product?.isRemoved ?? false)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Text('Removed by Fanitt: ${_product!.removedReason}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                ),

              // Photos
              FieldLabel('Photos (${_photos.length}/$_maxPhotos)', isRequired: true),
              Text('First photo is the cover. Use clear, square photos on a plain background.', style: context.text.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 96,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: GestureDetector(
                          onTap: busy ? null : () => _photoMenu(i),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                child: SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: _photos[i].file != null
                                      ? Image.file(File(_photos[i].file!.path), fit: BoxFit.cover)
                                      : StoreImage(url: _photos[i].url!, icon: ShopIcons.bag),
                                ),
                              ),
                              if (i == 0)
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(5)),
                                    child: const Text('COVER', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                                  child: const Icon(AppIcons.dotsThree, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_photos.length < _maxPhotos)
                      InkWell(
                        onTap: busy ? null : _addPhotos,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(AppIcons.camera, color: AppColors.primary),
                              SizedBox(height: 4),
                              Text('Add photo', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Basics
              AppTextField(
                label: 'Product name',
                isRequired: true,
                controller: _title,
                maxLength: 120,
                hint: 'e.g. Oversized cotton T-shirt — black',
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().length < 3) ? 'Title must be at least 3 characters' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              const FieldLabel('Category', isRequired: true),
              ChoicePills<String>(
                options: shopCategories.keys.toList(),
                selected: {_category},
                labelOf: (k) => shopCategories[k]!,
                onChanged: (k) => setState(() => _category = k),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Price
              _Heading(icon: ShopIcons.tag, text: 'Price'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Selling price (₹)',
                      isRequired: true,
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final paise = Fmt.rupeesToPaise(v ?? '');
                        if (paise == null || paise < 100) return 'At least ₹1';
                        if (paise > 10000000) return 'Max ₹1,00,000';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      label: 'MRP (₹)',
                      controller: _mrp,
                      hint: 'Optional',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final mrp = Fmt.rupeesToPaise(v ?? '') ?? 0;
                        final price = Fmt.rupeesToPaise(_price.text) ?? 0;
                        if (mrp > 0 && mrp < price) return 'Must be more than price';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              Builder(
                builder: (context) {
                  final price = Fmt.rupeesToPaise(_price.text) ?? 0;
                  final mrp = Fmt.rupeesToPaise(_mrp.text) ?? 0;
                  if (price <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Text('Buyers see: ', style: context.text.bodySmall),
                        ShopPrice(price: price, mrp: mrp, size: 14),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // Stock & options
              _Heading(icon: AppIcons.package, text: 'Stock'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _hasOptions,
                onChanged: busy ? null : _toggleOptions,
                title: Text('Has sizes, colours or other options', style: context.text.titleSmall),
                subtitle: Text('Each option gets its own stock', style: context.text.bodySmall),
              ),
              if (!_hasOptions)
                AppTextField(
                  label: 'Units in stock',
                  isRequired: true,
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => _hasOptions || (int.tryParse(v ?? '') != null) ? null : 'Enter how many you have',
                )
              else ...[
                const FieldLabel('Option type'),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final n in _variantNames)
                      ChoiceChip(
                        label: Text(n),
                        selected: _variantName.text == n,
                        onSelected: (_) => setState(() => _variantName.text = n),
                        selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    key: ObjectKey(_options[i]),
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: AppTextField(label: '${_variantName.text} ${i + 1}', controller: _options[i].label, hint: _variantName.text == 'Size' ? 'e.g. M' : 'e.g. Black', maxLength: 30),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          flex: 2,
                          child: AppTextField(
                            label: 'Stock',
                            controller: _options[i].stock,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 26),
                          child: IconButton(
                            tooltip: 'Remove',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                              _disposeLater([_options.removeAt(i)]);
                              if (_options.isEmpty) _hasOptions = false;
                            }),
                            icon: Icon(AppIcons.close, color: palette.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _options.length >= 20 || busy ? null : () => setState(() => _options.add(_OptionRow())),
                      icon: const Icon(AppIcons.plus, size: 18),
                      label: const Text('Add option'),
                    ),
                    if (_variantName.text == 'Size') TextButton(onPressed: busy ? null : _quickSizes, child: const Text('Add S – XXL')),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // Delivery
              _Heading(icon: ShopIcons.truck, text: 'Delivery'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Delivery charge (₹)',
                      controller: _delivery,
                      helperText: '0 = free delivery',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      validator: (v) => (Fmt.rupeesToPaise(v ?? '') ?? 0) > 1000000 ? 'Max ₹10,000' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: AppTextField(label: 'Delivered in', controller: _deliveryDays, hint: 'e.g. 3–7 days', maxLength: 30)),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _cod,
                onChanged: (v) => setState(() => _cod = v),
                title: Text('Allow Cash on Delivery', style: context.text.titleSmall),
                subtitle: Text(_cod ? 'Buyers can pay when it arrives — you collect the cash' : 'Buyers must pay online', style: context.text.bodySmall),
              ),
              const SizedBox(height: AppSpacing.md),

              // Details
              _Heading(icon: AppIcons.fileText, text: 'Details'),
              AppTextField(
                label: 'Description',
                controller: _description,
                minLines: 4,
                maxLines: 10,
                maxLength: 5000,
                hint: 'Material, fit, size guide, care instructions…',
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: AppSpacing.sm),
              TagInput(
                label: 'Highlights',
                values: _highlights,
                maxItems: 8,
                hint: 'e.g. 100% cotton',
                onChanged: (v) => setState(() => _highlights = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'Return / exchange policy',
                controller: _returnPolicy,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                hint: 'Optional — e.g. Size exchange within 7 days of delivery',
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        bottomNavigationBar: ShopBottomBar(
          child: _isLive
              ? GradientButton(label: 'Save changes', isLoading: _busy == 'draft', onPressed: busy ? null : () => _save(publish: false))
              : Row(
            children: [
              Expanded(
                child: AppButton.secondary(label: 'Save draft', height: 50, isLoading: _busy == 'draft', onPressed: busy ? null : () => _save(publish: false)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: GradientButton(label: 'Publish', isLoading: _busy == 'publish', onPressed: busy ? null : () => _save(publish: true))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(text, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}