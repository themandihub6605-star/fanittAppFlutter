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
import '../../../community/presentation/communities_screen.dart' show MyCommunitiesScreen;
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

/// One card frame for the whole screen — same as the Home cards: white,
/// rounded 20, thin grey border, soft neutral shadow.
BoxDecoration _frame(BuildContext context, {Color? borderColor}) => BoxDecoration(
  color: context.palette.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: borderColor ?? context.palette.border.withValues(alpha: context.isDark ? 0.55 : 0.7)),
  boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
);

/// Section title + one grey line — same as the Home section headers.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(fontSize: 12.5, color: palette.textSecondary)),
        ],
      ],
    );
  }
}

class _StoreHome extends StatelessWidget {
  const _StoreHome({required this.data});

  final MyStore data;

  @override
  Widget build(BuildContext context) {
    final store = data.store!;
    final config = context.watch<LoadCubit<StoreConfig>>().state.data;
    final summary = context.watch<LoadCubit<StoreSummary>>().state.data;
    final shop = context.watch<LoadCubit<SellerShopSummary>>().state.data;
    // Tools the admin switched off are hidden (all show until settings load).
    bool enabled(String key) => config == null || config.toolCards.any((c) => c.key == key);
    final tools = [for (final t in _tools) if (enabled(t.key)) t];

    return Scaffold(
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
            // Hero: banner, glass buttons, logo, name, open / closed switch.
            SliverToBoxAdapter(child: _StoreHeader(store: store, onEdit: () => _editStore(context, store))),

            // Earnings — white card, calm colours.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(child: _EarningsCard(store: store, summary: summary).animate().fadeIn(delay: 60.ms, duration: 300.ms).slideY(begin: 0.05)),
            ),

            // Tools — like the Home quick-action tiles.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xxl - 4, AppSpacing.gutter, AppSpacing.sm),
              sliver: const SliverToBoxAdapter(
                child: _Section(title: 'Grow with your fans', subtitle: 'Go live, host sessions, sell, take paid calls'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 116),
                itemCount: tools.length,
                itemBuilder: (context, i) => _ToolTile(tool: tools[i], index: i),
              ),
            ),

            // Shop — physical products & orders. Hidden while the admin has
            // the Fanitt Store shop switched off.
            ValueListenableBuilder<bool>(
              valueListenable: FeatureFlags.store,
              builder: (context, shopOn, _) => shopOn
                  ? SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xxl - 4, AppSpacing.gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Section(title: 'Your shop', subtitle: 'Merch & physical products'),
                      const SizedBox(height: AppSpacing.sm),
                      _ShopCard(summary: shop).animate().fadeIn(delay: 150.ms, duration: 350.ms),
                    ],
                  ),
                ),
              )
                  : const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Manage
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xxl - 4, AppSpacing.gutter, AppSpacing.xxl),
              sliver: SliverList.list(
                children: [
                  const _Section(title: 'Manage', subtitle: 'Sales, tips, money and settings'),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: _frame(context),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _ManageTile(icon: AppIcons.chartLine, title: 'Analytics', subtitle: 'Views, sales, lives, calls and more', onTap: () => context.push(AppRoutes.storeAnalytics)),
                        if (enabled('digital_products'))
                          _ManageTile(icon: AppIcons.receipt, title: 'Digital sales', subtitle: 'Everyone who bought a digital product', onTap: () => context.push(AppRoutes.storeSales)),
                        if (enabled('fanbox'))
                          _ManageTile(icon: AppIcons.gift, title: 'FanBox', subtitle: 'Tips your fans sent you', onTap: () => context.push(AppRoutes.storeFanbox)),
                        _ManageTile(icon: AppIcons.wallet, title: 'Wallet & withdrawals', subtitle: 'Store earnings land in your Fanitt wallet', onTap: () => context.push(AppRoutes.wallet)),
                        _ManageTile(icon: AppIcons.gear, title: 'Store settings', subtitle: 'Name, logo, banner and opening', onTap: () => _editStore(context, store), last: true),
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
    final open = store.isOpen;
    final top = MediaQuery.paddingOf(context).top;
    final canPop = Navigator.of(context).canPop();
    return SizedBox(
      height: top + 196,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Banner (or a rich brand gradient), with shades so white text reads.
          store.bannerUrl.isNotEmpty
              ? StoreImage(url: store.bannerUrl, icon: AppIcons.storeFilled)
              : const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF667085), Color(0xFF344054)]),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59000000), Color(0x00000000), Color(0x99000000)],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
          // Glass buttons
          Positioned(
            top: top + 8,
            left: AppSpacing.gutter,
            right: AppSpacing.gutter,
            child: Row(
              children: [
                if (canPop) _GlassButton(icon: AppIcons.back, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
                const Spacer(),
                ShareIconButton(onDark: true, size: 40, message: () => ShareService.store(slug: store.slug, name: store.name, tagline: store.tagline, mine: true)),
                const SizedBox(width: 8),
                _GlassButton(icon: AppIcons.eye, tooltip: 'View my store', onTap: () => context.push(AppRoutes.storePage(store.slug))),
                const SizedBox(width: 8),
                _GlassButton(icon: AppIcons.gear, tooltip: 'Store settings', onTap: widget.onEdit),
              ],
            ),
          ),
          // Logo, name, open / closed, switch
          Positioned(
            left: AppSpacing.gutter,
            right: AppSpacing.gutter - 4,
            bottom: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onEdit,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
                    child: Hero(tag: 'store-logo-${store.id}', child: StoreLogo(name: store.name, url: store.logoUrl, size: 54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)]),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: open ? const Color(0xFF22C55E) : AppColors.warning, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(open ? 'Open · taking orders' : 'Closed · not taking orders', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _busy
                    ? const SizedBox(width: 48, height: 24, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))))
                    : Switch.adaptive(value: open, activeTrackColor: const Color(0xFF22C55E), onChanged: (_) => _toggleOpen()),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

