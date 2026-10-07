import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/link_opener.dart';
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
import '../../../../core/widgets/image_upload_box.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

const _maxFiles = 10;
const _maxFileBytes = 500 * 1024 * 1024;
const _allowedExtensions = [
  'pdf', 'epub', 'zip', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'csv', //
  'jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm', 'mp3', 'm4a', 'aac', 'wav', 'ogg',
];

/// Create or edit a digital product: details, cover, files, publish.
/// `productId == null` creates a new product (saved as a draft first).
class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({super.key, this.productId});

  final String? productId;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  DigitalProduct? _product;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.productId != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await sl<StoreRepository>().myProduct(widget.productId!);
      if (mounted) setState(() => _product = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.productId == null && _product == null ? 'New product' : 'Edit product';
    return ActionScope(
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _EditorBody(product: _product, onChanged: (p) => setState(() => _product = p)),
      ),
    );
  }
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({required this.product, required this.onChanged});

  final DigitalProduct? product;
  final ValueChanged<DigitalProduct> onChanged;

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.product?.title ?? '');
  late final _description = TextEditingController(text: widget.product?.description ?? '');
  late final _price = TextEditingController(text: widget.product == null || widget.product!.isFree ? '' : Fmt.paiseToRupeesInput(widget.product!.price));
  late String _category = widget.product?.category ?? 'ebook';
  late bool _free = widget.product?.isFree ?? false;

  // Upload in progress
  String? _uploadingName;
  double _progress = 0;
  CancelToken? _cancel;

  DigitalProduct? get _p => widget.product;
  StoreRepository get _repo => sl<StoreRepository>();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _cancel?.cancel();
    super.dispose();
  }

  int? get _pricePaise => _free ? 0 : Fmt.rupeesToPaise(_price.text);

  bool get _dirty {
    final p = _p;
    if (p == null) return true;
    return p.title != _title.text.trim() || p.description != _description.text.trim() || p.category != _category || p.price != (_pricePaise ?? -1);
  }

  Future<void> _saveDetails() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final price = _pricePaise!;
    final result = await context.read<ActionCubit>().run(
      'save',
          () => _p == null
          ? _repo.createProduct(title: _title.text.trim(), price: price, description: _description.text.trim(), category: _category)
          : _repo.updateProduct(_p!.id, title: _title.text.trim(), price: price, description: _description.text.trim(), category: _category),
    );
    if (result != null && mounted) {
      widget.onChanged(result);
      AppSnackbar.success(context, _p == null ? 'Draft saved — now add a cover and files' : 'Saved');
    }
  }

  Future<void> _pickCover() async {
    final image = await sl<MediaPicker>().image();
    if (image == null || !mounted) return;
    final result = await context.read<ActionCubit>().run('cover', () => _repo.uploadCover(_p!.id, image));
    if (result != null && mounted) widget.onChanged(result);
  }

  Future<void> _addFile() async {
    if (_p!.files.length >= _maxFiles) {
      AppSnackbar.error(context, 'A product can have up to $_maxFiles files');
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: _allowedExtensions);
    final picked = result?.files.single;
    if (picked?.path == null || !mounted) return;
    final size = await File(picked!.path!).length();
    if (size > _maxFileBytes) {
      if (mounted) AppSnackbar.error(context, 'Each file can be up to 500 MB');
      return;
    }

    setState(() {
      _uploadingName = picked.name;
      _progress = 0;
      _cancel = CancelToken();
    });
    try {
      final updated = await _repo.uploadProductFile(
        _p!.id,
        PickedMedia(path: picked.path!, name: picked.name),
        cancelToken: _cancel,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onChanged(updated);
      AppSnackbar.success(context, 'File added');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) {
        setState(() {
          _uploadingName = null;
          _cancel = null;
        });
      }
    }
  }

  Future<void> _removeFile(ProductFile file) async {
    final ok = await confirmAction(context, title: 'Remove ${file.name}?', message: 'Buyers who already own this product keep it.', confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    final result = await context.read<ActionCubit>().run('file-${file.id}', () => _repo.removeFile(_p!.id, file.id));
    if (result != null && mounted) widget.onChanged(result);
  }

  Future<void> _previewFile(ProductFile file) async {
    final url = await context.read<ActionCubit>().run('preview', () => _repo.previewFileUrl(_p!.id, file.id));
    if (url != null) await LinkOpener.open(url);
  }

  Future<void> _togglePublish() async {
    if (_dirty) {
      AppSnackbar.info(context, 'Save your changes first');
      return;
    }
    final live = _p!.status == ProductStatus.published;
    final result = await context.read<ActionCubit>().run('publish', () => live ? _repo.unpublish(_p!.id) : _repo.publish(_p!.id));
    if (result != null && mounted) {
      widget.onChanged(result);
      HapticFeedback.mediumImpact();
      AppSnackbar.success(context, live ? 'Hidden from your store' : 'Your product is live 🎉');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(context, title: 'Delete this product?', message: 'This can’t be undone.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !mounted) return;
    final done = await context.read<ActionCubit>().run('delete', () async {
      await _repo.deleteProduct(_p!.id);
      return true;
    });
    if (done == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy || _uploadingName != null;
    final p = _p;
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
        children: [
          if (p != null) ...[
            Row(
              children: [
                ProductStatusChip(status: p.status),
                const Spacer(),
                if (p.salesCount > 0) Text('${p.salesCount} sold · ${Fmt.money(p.revenue)}', style: context.text.bodySmall),
              ],
            ),
            if (p.status == ProductStatus.removed && p.removedReason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Removed by Fanitt: ${p.removedReason}', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            // Cover — same shape and look as the product card on Home.
            ListenableBuilder(
              listenable: Listenable.merge([_title, _price]),
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.productCover,
                url: p.coverUrl.isEmpty ? null : p.coverUrl,
                enabled: !busy,
                onPick: _pickCover,
                previewBuilder: (context, image) => ProductCardPreview(
                  image: image,
                  title: _title.text.trim(),
                  category: _category,
                  free: _free,
                  pricePaise: _pricePaise,
                  storeName: p.storeName,
                  storeLogoUrl: p.storeLogoUrl,
                  sold: p.salesCount,
                  fileCount: p.files.length,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Details
          AppTextField(
            label: 'Title',
            hint: 'e.g. 50 Canva templates for reels',
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter at least 3 characters' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Description',
            hint: 'What’s inside, who it’s for, what they’ll get',
            controller: _description,
            minLines: 4,
            maxLines: 10,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppDropdown<String>(
            label: 'Category',
            items: productCategories.keys.toList(),
            value: _category,
            labelOf: (k) => productCategories[k]!,
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _free,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _free = v),
            title: Text('Free product', style: context.text.titleSmall),
            subtitle: Text('Great for lead magnets and samples', style: context.text.bodySmall),
          ),
          if (!_free)
            AppTextField(
              label: 'Price (₹)',
              hint: '499',
              controller: _price,
              prefixIcon: AppIcons.rupee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final paise = Fmt.rupeesToPaise(v ?? '');
                if (paise == null || paise <= 0) return 'Enter a price, or turn on Free';
                if (paise > 10000000) return 'Maximum ₹1,00,000';
                return null;
              },
            ),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(
            label: p == null ? 'Save draft' : 'Save changes',
            isLoading: context.watch<ActionCubit>().state.busyKey == 'save',
            onPressed: busy || (p != null && !_dirty) ? null : _saveDetails,
          ),

          if (p != null) ...[
            const SizedBox(height: AppSpacing.xl),
            FieldLabel('Files (${p.files.length}/$_maxFiles)'),
            Text('Buyers download these after paying. Up to 500 MB each.', style: context.text.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, f) in p.files.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(AppIcons.fileText, color: palette.textSecondary, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                            Text(fileSizeLabel(f.size), style: context.text.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(tooltip: 'Open', onPressed: busy ? null : () => _previewFile(f), icon: Icon(AppIcons.download, size: 18, color: palette.textSecondary)),
                      IconButton(tooltip: 'Remove', onPressed: busy ? null : () => _removeFile(f), icon: Icon(AppIcons.trash, size: 18, color: palette.textSecondary)),
                    ],
                  ),
                ).animate(delay: (40 * i).ms).fadeIn(duration: 250.ms),
              ),
            if (_uploadingName != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text('Uploading $_uploadingName', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
                        Text('${(_progress * 100).round()}%', style: context.text.labelMedium),
                        TextButton(onPressed: () => _cancel?.cancel(), child: const Text('Cancel')),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _progress, minHeight: 6, color: AppColors.primary, backgroundColor: palette.surfaceMuted),
                    ),
                  ],
                ),
              )
            else if (p.files.length < _maxFiles)
              AppButton.secondary(label: 'Add a file', icon: AppIcons.upload, onPressed: busy ? null : _addFile),

            const SizedBox(height: AppSpacing.xl),
            if (p.status != ProductStatus.removed)
              AppButton(
                label: p.status == ProductStatus.published ? 'Hide from store' : 'Publish',
                icon: p.status == ProductStatus.published ? AppIcons.eyeOff : AppIcons.sparkle,
                variant: p.status == ProductStatus.published ? AppButtonVariant.secondary : AppButtonVariant.primary,
                isLoading: context.watch<ActionCubit>().state.busyKey == 'publish',
                onPressed: busy ? null : _togglePublish,
              ),
            if (p.status != ProductStatus.published && p.status != ProductStatus.removed) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('To publish: a cover, a description of 20+ characters and at least one file.', textAlign: TextAlign.center, style: context.text.bodySmall),
            ],
            if (p.salesCount == 0) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: busy ? null : _delete,
                icon: const Icon(AppIcons.trash, color: AppColors.error, size: 18),
                label: const Text('Delete product', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The Home product card drawn over the cover, so the creator sees exactly
/// how the product will look in the app while uploading.
class ProductCardPreview extends StatelessWidget {
  const ProductCardPreview({
    super.key,
    required this.image,
    required this.title,
    required this.category,
    required this.free,
    required this.pricePaise,
    this.storeName = '',
    this.storeLogoUrl = '',
    this.sold = 0,
    this.fileCount = 0,
  });

  final Widget image;
  final String title;
  final String category;
  final bool free;
  final int? pricePaise;
  final String storeName;
  final String storeLogoUrl;
  final int sold;
  final int fileCount;

  static const _shade = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x4D000000), Color(0x00000000), Color(0x8C000000), Color(0xE0000000), Color(0xFA000000)],
        stops: [0, 0.22, 0.48, 0.74, 1],
      ),
    ),
  );

  static Widget _chip(String label, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 11, color: Colors.white), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final name = storeName.isEmpty ? 'Your store' : storeName;
    final priceLabel = free ? 'FREE' : (pricePaise == null || pricePaise! <= 0 ? '₹ —' : Fmt.money(pricePaise!));
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        _shade,
        Positioned(
          left: 10,
          right: 10,
          top: 10,
          child: Row(children: [Flexible(child: _chip(productCategories[category] ?? 'Other'))]),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: free ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                  color: free ? AppColors.success : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(priceLabel, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 8),
              Text(
                title.isEmpty ? 'Your product title shows here' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: title.isEmpty ? Colors.white70 : Colors.white, fontSize: 15, fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -0.2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  StoreLogo(name: name, url: storeLogoUrl, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  sold > 0
                      ? Text('${Fmt.compact(sold)} bought', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700))
                      : _chip('NEW', icon: AppIcons.sparkle),
                  const Spacer(),
                  if (fileCount > 0) ...[
                    const Icon(AppIcons.file, size: 13, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text('$fileCount ${fileCount == 1 ? 'file' : 'files'}', style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}