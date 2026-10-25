// File: lib/features/store/presentation/creator/store_entry_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/feature_flags.dart';
import '../../../../core/services/share_service.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/image_upload_box.dart';
import '../../data/shop_repository.dart';
import '../../data/store_access.dart';
import '../../data/store_repository.dart';
import '../commerce/shop_widgets.dart';
import '../widgets/store_widgets.dart';
import 'store_setup_screen.dart';

/// Creator's way into Fanitt Store: setup until the store is approved,
/// then the Store Home dashboard — shop (physical products & orders),
/// tools (Meet, Live, Community, Affiliate) and more.
class StoreEntryScreen extends StatelessWidget {
  const StoreEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<StoreRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => LoadCubit<MyStore>(repo.myStore)),
        BlocProvider(create: (_) => LoadCubit<StoreConfig>(repo.config)),
        // Only loaded once the store is live (the dashboard reads it).
        BlocProvider(create: (_) => LoadCubit<StoreSummary>(repo.summary)),
        BlocProvider(create: (_) => LoadCubit<SellerShopSummary>(ShopRepository.i.sellerSummary)),
      ],
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<MyStore>>();
          final data = cubit.state.data;
          if (data != null) StoreAccess.apply(data);
          final active = data?.store?.isActive ?? false;
          return Scaffold(
            appBar: active ? null : AppBar(title: const Text('Fanitt Store')),
            body: AsyncView<MyStore>(
              state: cubit.state,
              onRetry: cubit.load,
              builder: (data) => data.store?.isActive ?? false ? _StoreHome(data: data) : StoreSetupView(data: data),
            ),
          );
        },
      ),
    );
  }
}

class _StoreHome extends StatelessWidget {
  const _StoreHome({required this.data});

  final MyStore data;