/// Round frosted button on the hero banner.
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 19, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Earnings card — white, grey and dark text: total earned, last 30 days,
/// three numbers, then Withdraw (the one orange button) and Analytics.
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _frame(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(14)),
                child: Icon(AppIcons.wallet, color: palette.textPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total earned', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.textSecondary)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(Fmt.money(stats.netEarnings), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, height: 1.15, color: palette.textPrimary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Last 30 days', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    '${monthNet > 0 ? '+' : ''}${Fmt.money(monthNet)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: monthNet > 0 ? AppColors.success : palette.textPrimary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatBox(icon: AppIcons.receipt, value: Fmt.compact(stats.orders), label: 'Orders'),
              const SizedBox(width: 8),
              _StatBox(icon: AppIcons.eye, value: Fmt.compact(stats.views), label: 'Views'),
              const SizedBox(width: 8),
              _StatBox(icon: AppIcons.chartLine, value: conversion, label: 'Conversion'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _CardButton(label: 'Withdraw', icon: AppIcons.wallet, filled: true, onTap: () => context.push(AppRoutes.wallet))),
              const SizedBox(width: 8),
              Expanded(child: _CardButton(label: 'Analytics', icon: AppIcons.chartLine, onTap: () => context.push(AppRoutes.storeAnalytics))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grey number box with a small grey icon.
class _StatBox extends StatelessWidget {
  const _StatBox({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 9),
        decoration: BoxDecoration(color: palette.surfaceMuted.withValues(alpha: context.isDark ? 1 : 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: palette.textSecondary),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: palette.textPrimary))),
            Text(label, maxLines: 1, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Orange pill (main action) or white pill with a grey border.
class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.icon, required this.onTap, this.filled = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = filled ? Colors.white : palette.textPrimary;
    return Material(
      color: filled ? AppColors.primary : palette.surface,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
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
  _Tool(key: 'virtual_meet', title: 'Live session', subtitle: 'Webinars & 1:1', icon: AppIcons.videoCamera, colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)], route: AppRoutes.sessions),
  _Tool(key: 'stream_live', title: 'Stream Live', subtitle: 'Free or paid', icon: AppIcons.broadcast, colors: [Color(0xFFE53935), Color(0xFFFF7043)], route: AppRoutes.storeLives),
  _Tool(key: 'community', title: 'Community', subtitle: 'Free or paid', icon: AppIcons.users, colors: [Color(0xFF00A3A3), Color(0xFF26C6DA)], route: MyCommunitiesScreen.route),
  _Tool(key: 'affiliate', title: 'Affiliate', subtitle: 'Share links', icon: AppIcons.link, colors: [Color(0xFFF59E0B), Color(0xFFFFCA28)], route: AppRoutes.storeAffiliate),
  _Tool(key: 'digital_products', title: 'Digital products', subtitle: 'Courses, ebooks', icon: AppIcons.download, colors: [Color(0xFF3949AB), Color(0xFF7986CB)], route: AppRoutes.storeProducts),
  _Tool(key: 'chat_calls', title: 'Paid calls', subtitle: 'Per minute', icon: AppIcons.phone, colors: [Color(0xFF1E88E5), Color(0xFF64B5F6)], route: AppRoutes.storeCalls),
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
    final dark = context.isDark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(t.route);
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border.withValues(alpha: dark ? 0.5 : 0.7)),
            boxShadow: dark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Column(
            children: [
              // Glossy colour icon — same as the Home quick actions.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [t.colors.last, t.colors.first]),
                  boxShadow: [BoxShadow(color: t.colors.first.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)]),
                        ),
                      ),
                    ),
                    Center(child: Icon(t.icon, color: Colors.white, size: 20)),
                  ],
                ),
              ),
              const Spacer(),
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: -0.1, color: palette.textPrimary)),
              const SizedBox(height: 1),
              Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: palette.textSecondary)),
            ],
          ),
        ),
      ),
    ).animate(delay: (50 * widget.index).ms).fadeIn(duration: 260.ms).scaleXY(begin: 0.94, curve: Curves.easeOutBack, duration: 340.ms);
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
      decoration: _frame(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 2),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(13)),
                  child: Icon(ShopIcons.bag, color: palette.textPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s == null || s.productsTotal == 0 ? 'Start selling merch' : '${s.productsLive} live · ${Fmt.money(s.earnings)} earned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary),
                      ),
                      Text('Clothes, merch & more · COD or online', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                    ],
                  ),
                ),
                if (pending > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('$pending to do', style: const TextStyle(color: AppColors.warning, fontSize: 11.5, fontWeight: FontWeight.w800)),
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
                Expanded(child: _ShopAction(icon: AppIcons.plus, label: 'Add', filled: true, onTap: () => _open(context, AppRoutes.shopProductEditor()))),
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
      color: hot ? AppColors.success.withValues(alpha: 0.1) : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, '${AppRoutes.sellerShopOrders}?tab=$tab'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text('$value', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: hot ? AppColors.success : palette.textPrimary)),
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

  /// The one main button (Add) — orange. The rest are white.
  final bool filled;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = filled ? Colors.white : palette.textPrimary;
    return Material(
      color: filled ? AppColors.primary : palette.surface,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg))),
              if (badge > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                  child: Text('$badge', style: const TextStyle(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.last = false});

  final IconData icon;
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
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: palette.border.withValues(alpha: 0.7)))),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: palette.textPrimary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
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