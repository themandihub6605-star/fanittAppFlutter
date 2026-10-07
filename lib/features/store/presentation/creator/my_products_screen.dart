import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// The creator's digital products.
class MyProductsScreen extends StatelessWidget {
  const MyProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<DigitalProduct>>(sl<StoreRepository>().myProducts),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<DigitalProduct>>>();
          Future<void> open(String route) async {
            await context.push(route);
            if (context.mounted) cubit.refresh();
          }

          return Scaffold(
            appBar: AppBar(title: const Text('My products')),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'new-product',
              onPressed: () => open(AppRoutes.storeProductEditor()),
              icon: const Icon(AppIcons.plus),
              label: const Text('New product'),
            ).animate().scale(begin: const Offset(0.6, 0.6), duration: 350.ms, curve: Curves.easeOutBack),
            body: AsyncView<List<DigitalProduct>>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (products) => AppRefresh(
                onRefresh: cubit.refresh,
                child: products.isEmpty
                    ? ScrollableMessage(
                        child: MessageView(
                          icon: AppIcons.package,
                          title: 'No products yet',
                          message: 'Sell courses, ebooks, templates, presets and more. Buyers get them instantly.',
                          action: AppButton(label: 'Create your first product', expand: false, onPressed: () => open(AppRoutes.storeProductEditor())),
                        ),
                      )
                    : GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: AppSpacing.sm, crossAxisSpacing: AppSpacing.sm, childAspectRatio: 0.66),
                        itemCount: products.length,
                        itemBuilder: (context, i) => ProductTile(
                          product: products[i],
                          index: i,
                          showStatus: true,
                          onTap: () => open(AppRoutes.storeProductEditor(products[i].id)),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
