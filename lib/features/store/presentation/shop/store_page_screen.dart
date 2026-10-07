import 'package:flutter/material.dart';
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
import '../../../../core/widgets/async_view.dart';
import '../../data/store_repository.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/services/link_opener.dart';
import '../../../../core/services/share_service.dart';
import '../call/request_call_sheet.dart';
import '../fanbox/fanbox_sheet.dart';
import '../meet/meets_section.dart';
import '../widgets/store_widgets.dart';

/// A creator's public store.
class StorePageScreen extends StatelessWidget {
  const StorePageScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<StorePage>(() => sl<StoreRepository>().storePage(slug)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<StorePage>>();
          final page = cubit.state.data;
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              actions: [
                if (page != null)
                  ShareIconButton(
                    onDark: true,
                    size: 40,
                    message: () => ShareService.store(slug: page.store.slug, name: page.store.name, tagline: page.store.tagline, mine: page.isOwner),
                  ),
                const SizedBox(width: 10),
              ],
            ),
            body: AsyncView<StorePage>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (page) => _StoreBody(page: page),
            ),
          );
        },
      ),
    );
  }
}

class _StoreBody extends StatelessWidget {
  const _StoreBody({required this.page});

  final StorePage page;

  @override
  Widget build(BuildContext context) {
    final store = page.store;
    final palette = context.palette;
    final topInset = MediaQuery.paddingOf(context).top;
    final cubit = context.read<LoadCubit<StorePage>>();

    return RefreshIndicator.adaptive(
      color: AppColors.primary,
      edgeOffset: topInset + kToolbarHeight,
      onRefresh: cubit.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200 + topInset,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  StoreImage(url: store.bannerUrl),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent, palette.background],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.gutter,
                    bottom: -30,
                    child: Hero(tag: 'store-logo-${store.id}', child: StoreLogo(name: store.name, url: store.logoUrl, size: 84, borderColor: palette.background)),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 40, AppSpacing.gutter, AppSpacing.md),
            sliver: SliverList.list(
              children: [
                Text(store.name, style: context.text.headlineSmall),
                if (store.tagline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(store.tagline, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                ],
                if (store.about.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(store.about, style: context.text.bodyMedium),
                ],
                if (!store.isOpen) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('This store is not taking orders right now.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
                ],
                if (page.isOwner) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('This is how buyers see your store.', style: context.text.bodySmall?.copyWith(color: AppColors.info)),
                ],
                if (!page.isOwner) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton.secondary(
                    label: 'Send a FanBox',
                    icon: AppIcons.gift,
                    height: 44,
                    onPressed: () => showFanBoxSheet(context, storeId: store.id, creatorName: store.name, config: page.fanbox),
                  ),
                ],
                if (page.calls.enabled && !page.isOwner) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _CallCard(page: page),
                ],
                if (page.lives.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Lives', style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: page.lives.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (context, i) => LiveCard(live: page.lives[i]),
                    ),
                  ),
                ],
                if (page.meets.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Virtual Meets', style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  MeetsSection(meets: page.meets, isOwner: page.isOwner),
                ],
                if (!page.affiliate.isEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text('Recommended by ${store.name}', style: context.text.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  _AffiliateSection(storefront: page.affiliate),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text('Digital products', style: context.text.titleLarge),
              ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.05),
            ),
          ),
          if (page.products.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.huge),
                child: MessageView(icon: AppIcons.package, title: 'Nothing here yet', message: 'New products will show up here.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.huge),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: AppSpacing.sm, crossAxisSpacing: AppSpacing.sm, childAspectRatio: 0.72),
                itemCount: page.products.length,
                itemBuilder: (context, i) => ProductTile(
                  product: page.products[i],
                  index: i,
                  onTap: () async {
                    await context.push(AppRoutes.storeProduct(page.products[i].id));
                    if (context.mounted) cubit.refresh();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class _CallCard extends StatelessWidget {
  const _CallCard({required this.page});

  final StorePage page;

  @override
  Widget build(BuildContext context) {
    final info = page.calls;
    final palette = context.palette;
    final available = info.online && !info.busy && page.store.isOpen;
    final rates = [
      if (info.audioEnabled) 'Audio ${info.audioRate == 0 ? 'free' : '${Fmt.money(info.audioRate)}/min'}',
      if (info.videoEnabled) 'Video ${info.videoRate == 0 ? 'free' : '${Fmt.money(info.videoRate)}/min'}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: available ? AppColors.success.withValues(alpha: 0.5) : palette.border),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              const Icon(AppIcons.phone, color: AppColors.primary, size: 28),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: available ? AppColors.success : palette.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(available ? 'Available for a call' : (info.busy ? 'On another call' : 'Offline right now'), style: context.text.titleSmall),
                Text(rates, style: context.text.bodySmall),
              ],
            ),
          ),
          AppButton(
            label: 'Call',
            expand: false,
            height: 40,
            onPressed: available ? () => showRequestCallSheet(context, store: page.store, info: info) : null,
          ),
        ],
      ),
    );
  }
}


/// Affiliate picks: collections first, then everything else. Tapping opens
/// the shop through Fanitt's tracking link.
class _AffiliateSection extends StatelessWidget {
  const _AffiliateSection({required this.storefront});

  final AffiliateStorefront storefront;

  @override
  Widget build(BuildContext context) {
    final inCollections = {for (final c in storefront.collections) ...c.products.map((p) => p.id)};
    final others = storefront.products.where((p) => !inCollections.contains(p.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in storefront.collections.where((c) => c.products.isNotEmpty)) ...[
          Text(c.title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          _AffiliateRow(products: c.products),
          const SizedBox(height: AppSpacing.md),
        ],
        if (others.isNotEmpty) _AffiliateRow(products: others),
      ],
    );
  }
}

class _AffiliateRow extends StatelessWidget {
  const _AffiliateRow({required this.products});

  final List<AffiliateProduct> products;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final p = products[i];
          return SizedBox(
            width: 140,
            child: Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => LinkOpener.open(StoreRepository.goUrl(p.goPath)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: ColoredBox(color: Colors.white, child: SizedBox.expand(child: StoreImage(url: p.imageUrl, icon: AppIcons.link, fit: BoxFit.contain)))),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelMedium),
                          const SizedBox(height: 2),
                          Text(
                            [if (p.price != null) Fmt.money(p.price!), if (p.merchant.isNotEmpty) p.merchant].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall?.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}