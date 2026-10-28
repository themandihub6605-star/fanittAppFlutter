// File: lib/features/store/presentation/creator/my_products_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

enum _Filter { all, live, drafts, hidden }

/// The creator's digital products: totals on top, filter, then the grid.
/// Calm look — white cards, orange only for the "New" action.
class MyProductsScreen extends StatefulWidget {
  const MyProductsScreen({super.key});

  @override
  State<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends State<MyProductsScreen> {
  final _cubit = LoadCubit<List<DigitalProduct>>(sl<StoreRepository>().myProducts);
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _open(String route) async {
    HapticFeedback.selectionClick();
    await context.push(route);
    if (mounted) _cubit.refresh();
  }

  bool _matches(DigitalProduct p) => switch (_filter) {
    _Filter.all => true,
    _Filter.live => p.status == ProductStatus.published,
    _Filter.drafts => p.status == ProductStatus.draft,
    _Filter.hidden => p.status == ProductStatus.unpublished || p.status == ProductStatus.removed,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocProvider.value(
      value: _cubit,
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<DigitalProduct>>>();
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: const Text('Digital products', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              actions: [
                TextButton.icon(
                  onPressed: () => _open(AppRoutes.storeProductEditor()),
                  icon: const Icon(AppIcons.plus, size: 18, color: AppColors.primary),
                  label: const Text('New', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
              ],
            ),
            body: AsyncView<List<DigitalProduct>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (products) {
                if (products.isEmpty) {
                  return AppRefresh(
                    onRefresh: cubit.refresh,
                    child: ScrollableMessage(
                      child: MessageView(
                        icon: AppIcons.package,
                        title: 'No products yet',
                        message: 'Sell courses, ebooks, templates, presets and more. Buyers get them instantly.',
                        action: AppButton(label: 'Create your first product', expand: false, onPressed: () => _open(AppRoutes.storeProductEditor())),
                      ),
                    ),
                  );
                }
                final shown = products.where(_matches).toList();
                final counts = {for (final f in _Filter.values) f: products.where((p) => switch (f) {
                  _Filter.all => true,
                  _Filter.live => p.status == ProductStatus.published,
                  _Filter.drafts => p.status == ProductStatus.draft,
                  _Filter.hidden => p.status == ProductStatus.unpublished || p.status == ProductStatus.removed,
                }).length};
                return AppRefresh(
                  onRefresh: cubit.refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
                          child: _Totals(products: products).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 56,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter, 6),
                            children: [
                              for (final f in _Filter.values)
                                if (f == _Filter.all || counts[f]! > 0)
                                  _Chip(
                                    label: switch (f) {
                                      _Filter.all => 'All',
                                      _Filter.live => 'Live',
                                      _Filter.drafts => 'Drafts',
                                      _Filter.hidden => 'Hidden',
                                    },
                                    count: counts[f]!,
                                    selected: _filter == f,
                                    onTap: () => setState(() => _filter = f),
                                  ),
                            ],
                          ),
                        ),
                      ),
                      if (shown.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: Text('Nothing here', style: TextStyle(color: palette.textSecondary))),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 100),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: AppSpacing.sm, crossAxisSpacing: AppSpacing.sm, childAspectRatio: 0.66),
                            itemCount: shown.length,
                            itemBuilder: (context, i) => ProductTile(
                              product: shown[i],
                              index: i,
                              showStatus: true,
                              onTap: () => _open(AppRoutes.storeProductEditor(shown[i].id)),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Products · Sales · Earned · Views — one white card, four columns.
class _Totals extends StatelessWidget {
  const _Totals({required this.products});

  final List<DigitalProduct> products;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final live = products.where((p) => p.status == ProductStatus.published).length;
    final sales = products.fold<int>(0, (a, p) => a + p.salesCount);
    final revenue = products.fold<int>(0, (a, p) => a + p.revenue);
    final views = products.fold<int>(0, (a, p) => a + p.views);
    Widget cell(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: palette.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
        ],
      ),
    );
    Widget gap() => Container(width: 1, height: 30, color: palette.border);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          cell('$live/${products.length}', 'Live'),
          gap(),
          cell(Fmt.compact(sales), 'Sales'),
          gap(),
          cell(revenue == 0 ? '₹0' : Fmt.money(revenue), 'Earned'),
          gap(),
          cell(Fmt.compact(views), 'Views'),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: context.isDark ? 0.2 : 0.08) : palette.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.primary.withValues(alpha: 0.5) : palette.border),
          ),
          child: Text(
            '$label  $count',
            style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? AppColors.primary : palette.textPrimary),
          ),
        ),
      ),
    );
  }
}