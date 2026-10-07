import 'package:cached_network_image/cached_network_image.dart';
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
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';
import 'store_setup_screen.dart';

/// Creator's way into Fanitt Store: setup until the store is approved,
/// then the Store Home dashboard with the seven tools.
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
      ],
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<MyStore>>();
          final data = cubit.state.data;
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
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(child: _StoreHeader(store: store, onEdit: () => _editStore(context, store))),
            ),

            // Earnings hero
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(child: _EarningsHero(store: store, summary: summary).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06)),
            ),

            // Small numbers
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: _MiniStat(icon: AppIcons.receipt, value: Fmt.compact(store.stats.orders), label: 'Orders', color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _MiniStat(icon: AppIcons.eye, value: Fmt.compact(store.stats.views), label: 'Store views', color: AppColors.info)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MiniStat(
                        icon: AppIcons.chartLine,
                        value: store.stats.views == 0 ? '—' : '${((store.stats.orders / store.stats.views) * 100).clamp(0, 100).toStringAsFixed(1)}%',
                        label: 'Conversion',
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
              ),
            ),

            // Tools
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your tools', style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Everything you can sell and run from your store', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
            if (config == null)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator())))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 150),
                  itemCount: config.toolCards.length,
                  itemBuilder: (context, i) => _ToolTile(card: config.toolCards[i], index: i),
                ),
              ),

            // Manage
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.huge),
              sliver: SliverList.list(
                children: [
                  Text('Manage', style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _ManageTile(icon: AppIcons.chartLine, color: const Color(0xFF00A3A3), title: 'Analytics', subtitle: 'Views, sales, lives, calls and more', onTap: () => context.push(AppRoutes.storeAnalytics)),
                        _ManageTile(icon: AppIcons.receipt, color: AppColors.primary, title: 'Sales & orders', subtitle: 'Everyone who bought from you', onTap: () => context.push(AppRoutes.storeSales)),
                        _ManageTile(icon: AppIcons.package, color: const Color(0xFF7C4DFF), title: 'My products', subtitle: 'Create and edit digital products', onTap: () => context.push(AppRoutes.storeProducts)),
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
    return Container(
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same shop-front card buyers see on Home.
          AspectRatio(
            aspectRatio: ImageSlot.storeBanner.aspectRatio,
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.storePage(store.slug)),
              child: StorefrontPreview(
                banner: store.bannerUrl.isEmpty ? StorefrontPreview.placeholder() : StoreImage(url: store.bannerUrl),
                name: store.name,
                tagline: store.tagline,
                logoUrl: store.logoUrl,
                sold: store.stats.orders,
                logoHeroTag: 'store-logo-${store.id}',
                topRight: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: store.isOpen ? const Color(0xFF34D399) : const Color(0xFFFBBF24), shape: BoxShape.circle))
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 1, end: 0.3, duration: 900.ms),
                      const SizedBox(width: 5),
                      Text(store.isOpen ? 'Live' : 'Closed', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    store.isOpen ? 'Taking orders — buyers can purchase now' : 'Closed — buyers can see your store but not buy',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(fontSize: 12.5, color: palette.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                // Taking orders switch
                GestureDetector(
                  onTap: _busy ? null : _toggleOpen,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: store.isOpen ? AppColors.primary.withValues(alpha: 0.12) : palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: store.isOpen ? AppColors.primary.withValues(alpha: 0.3) : palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _busy
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.8))
                            : Icon(store.isOpen ? AppIcons.storeFilled : AppIcons.lock, size: 13, color: store.isOpen ? AppColors.primary : palette.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          store.isOpen ? 'Open' : 'Closed',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: store.isOpen ? AppColors.primary : palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

/// Dark card: what the store earned, with a 30-day line.
class _EarningsHero extends StatelessWidget {
  const _EarningsHero({required this.store, required this.summary});

  final StoreInfo store;
  final StoreSummary? summary;

  @override
  Widget build(BuildContext context) {
    final last30 = summary?.last30Days ?? const [];
    final monthNet = last30.fold<int>(0, (s, d) => s + d.net);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14141F), Color(0xFF2A1320)]),
        boxShadow: [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('You earned', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text('Last 30 days ${Fmt.money(monthNet)}', style: const TextStyle(color: AppColors.sunrise, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: store.stats.netEarnings.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              Fmt.money(v.round()),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Sales ${Fmt.money(store.stats.grossSales)} · Fees ${Fmt.money(store.stats.feesPaid)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (last30.length > 1) ...[
            const SizedBox(height: 14),
            SizedBox(height: 36, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values: [for (final d in last30) d.net.toDouble()]))),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _HeroButton(icon: AppIcons.wallet, label: 'Withdraw', onTap: () => context.push(AppRoutes.wallet), filled: true)),
              const SizedBox(width: 10),
              Expanded(child: _HeroButton(icon: AppIcons.chartLine, label: 'Analytics', onTap: () => context.push(AppRoutes.storeAnalytics))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final step = size.width / (values.length - 1);
    final points = [
      for (var i = 0; i < values.length; i++) Offset(i * step, size.height - (maxV == 0 ? 0 : values[i] / maxV) * (size.height - 4) - 2),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final mid = (prev.dx + cur.dx) / 2;
      line.cubicTo(mid, prev.dy, mid, cur.dy, cur.dx, cur.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66F4511E), Color(0x00F4511E)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values;
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]) : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.1),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// One of the seven tools; image and text come from the admin panel.
class _ToolTile extends StatefulWidget {
  const _ToolTile({required this.card, required this.index});

  final ToolCard card;
  final int index;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _down = false;

  static const _icons = <String, IconData>{
    'virtual_meet': AppIcons.videoCamera,
    'stream_live': AppIcons.broadcast,
    'chat_calls': AppIcons.phone,
    'digital_products': AppIcons.package,
    'community': AppIcons.users,
    'affiliate': AppIcons.link,
    'fanbox': AppIcons.gift,
  };

  static const _accents = <String, Color>{
    'virtual_meet': Color(0xFF7C4DFF),
    'stream_live': Color(0xFFE53935),
    'chat_calls': Color(0xFF1E88E5),
    'digital_products': Color(0xFFF4511E),
    'community': Color(0xFF00A3A3),
    'affiliate': Color(0xFFF59E0B),
    'fanbox': Color(0xFFEC2A78),
  };

  void _open(BuildContext context) {
    HapticFeedback.selectionClick();
    switch (widget.card.key) {
      case 'digital_products':
        context.push(AppRoutes.storeProducts);
      case 'virtual_meet':
        context.push(AppRoutes.sessions);
      case 'community':
        context.push(AppRoutes.communities);
      case 'fanbox':
        context.push(AppRoutes.storeFanbox);
      case 'affiliate':
        context.push(AppRoutes.storeAffiliate);
      case 'stream_live':
        context.push(AppRoutes.storeLives);
      case 'chat_calls':
        context.push(AppRoutes.storeCalls);
      default:
        _comingSoon(context, widget.card.title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final icon = _icons[card.key] ?? AppIcons.store;
    final accent = _accents[card.key] ?? AppColors.primary;
    final palette = context.palette;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () => _open(context),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: palette.border)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Picture area — the whole image is shown (never cropped).
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.06)]),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (card.imageUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: CachedNetworkImage(
                            imageUrl: card.imageUrl,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => const SizedBox.shrink(),
                            errorWidget: (_, _, _) => Center(child: Icon(icon, size: 34, color: accent)),
                          ),
                        )
                      else
                        Center(child: Icon(icon, size: 34, color: accent)),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(9)),
                          child: Icon(icon, color: Colors.white, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(card.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(AppIcons.chevronRight, size: 16, color: palette.textTertiary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (50 * widget.index).ms).fadeIn(duration: 280.ms).scaleXY(begin: 0.95, curve: Curves.easeOutBack);
  }
}

void _comingSoon(BuildContext context, String title) {
  showAppSheet<void>(
    context,
    builder: (ctx) => SheetBody(
      title: title,
      subtitle: 'Coming in the next Fanitt update',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(AppIcons.sparkle, size: 44, color: AppColors.primary)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.9, end: 1.1, duration: 900.ms),
          const SizedBox(height: AppSpacing.md),
          Text('We’re putting the final touches on this. Keep your app updated — you’ll see it here soon.', textAlign: TextAlign.center, style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          AppButton(label: 'Got it', onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    ),
  );
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