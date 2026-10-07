import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/link_opener.dart';
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
import '../widgets/store_widgets.dart';

/// Everything the user bought in Fanitt Store, with downloads and invoices.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.showBack = true});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<LibraryItem>>(sl<StoreRepository>().library),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<LibraryItem>>>();
          return Scaffold(
            appBar: AppBar(automaticallyImplyLeading: showBack, title: const Text('My library')),
            body: AsyncView<List<LibraryItem>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (items) => AppRefresh(
                onRefresh: cubit.refresh,
                child: items.isEmpty
                    ? ScrollableMessage(
                        child: MessageView(
                          icon: AppIcons.library,
                          title: 'Your library is empty',
                          message: 'Products you buy from creators show up here.',
                          action: AppButton(label: 'Explore stores', expand: false, onPressed: () => context.push(AppRoutes.stores)),
                        ),
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) => _LibraryCard(item: items[i]).animate(delay: (40 * i.clamp(0, 10)).ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LibraryCard extends StatefulWidget {
  const _LibraryCard({required this.item});

  final LibraryItem item;

  @override
  State<_LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<_LibraryCard> {
  bool _open = false;
  String? _downloading;

  Future<void> _download(ProductFile f) async {
    setState(() => _downloading = f.id);
    try {
      final url = await sl<StoreRepository>().downloadUrl(widget.item.product.id, f.id);
      await LinkOpener.open(url);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _invoice() async {
    try {
      final inv = await sl<StoreRepository>().invoice(widget.item.orderId);
      if (!mounted) return;
      await showAppSheet<void>(
        context,
        builder: (ctx) => SheetBody(
          title: 'Invoice',
          subtitle: inv.invoiceNumber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyValueRow(label: 'Item', value: inv.itemTitle),
              KeyValueRow(label: 'Sold by', value: inv.sellerName),
              KeyValueRow(label: 'Billed to', value: inv.buyerName),
              if (inv.date != null) KeyValueRow(label: 'Date', value: Fmt.date(inv.date!.toLocal())),
              if (inv.paymentId.isNotEmpty) KeyValueRow(label: 'Payment ID', value: inv.paymentId),
              KeyValueRow(label: 'Status', value: inv.status == 'refunded' ? 'Refunded' : 'Paid'),
              const Divider(height: AppSpacing.lg),
              KeyValueRow(label: 'Total', value: inv.amount == 0 ? 'Free' : Fmt.money(inv.amount), emphasize: true),
              const SizedBox(height: AppSpacing.lg),
              AppButton.secondary(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final p = item.product;
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(width: 64, height: 64, child: StoreImage(url: p.coverUrl, icon: AppIcons.package)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${item.storeName}${item.purchasedAt == null ? '' : ' · ${Fmt.date(item.purchasedAt!.toLocal())}'}',
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(AppIcons.caretDown, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!item.available)
                          Text('This product is no longer available.', style: context.text.bodySmall?.copyWith(color: AppColors.warning))
                        else
                          for (final f in p.files)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                              leading: Icon(AppIcons.fileText, color: palette.textSecondary, size: 20),
                              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                              subtitle: Text(fileSizeLabel(f.size), style: context.text.bodySmall),
                              trailing: _downloading == f.id
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : IconButton(tooltip: 'Download', onPressed: () => _download(f), icon: const Icon(AppIcons.download, color: AppColors.primary)),
                            ),
                        Row(
                          children: [
                            TextButton.icon(onPressed: _invoice, icon: const Icon(AppIcons.receipt, size: 16), label: const Text('Invoice')),
                            const Spacer(),
                            if (item.storeSlug.isNotEmpty)
                              TextButton(onPressed: () => context.push(AppRoutes.storePage(item.storeSlug)), child: const Text('Visit store')),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
