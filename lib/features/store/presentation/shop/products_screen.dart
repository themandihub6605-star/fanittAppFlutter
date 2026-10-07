import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/share_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

const _sorts = {'new': 'Newest', 'popular': 'Best selling', 'price_low': 'Price: low to high', 'price_high': 'Price: high to low'};

/// Marketplace: every digital product from every creator store.
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PagedCubit<DigitalProduct>((page) => sl<StoreRepository>().products(category: initialCategory, page: page)),
      child: _ProductsView(initialCategory: initialCategory),
    );
  }
}

class _ProductsView extends StatefulWidget {
  const _ProductsView({this.initialCategory});

  final String? initialCategory;

  @override
  State<_ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<_ProductsView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  late String? _category = widget.initialCategory;
  String? _price; // free | paid
  String _sort = 'new';

  PagedCubit<DigitalProduct> get _cubit => context.read<PagedCubit<DigitalProduct>>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _cubit.loadMore();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    final repo = sl<StoreRepository>();
    final search = _search.text.trim();
    _cubit.updateQuery((page) => repo.products(search: search, category: _category, price: _price, sort: _sort, page: page));
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _openFilters() async {
    final picked = await showAppSheet<({String sort, String? price})>(context, builder: (_) => _FilterSheet(sort: _sort, price: _price));
    if (picked == null) return;
    setState(() {
      _sort = picked.sort;
      _price = picked.price;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = context.watch<PagedCubit<DigitalProduct>>().state;
    final filtersOn = _price != null || _sort != 'new';

    return Scaffold(
      appBar: AppBar(title: const Text('All products')),
      body: Column(
        children: [
          // Search + filter
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search courses, ebooks, templates…',
                      prefixIcon: const Icon(AppIcons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: palette.border)),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Material(
                      color: filtersOn ? AppColors.primary : palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _openFilters,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: filtersOn ? AppColors.primary : palette.border)),
                          child: Icon(AppIcons.sliders, size: 20, color: filtersOn ? Colors.white : palette.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Categories
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.xs),
              children: [
                for (final entry in [const MapEntry<String?, String>(null, 'All'), ...productCategories.entries.map((e) => MapEntry<String?, String>(e.key, e.value))])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _category == entry.key,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(color: _category == entry.key ? Colors.white : palette.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _category = entry.key);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: state.isFirstLoad
                ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xl),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 250),
              itemCount: 6,
              itemBuilder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(16)),
              ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6)),
            )
                : state.items.isEmpty
                ? AppRefresh(
              onRefresh: () async => _reload(),
              child: const ScrollableMessage(
                child: MessageView(icon: AppIcons.package, title: 'No products found', message: 'Try another search, category or filter.'),
              ),
            )
                : AppRefresh(
              onRefresh: () async => _reload(),
              child: GridView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xl),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 250),
                itemCount: state.items.length + (state.hasMore ? 2 : 0),
                itemBuilder: (context, i) {
                  if (i >= state.items.length) {
                    return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  return MarketProductCard(product: state.items[i], index: i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product card for the marketplace: cover, price, title and which store sells it.
class MarketProductCard extends StatefulWidget {
  const MarketProductCard({super.key, required this.product, this.index = 0, this.width});

  final DigitalProduct product;
  final int index;
  final double? width;

  @override
  State<MarketProductCard> createState() => _MarketProductCardState();
}

class _MarketProductCardState extends State<MarketProductCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final palette = context.palette;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(AppRoutes.storeProduct(p.id));
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    StoreImage(url: p.coverUrl, icon: AppIcons.package),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                        child: Text(p.categoryLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: ShareIconButton(
                        onDark: true,
                        size: 28,
                        message: () => ShareService.product(id: p.id, title: p.title, store: p.storeName.isEmpty ? 'a Fanitt creator' : p.storeName, price: p.price, category: p.categoryLabel),
                      ),
                    ),
                    if (p.salesCount >= 10)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(6)),
                          child: const Text('🔥 Bestseller', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(
                  children: [
                    if (p.storeName.isNotEmpty) ...[
                      StoreLogo(name: p.storeName, url: p.storeLogoUrl, size: 18),
                      const SizedBox(width: 5),
                      Expanded(child: Text(p.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11))),
                    ] else
                      const Spacer(),
                    const SizedBox(width: 4),
                    Text(
                      p.owned ? 'Owned' : (p.isFree ? 'Free' : Fmt.money(p.price)),
                      style: TextStyle(
                        color: p.owned || p.isFree ? AppColors.success : AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (30 * (widget.index % 10)).ms).fadeIn(duration: 260.ms).slideY(begin: 0.05);
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.sort, required this.price});

  final String sort;
  final String? price;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _sort = widget.sort;
  late String? _price = widget.price;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget option(String label, bool selected, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : palette.border),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.text.titleSmall)),
            if (selected) const Icon(AppIcons.checkCircle, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
    return SheetBody(
      title: 'Sort & filter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sort by', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final e in _sorts.entries) option(e.value, _sort == e.key, () => setState(() => _sort = e.key)),
          const SizedBox(height: 10),
          Text('Price', style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          option('Any price', _price == null, () => setState(() => _price = null)),
          option('Free only', _price == 'free', () => setState(() => _price = 'free')),
          option('Paid only', _price == 'paid', () => setState(() => _price = 'paid')),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.of(context).pop((sort: _sort, price: _price)),
            child: const Text('Show products', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop((sort: 'new', price: null)),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}