import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/models/common_models.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/shop_repository.dart';
import 'shop_widgets.dart';

/// Fanitt Store — every physical product creators sell: search, categories,
/// sort and an endless grid. With [storeId] it shows one store's products.
class ShopHomeScreen extends StatefulWidget {
  const ShopHomeScreen({super.key, this.storeId, this.storeName, this.initialCategory});

  final String? storeId;
  final String? storeName;
  final String? initialCategory;

  @override
  State<ShopHomeScreen> createState() => _ShopHomeScreenState();
}

class _ShopHomeScreenState extends State<ShopHomeScreen> {
  static const _sorts = <String, String>{
    'popular': 'Popular',
    'new': 'Newest',
    'price_low': 'Price: low to high',
    'price_high': 'Price: high to low',
  };

  final _search = TextEditingController();
  Timer? _debounce;
  late String? _category = widget.initialCategory;
  String _sort = 'popular';
  late final PagedCubit<ShopProduct> _cubit = PagedCubit<ShopProduct>(_fetch);

  @override
  void initState() {
    super.initState();
    ShopRepository.i.refreshCartCount();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<Paged<ShopProduct>> _fetch(int page) =>
      ShopRepository.i.products(page: page, category: _category, search: _search.text, sort: _sort, storeId: widget.storeId);

  void _reload() => _cubit.updateQuery(_fetch);

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.xs),
              child: Align(alignment: Alignment.centerLeft, child: Text('Sort by', style: ctx.text.titleMedium)),
            ),
            for (final e in _sorts.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == _sort ? const Icon(AppIcons.check, color: AppColors.primary) : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (picked != null && picked != _sort) {
      setState(() => _sort = picked);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final title = widget.storeId == null ? 'Fanitt Store' : (widget.storeName?.isNotEmpty ?? false ? widget.storeName! : 'Store products');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(tooltip: 'My orders', icon: const Icon(ShopIcons.orders), onPressed: () => context.push(AppRoutes.shopOrders)),
          const CartIconButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Search + sort
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search clothes, merch, accessories…',
                        prefixIcon: const Icon(AppIcons.search, size: 20),
                        contentPadding: EdgeInsets.zero,
                        suffixIcon: ListenableBuilder(
                          listenable: _search,
                          builder: (context, _) => _search.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                            icon: const Icon(AppIcons.close, size: 18),
                            onPressed: () {
                              _search.clear();
                              _reload();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _pickSort,
                    icon: const Icon(AppIcons.sliders, size: 18),
                    label: const Text('Sort'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textPrimary,
                      side: BorderSide(color: palette.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Categories
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 4),
              children: [
                _CategoryChip(label: 'All', selected: _category == null, onTap: () {
                  setState(() => _category = null);
                  _reload();
                }),
                for (final e in shopCategories.entries)
                  _CategoryChip(
                    label: e.value,
                    selected: _category == e.key,
                    onTap: () {
                      setState(() => _category = _category == e.key ? null : e.key);
                      _reload();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _ProductGrid(cubit: _cubit)),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.primary : palette.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : palette.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : palette.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.cubit});

  final PagedCubit<ShopProduct> cubit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PagedCubit<ShopProduct>, PagedState<ShopProduct>>(
      bloc: cubit,
      builder: (context, state) {
        if (!state.hasLoaded && state.errorMessage == null) return const LoadingView();
        if (state.items.isEmpty && state.errorMessage != null) return ErrorView(message: state.errorMessage!, onRetry: cubit.refresh);
        return AppRefresh(
          onRefresh: cubit.refresh,
          child: state.items.isEmpty
              ? const ScrollableMessage(
            child: MessageView(icon: ShopIcons.bag, title: 'No products found', message: 'Try another category or search.'),
          )
              : NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 500) cubit.loadMore();
              return false;
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.md),
                  sliver: SliverGrid.builder(
                    gridDelegate: shopGridDelegate,
                    itemCount: state.items.length,
                    itemBuilder: (context, i) => ShopProductCard(product: state.items[i], index: i),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    child: Center(
                      child: state.isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : state.errorMessage != null
                          ? TextButton(onPressed: () => cubit.loadMore(force: true), child: const Text('Couldn’t load more — tap to retry'))
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}