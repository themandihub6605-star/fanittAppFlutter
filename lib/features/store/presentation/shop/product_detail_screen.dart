import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/services/share_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import '../widgets/store_checkout.dart';
import '../widgets/store_widgets.dart';

/// Product page with Buy / Get for free, and downloads once owned.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<ProductPage>(() => sl<StoreRepository>().productPage(productId)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<ProductPage>>();
          final page = cubit.state.data;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Product'),
              actions: [
                if (page != null)
                  ShareIconButton(
                    size: 44,
                    message: () => ShareService.product(
                      id: page.product.id,
                      title: page.product.title,
                      store: page.store.name,
                      price: page.product.price,
                      category: page.product.categoryLabel,
                      mine: page.isOwner,
                    ),
                  ),
                const SizedBox(width: 4),
              ],
            ),
            body: AsyncView<ProductPage>(state: cubit.state, onRetry: cubit.load, builder: (p) => _Body(page: p)),
            bottomNavigationBar: page == null || page.isOwner ? null : _BuyBar(page: page),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.page});

  final ProductPage page;

  Future<void> _download(BuildContext context, ProductFile file) async {
    try {
      final url = await sl<StoreRepository>().downloadUrl(page.product.id, file.id);
      await LinkOpener.open(url);
    } on ApiException catch (e) {
      if (context.mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = page.product;
    final palette = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(aspectRatio: 16 / 10, child: StoreImage(url: p.coverUrl, icon: AppIcons.package)),
        ).animate().fadeIn(duration: 350.ms).scaleXY(begin: 0.97, curve: Curves.easeOutCubic),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            PriceTag(price: p.price, owned: page.owned),
            const SizedBox(width: AppSpacing.xs),
            Text('${p.categoryLabel} · ${p.files.length} file${p.files.length == 1 ? '' : 's'} · ${fileSizeLabel(p.totalSize)}', style: context.text.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(p.title, style: context.text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        InkWell(
          onTap: () => context.push(AppRoutes.storePage(page.store.slug)),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                StoreLogo(name: page.store.name, url: page.store.logoUrl, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(page.store.name, style: context.text.titleSmall)),
                Icon(AppIcons.chevronRight, size: 16, color: palette.textTertiary),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (p.description.isNotEmpty) Text(p.description, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.5)),
        const SizedBox(height: AppSpacing.lg),
        Text(page.owned ? 'Your files' : 'What you get', style: context.text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final f in p.files)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
              child: Row(
                children: [
                  Icon(AppIcons.fileText, size: 20, color: palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                  Text(fileSizeLabel(f.size), style: context.text.bodySmall),
                  if (page.owned)
                    IconButton(tooltip: 'Download', onPressed: () => _download(context, f), icon: const Icon(AppIcons.download, color: AppColors.primary, size: 20))
                  else
                    const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BuyBar extends StatefulWidget {
  const _BuyBar({required this.page});

  final ProductPage page;

  @override
  State<_BuyBar> createState() => _BuyBarState();
}

class _BuyBarState extends State<_BuyBar> {
  bool _busy = false;

  Future<void> _buy() async {
    final p = widget.page.product;
    setState(() => _busy = true);
    final order = await payForStoreItem(
      context,
      amount: p.price,
      title: p.title,
      start: (payWith) => sl<StoreRepository>().checkoutProduct(p.id, payWith: payWith),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order == null) return;
    context.read<LoadCubit<ProductPage>>().replace(widget.page.copyWith(owned: true));
    await showAppSheet<void>(
      context,
      builder: (ctx) => SheetBody(
        title: p.isFree ? 'It’s yours!' : 'Payment successful',
        subtitle: order.invoiceNumber.isEmpty ? null : 'Invoice ${order.invoiceNumber}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(AppIcons.checkCircle, color: AppColors.success, size: 64).animate().scale(begin: const Offset(0.3, 0.3), duration: 450.ms, curve: Curves.easeOutBack),
            const SizedBox(height: AppSpacing.md),
            Text('“${p.title}” is in your library. Download it any time.', textAlign: TextAlign.center, style: ctx.text.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Open my library',
              icon: AppIcons.library,
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push(AppRoutes.library);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton.secondary(label: 'Done', onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final p = page.product;
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.sm),
          child: page.owned
              ? AppButton(label: 'Open in my library', icon: AppIcons.library, onPressed: () => context.push(AppRoutes.library))
              : Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.isFree ? 'Free' : Fmt.money(p.price), style: context.text.titleLarge),
                    Text('Instant download', style: context.text.bodySmall),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                child: AppButton(
                  label: p.isFree ? 'Get it free' : 'Buy now',
                  isLoading: _busy,
                  onPressed: _busy || !page.store.isOpen ? null : _buy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}