  @override
  Widget build(BuildContext context) {
    final store = data.store!;
    final palette = context.palette;
    final config = context.watch<LoadCubit<StoreConfig>>().state.data;
    final summary = context.watch<LoadCubit<StoreSummary>>().state.data;
    final shop = context.watch<LoadCubit<SellerShopSummary>>().state.data;
    // Tools the admin switched off are hidden (all show until settings load).
    bool enabled(String key) => config == null || config.toolCards.any((c) => c.key == key);
    final tools = [for (final t in _tools) if (enabled(t.key)) t];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My store'),
        actions: [
          ShareIconButton(
            size: 44,
            message: () => ShareService.store(slug: store.slug, name: store.name, tagline: store.tagline, mine: true),
          ),
          IconButton(tooltip: 'View my store', icon: const Icon(AppIcons.eye), onPressed: () => context.push(AppRoutes.storePage(store.slug))),
          IconButton(tooltip: 'Store settings', icon: const Icon(AppIcons.gear), onPressed: () => _editStore(context, store)),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: () async {
          await Future.wait([
            context.read<LoadCubit<MyStore>>().refresh(),
            context.read<LoadCubit<StoreConfig>>().refresh(),
            context.read<LoadCubit<StoreSummary>>().refresh(),
            context.read<LoadCubit<SellerShopSummary>>().refresh(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Store: logo, name, open / closed
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(child: _StoreHeader(store: store, onEdit: () => _editStore(context, store))),
            ),

            // Earnings + numbers
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(child: _EarningsCard(store: store, summary: summary).animate().fadeIn(delay: 60.ms, duration: 300.ms)),
            ),

            // Shop — physical products & orders. Hidden while the admin has
            // the Fanitt Store shop switched off.
            ValueListenableBuilder<bool>(
              valueListenable: FeatureFlags.store,
              builder: (context, shopOn, _) => shopOn
                  ? SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
                sliver: SliverToBoxAdapter(child: _ShopCard(summary: shop).animate().fadeIn(delay: 150.ms, duration: 350.ms)),
              )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Tools
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Grow with your fans', style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Go live, host live sessions, sell digital products and take paid calls', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 116),
                itemCount: tools.length,
                itemBuilder: (context, i) => _ToolTile(tool: tools[i], index: i),
              ),
            ),

            // Manage
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xxl),
              sliver: SliverList.list(
                children: [
                  Text('More', style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _ManageTile(icon: AppIcons.chartLine, color: const Color(0xFF00A3A3), title: 'Analytics', subtitle: 'Views, sales, lives, calls and more', onTap: () => context.push(AppRoutes.storeAnalytics)),
                        if (enabled('digital_products'))
                          _ManageTile(icon: AppIcons.receipt, color: AppColors.primary, title: 'Digital sales', subtitle: 'Everyone who bought a digital product', onTap: () => context.push(AppRoutes.storeSales)),
                        if (enabled('fanbox'))
                          _ManageTile(icon: AppIcons.gift, color: const Color(0xFFEC2A78), title: 'FanBox', subtitle: 'Tips your fans sent you', onTap: () => context.push(AppRoutes.storeFanbox)),
                        _ManageTile(icon: AppIcons.wallet, color: AppColors.success, title: 'Wallet & withdrawals', subtitle: 'Store earnings land in your Fanitt wallet', onTap: () => context.push(AppRoutes.wallet)),
                        _ManageTile(icon: AppIcons.gear, color: palette.textSecondary, title: 'Store settings', subtitle: 'Name, logo, banner and opening', onTap: () => _editStore(context, store), last: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStore(BuildContext context, StoreInfo store) async {
    final cubit = context.read<LoadCubit<MyStore>>();
    final updated = await showAppSheet<MyStore>(
      context,
      builder: (_) => SheetActionScope(child: _EditStoreSheet(store: store, onImageChanged: cubit.replace)),
    );
    if (updated != null && context.mounted) {
      context.read<LoadCubit<MyStore>>().replace(updated);
      AppSnackbar.success(context, 'Store updated');
    }
  }
}

/// Banner with glass buttons, logo on its edge, name, tagline and an
/// open/closed switch.
class _StoreHeader extends StatefulWidget {
  const _StoreHeader({required this.store, required this.onEdit});

  final StoreInfo store;
  final VoidCallback onEdit;

  @override
  State<_StoreHeader> createState() => _StoreHeaderState();
}

class _StoreHeaderState extends State<_StoreHeader> {
  bool _busy = false;

  Future<void> _toggleOpen() async {
    setState(() => _busy = true);
    try {
      final updated = await sl<StoreRepository>().updateStore(isOpen: !widget.store.isOpen);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      context.read<LoadCubit<MyStore>>().replace(updated);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final palette = context.palette;
    final open = store.isOpen;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onEdit,
            child: Hero(tag: 'store-logo-${store.id}', child: StoreLogo(name: store.name, url: store.logoUrl, size: 52)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: open ? AppColors.success : AppColors.warning, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        open ? 'Open · taking orders' : 'Closed · not taking orders',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(fontSize: 12.5, color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _busy
              ? const SizedBox(width: 48, height: 24, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
              : Switch.adaptive(value: open, activeTrackColor: AppColors.primary, onChanged: (_) => _toggleOpen()),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

/// Light card: total earned, last 30 days, three numbers and two actions.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.store, required this.summary});

  final StoreInfo store;
  final StoreSummary? summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final monthNet = (summary?.last30Days ?? const []).fold<int>(0, (s, d) => s + d.net);
    final stats = store.stats;
    final conversion = stats.views == 0 ? '—' : '${((stats.orders / stats.views) * 100).clamp(0, 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Total earned', style: context.text.bodySmall?.copyWith(color: palette.textSecondary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text('30 days ${Fmt.money(monthNet)}', style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(Fmt.money(stats.netEarnings), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _Stat(value: Fmt.compact(stats.orders), label: 'Orders'),
                  VerticalDivider(width: 1, thickness: 1, color: palette.border),
                  _Stat(value: Fmt.compact(stats.views), label: 'Views'),
                  VerticalDivider(width: 1, thickness: 1, color: palette.border),
                  _Stat(value: conversion, label: 'Conversion'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.wallet),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(AppIcons.wallet, size: 17),
                  label: const Text('Withdraw', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.storeAnalytics),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.textPrimary,
                    minimumSize: const Size.fromHeight(42),
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(AppIcons.chartLine, size: 17),
                  label: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: 1),
          Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _Tool {
  const _Tool({required this.key, required this.title, required this.subtitle, required this.icon, required this.colors, required this.route});

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String route;
}

const _tools = [
  _Tool(key: 'virtual_meet', title: 'Live session', subtitle: 'Webinars & 1:1 sessions', icon: AppIcons.videoCamera, colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)], route: AppRoutes.sessions),
  _Tool(key: 'stream_live', title: 'Stream Live', subtitle: 'Go live — free or paid', icon: AppIcons.broadcast, colors: [Color(0xFFE53935), Color(0xFFFF7043)], route: AppRoutes.storeLives),
  _Tool(key: 'community', title: 'Community', subtitle: 'Free or paid groups', icon: AppIcons.users, colors: [Color(0xFF00A3A3), Color(0xFF26C6DA)], route: AppRoutes.communities),
  _Tool(key: 'affiliate', title: 'Affiliate store', subtitle: 'Share links you love', icon: AppIcons.link, colors: [Color(0xFFF59E0B), Color(0xFFFFCA28)], route: AppRoutes.storeAffiliate),
  _Tool(key: 'digital_products', title: 'Digital products', subtitle: 'Courses, ebooks & templates', icon: AppIcons.download, colors: [Color(0xFF3949AB), Color(0xFF7986CB)], route: AppRoutes.storeProducts),
  _Tool(key: 'chat_calls', title: 'Paid calls', subtitle: 'Audio & video, per minute', icon: AppIcons.phone, colors: [Color(0xFF1E88E5), Color(0xFF64B5F6)], route: AppRoutes.storeCalls),
];

/// One tool — drawn in the app (icon + gradient), no uploaded images.
class _ToolTile extends StatefulWidget {
  const _ToolTile({required this.tool, required this.index});

  final _Tool tool;
  final int index;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tool;
    final palette = context.palette;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(t.route);
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.colors.first.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(t.icon, color: t.colors.first, size: 20),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  Icon(AppIcons.chevronRight, size: 15, color: palette.textTertiary),
                ],
              ),
              const SizedBox(height: 1),
              Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ),
    ).animate(delay: (60 * widget.index).ms).fadeIn(duration: 280.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}

/// Opens a shop screen and refreshes the shop numbers on the way back.
Future<void> _open(BuildContext context, String route) async {
  await context.push(route);
  if (context.mounted) context.read<LoadCubit<SellerShopSummary>>().refresh();
}

/// Physical products: what needs doing now + quick actions.
class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.summary});

  final SellerShopSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final palette = context.palette;
    final pending = s?.needsAction ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pending > 0 ? AppColors.primary.withValues(alpha: 0.45) : palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 2),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(ShopIcons.bag, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your shop', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        s == null
                            ? 'Sell clothes, merch & more'
                            : s.productsTotal == 0
                            ? 'Sell clothes, merch & more — COD or online'
                            : '${s.productsLive} live · ${Fmt.money(s.earnings)} earned',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (pending > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('$pending to do', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          if (s != null && (s.newOrders + s.toShip + s.shipped) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(child: _OrderCount(label: 'New', value: s.newOrders, highlight: true, tab: 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _OrderCount(label: 'To ship', value: s.toShip, tab: 1)),
                  const SizedBox(width: 8),
                  Expanded(child: _OrderCount(label: 'Shipped', value: s.shipped, tab: 2)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _ShopAction(icon: AppIcons.plus, label: 'Add product', filled: true, onTap: () => _open(context, AppRoutes.shopProductEditor()))),
                const SizedBox(width: 8),
                Expanded(child: _ShopAction(icon: ShopIcons.bag, label: 'Products', onTap: () => _open(context, AppRoutes.sellerShopProducts))),
                const SizedBox(width: 8),
                Expanded(child: _ShopAction(icon: ShopIcons.orders, label: 'Orders', badge: pending, onTap: () => _open(context, AppRoutes.sellerShopOrders))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCount extends StatelessWidget {
  const _OrderCount({required this.label, required this.value, required this.tab, this.highlight = false});

  final String label;
  final int value;
  final int tab;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final hot = highlight && value > 0;
    return Material(
      color: hot ? AppColors.primary.withValues(alpha: 0.08) : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, '${AppRoutes.sellerShopOrders}?tab=$tab'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text('$value', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: hot ? AppColors.primary : null)),
              Text(label, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopAction extends StatelessWidget {
  const _ShopAction({required this.icon, required this.label, required this.onTap, this.filled = false, this.badge = 0});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? shopGradient : null,
          color: filled ? null : palette.surfaceMuted,
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  backgroundColor: AppColors.primary,
                  label: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  child: Icon(icon, size: 20, color: filled ? Colors.white : palette.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: filled ? Colors.white : palette.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap, this.last = false});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: palette.border))),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _EditStoreSheet extends StatefulWidget {
  const _EditStoreSheet({required this.store, required this.onImageChanged});

  final StoreInfo store;

  /// Pictures upload right away; the store screen behind updates too.
  final ValueChanged<MyStore> onImageChanged;

  @override
  State<_EditStoreSheet> createState() => _EditStoreSheetState();
}

class _EditStoreSheetState extends State<_EditStoreSheet> {
  late final _name = TextEditingController(text: widget.store.name);
  late final _tagline = TextEditingController(text: widget.store.tagline);
  late final _about = TextEditingController(text: widget.store.about);
  late bool _open = widget.store.isOpen;
  late StoreInfo _store = widget.store;

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _image(bool banner) async {
    final picked = await sl<MediaPicker>().image();
    if (picked == null || !mounted) return;
    final result = await context.read<ActionCubit>().run('image', () => sl<StoreRepository>().uploadStoreImage(picked, banner: banner));
    if (result != null && mounted) {
      widget.onImageChanged(result);
      if (result.store != null) setState(() => _store = result.store!);
      AppSnackbar.success(context, banner ? 'Banner updated' : 'Logo updated');
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      AppSnackbar.error(context, 'Store name must be at least 2 characters');
      return;
    }
    final result = await context.read<ActionCubit>().run(
      'save',
          () => sl<StoreRepository>().updateStore(name: _name.text.trim(), tagline: _tagline.text.trim(), about: _about.text.trim(), isOpen: _open),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Store settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner — same shape and look as the store card on Home.
          ListenableBuilder(
            listenable: Listenable.merge([_name, _tagline]),
            builder: (context, _) => ImageUploadBox(
              slot: ImageSlot.storeBanner,
              url: _store.bannerUrl,
              optional: true,
              enabled: !busy,
              onPick: () => _image(true),
              previewBuilder: (context, image) => StorefrontPreview(
                banner: image,
                name: _name.text.trim(),
                tagline: _tagline.text.trim(),
                logoUrl: _store.logoUrl,
                sold: _store.stats.orders,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ImageUploadBox(
            slot: ImageSlot.logo,
            url: _store.logoUrl,
            enabled: !busy,
            width: 84,
            onPick: () => _image(false),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: 'Store name', controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Tagline', controller: _tagline, maxLength: 120, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'About', controller: _about, minLines: 3, maxLines: 5, maxLength: 1500, textCapitalization: TextCapitalization.sentences),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _open,
            onChanged: busy ? null : (v) => setState(() => _open = v),
            title: Text('Taking orders', style: context.text.titleSmall),
            subtitle: Text(_open ? 'Buyers can purchase from your store' : 'Your store is visible but closed for orders', style: context.text.bodySmall),
          ),
          const SizedBox(height: AppSpacing.sm),
          const InlineActionError(),
          AppButton(label: 'Save', isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}