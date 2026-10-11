import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/shop_repository.dart';
import 'shop_widgets.dart';

/// A creator's store page: their physical products (first 4 + See all).
/// Shows nothing when the store has none.
class StoreShopSection extends StatefulWidget {
  const StoreShopSection({super.key, required this.storeId, required this.storeName});

  final String storeId;
  final String storeName;

  @override
  State<StoreShopSection> createState() => _StoreShopSectionState();
}

class _StoreShopSectionState extends State<StoreShopSection> {
  List<ShopProduct>? _items;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await ShopRepository.i.products(storeId: widget.storeId, limit: 4, sort: 'popular');
      if (mounted) {
        setState(() {
          _items = page.items;
          _total = page.total;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Shop', style: context.text.titleLarge)),
              if (_total > items.length)
                TextButton(
                  onPressed: () => context.push(AppRoutes.shopBrowse(storeId: widget.storeId, storeName: widget.storeName)),
                  child: Text('See all $_total'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: shopGridDelegate,
            itemCount: items.length,
            itemBuilder: (context, i) => ShopProductCard(product: items[i], index: i, showStore: false),
          ),
        ],
      ),
    );
  }
}