// File: lib/features/dashboard/presentation/home_discover.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/services/feature_flags.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/json.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/guards/profile_gate.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../brands/data/brands_repository.dart';
import '../../campaigns/data/campaign_models.dart';
import '../../campaigns/data/campaign_repository.dart';
import '../../community/data/community_repository.dart';
import '../../community/presentation/community_paid_join.dart' show communityPriceLabel;
import '../../creators/data/creators_repository.dart';
import '../../profile/data/profile_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/live/live_now_stories.dart';
import '../../store/presentation/commerce/shop_home_section.dart';
import '../../store/presentation/meet/meet_detail_screen.dart';
import '../../store/presentation/widgets/store_widgets.dart';

// Home screen discovery kit: section headers, quick actions and horizontal
// rails (creators, brands, campaigns, live, meets, communities, stores).
// Every rail loads its own real data, shows a shimmer while loading and
// hides itself when there's nothing to show — no placeholder content.

/// Admin-pinned items first (in the admin's order), then the usual list,
/// without duplicates.
Future<List<T>> pinnedFirst<T>({
  required List<String> pinned,
  required Future<List<T>> Function(List<String> ids) loadPinned,
  required Future<List<T>> Function() loadRest,
  required String Function(T item) idOf,
  int max = 12,
  bool onlyPinned = false,
}) async {
  var first = <T>[];
  if (pinned.isNotEmpty) {
    try {
      final order = {for (var i = 0; i < pinned.length; i++) pinned[i]: i};
      first = [...await loadPinned(pinned)]..sort((a, b) => (order[idOf(a)] ?? 999).compareTo(order[idOf(b)] ?? 999));
    } catch (_) {
      first = <T>[];
    }
  }
  // Admin chose "only my picks": nothing automatic after them.
  if (onlyPinned && pinned.isNotEmpty) return first.take(max).toList();
  final seen = first.map(idOf).toSet();
  final rest = await loadRest();
  return [...first, ...rest.where((x) => !seen.contains(idOf(x)))].take(max).toList();
}

/// Bump this on pull-to-refresh: every rail reloads.
final ValueNotifier<int> homeRefreshTick = ValueNotifier<int>(0);

const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

// Home design tokens (8pt grid): 20px side margins, 24px between sections,
// 16px card corners, 12px button corners, 1px borders instead of heavy shadows.
const double kHomeCardRadius = 20;
const double kHomeButtonRadius = 12;

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.subtitle, this.onSeeAll, this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.gutter)});

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            InkWell(
              borderRadius: BorderRadius.circular(kHomeButtonRadius),
              onTap: onSeeAll,
              child: Padding(
                // 44px tall tap target.
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all', style: context.text.labelLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 2),
                    const Icon(AppIcons.chevronRight, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions — 4 per row inside one card. Pass `more` to show the first
// 7 actions plus a "More" tile that opens the extra rows below.
// ---------------------------------------------------------------------------

class HomeAction {
  const HomeAction({required this.icon, required this.label, required this.onTap, this.color = AppColors.primary, this.isNew = false, this.locked = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isNew;

  /// Shows a small lock (e.g. store tools before the store is live). The tap
  /// still runs [onTap], which explains what to do.
  final bool locked;
}

class HomeQuickActions extends StatefulWidget {
  const HomeQuickActions({super.key, required this.actions, this.more = const []});

  /// The first is the big tile; up to 5 more show (6 without `more`), the rest go under "More".
  final List<HomeAction> actions;

  /// Extra shortcuts, shown in the "More" sheet.
  final List<HomeAction> more;

  @override
  State<HomeQuickActions> createState() => _HomeQuickActionsState();
}

class _HomeQuickActionsState extends State<HomeQuickActions> {
  static const double _tileH = 92;
  static const double _gap = 10;

  void _openAll(List<HomeAction> rest) {
    HapticFeedback.selectionClick();
    showAppSheet<void>(context, builder: (_) => _AllActionsSheet(actions: rest));
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.actions;
    if (all.isEmpty) return const SizedBox.shrink();
    // Bento: the main action is a wide hero tile; then small tiles.
    // 6 actions show; the rest (and everything in `more`) is under "More".
    final hero = all.first;
    final small = all.skip(1).toList();
    final hasMore = small.length > 5 || widget.more.isNotEmpty;
    final shown = hasMore ? small.take(5).toList() : small.take(6).toList();
    final rest = [...small.skip(shown.length), ...widget.more];

    final tiles = <Widget>[
      for (final (i, a) in shown.indexed) _ActionTile(action: a, index: i + 1),
      if (hasMore)
        _ActionTile(
          action: HomeAction(icon: AppIcons.dashboard, label: 'More', color: context.palette.textSecondary, onTap: () => _openAll(rest)),
          index: shown.length + 1,
          neutral: true,
        ),
    ];

    Widget row(List<Widget> items, {int slots = 4}) => SizedBox(
      height: _tileH,
      child: Row(
        children: [
          for (var j = 0; j < slots; j++) ...[
            if (j > 0) const SizedBox(width: _gap),
            Expanded(child: j < items.length ? items[j] : const SizedBox.shrink()),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        children: [
          // Row 1: hero (2 slots) + 2 tiles — lined up with the 4-slot row below.
          LayoutBuilder(
            builder: (context, box) {
              final slot = (box.maxWidth - 3 * _gap) / 4;
              return SizedBox(
                height: _tileH,
                child: Row(
                  children: [
                    SizedBox(width: slot * 2 + _gap, child: _HeroAction(action: hero)),
                    const SizedBox(width: _gap),
                    SizedBox(width: slot, child: tiles.isNotEmpty ? tiles[0] : null),
                    const SizedBox(width: _gap),
                    SizedBox(width: slot, child: tiles.length > 1 ? tiles[1] : null),
                  ],
                ),
              );
            },
          ),
          if (tiles.length > 2) ...[
            const SizedBox(height: _gap),
            row(tiles.skip(2).take(4).toList()),
          ],
        ],
      ),
    );
  }
}

/// The main action — a wide brand-gradient tile.
class _HeroAction extends StatefulWidget {
  const _HeroAction({required this.action});

  final HomeAction action;

  @override
  State<_HeroAction> createState() => _HeroActionState();
}

class _HeroActionState extends State<_HeroAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        a.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: BoxDecoration(
            gradient: _brandGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [BoxShadow(color: Color(0x4DF4511E), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Soft light shapes for depth.
                Positioned(right: -24, top: -30, child: _bubble(96, 0.16)),
                Positioned(right: 30, bottom: -36, child: _bubble(70, 0.10)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Icon(a.icon, color: Colors.white, size: 20),
                          ),
                          const Spacer(),
                          if (a.isNew)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                              child: const Text('NEW', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                            )
                          else if (a.locked)
                            const Icon(AppIcons.lock, color: Colors.white, size: 16),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(AppIcons.arrowRightSimple, size: 13, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.94, curve: Curves.easeOutBack, duration: 380.ms);
  }

  Widget _bubble(double size, double alpha) => IgnorePointer(
    child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha))),
  );
}

/// Small bento tile: white card, glossy colour icon, label.
class _ActionTile extends StatefulWidget {
  const _ActionTile({required this.action, this.index = 0, this.animate = true, this.neutral = false});

  final HomeAction action;
  final int index;
  final bool animate;

  /// Grey icon (the "More" tile).
  final bool neutral;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final palette = context.palette;
    final dark = context.isDark;
    final c = a.color;

    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: widget.neutral
            ? null
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(c, Colors.white, 0.18)!, c]),
        color: widget.neutral ? palette.surfaceMuted : null,
        boxShadow: widget.neutral ? null : [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          // Glossy top highlight.
          if (!widget.neutral)
            Positioned(
              left: 4,
              right: 4,
              top: 3,
              height: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)]),
                ),
              ),
            ),
          Center(child: Icon(a.icon, size: 20, color: widget.neutral ? palette.textPrimary : Colors.white)),
        ],
      ),
    );

    Widget tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        a.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border.withValues(alpha: dark ? 0.5 : 0.7)),
            boxShadow: dark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(opacity: a.locked ? 0.5 : 1, child: icon),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(a.label, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: palette.textPrimary, letterSpacing: -0.1)),
                      ),
                    ),
                  ],
                ),
              ),
              if (a.locked)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(AppIcons.lock, size: 12, color: palette.textTertiary),
                )
              else if (a.isNew)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(6)),
                    child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.animate) {
      tile = tile.animate(delay: (35 * widget.index).ms).fadeIn(duration: 260.ms).scaleXY(begin: 0.9, curve: Curves.easeOutBack, duration: 360.ms);
    }
    return tile;
  }
}

/// "More" — every other shortcut in a bottom sheet, same tiles.
class _AllActionsSheet extends StatelessWidget {
  const _AllActionsSheet({required this.actions});

  final List<HomeAction> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('More shortcuts', style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: AppSpacing.md),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 92),
              itemBuilder: (context, i) {
                final a = actions[i];
                return _ActionTile(
                  index: i,
                  action: HomeAction(
                    icon: a.icon,
                    label: a.label,
                    color: a.color,
                    isNew: a.isNew,
                    locked: a.locked,
                    onTap: () {
                      Navigator.of(context).pop();
                      a.onTap();
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic rail
// ---------------------------------------------------------------------------

/// Horizontal list that loads its own data. Hidden when empty or on error.
class HomeRail<T> extends StatefulWidget {
  const HomeRail({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    required this.height,
    required this.itemWidth,
    this.subtitle,
    this.onSeeAll,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double height;
  final double itemWidth;
  final VoidCallback? onSeeAll;

  /// Optional widget before the title (e.g. a pulsing "live" dot).
  final Widget? leading;

  @override
  State<HomeRail<T>> createState() => _HomeRailState<T>();
}

class _HomeRailState<T> extends State<HomeRail<T>> with AutomaticKeepAliveClientMixin {
  // Keep loaded rails alive while scrolling — no reload, no flicker.
  @override
  bool get wantKeepAlive => true;

  late Future<List<T>> _future = _safeLoad();

  Future<List<T>> _safeLoad() async {
    try {
      return await widget.load();
    } catch (error, stack) {
      // The rail hides itself on failure — log why, so a missing section is easy to trace.
      debugPrint('[home] "${widget.title}" failed to load: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      return <T>[];
    }
  }

  void _reload() {
    if (!mounted) return;
    // setState must not return the Future, so assign inside a block.
    setState(() {
      _future = _safeLoad();
    });
  }

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_reload);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? <T>[];
        if (!loading && items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxl - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.leading == null)
                HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll)
              else
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.gutter),
                  child: Row(
                    children: [
                      widget.leading!,
                      const SizedBox(width: 8),
                      Expanded(child: HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll, padding: const EdgeInsets.only(right: AppSpacing.gutter))),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: widget.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: loading ? 4 : items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => SizedBox(
                    width: widget.itemWidth,
                    child: loading
                        ? const _Skeleton()
                        : widget.itemBuilder(context, items[i])
                        .animate(delay: (50 * i.clamp(0, 6)).ms)
                        .fadeIn(duration: 300.ms)
                        .slideX(begin: 0.12, curve: Curves.easeOutCubic),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: DecoratedBox(decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(16)), child: const SizedBox.expand())),
        const SizedBox(height: 10),
        Container(width: 120, height: 12, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6))),
        const SizedBox(height: 6),
        Container(width: 80, height: 10, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6))),
        const SizedBox(height: 4),
      ],
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6));
  }
}

// ---------------------------------------------------------------------------
// Card shell used by every rail item
// ---------------------------------------------------------------------------




/// Small pill on a picture: white with dark text, or a solid colour.
class _PicChip extends StatelessWidget {
  const _PicChip({required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;

  /// Solid background with white text (e.g. FREE in green). Null = white.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color == null ? const Color(0xFF0F172A) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color == null ? AppColors.primary : Colors.white), const SizedBox(width: 4)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.2))),
        ],
      ),
    );
  }
}


Widget _netImage(String? url, {IconData icon = AppIcons.image, BoxFit fit = BoxFit.cover}) {
  final placeholder = ColoredBox(
    color: const Color(0x14F4511E),
    child: Center(child: Icon(icon, color: const Color(0x80F4511E), size: 22)),
  );
  if (url == null || url.isEmpty) return placeholder;
  return CachedNetworkImage(imageUrl: url, fit: fit, placeholder: (_, _) => placeholder, errorWidget: (_, _, _) => placeholder);
}

Widget _avatar(String? url, String name, double size, {bool ring = false, Color? borderColor}) {
  final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
  final inner = ClipOval(
    child: SizedBox(
      width: size,
      height: size,
      child: url == null || url.isEmpty
          ? ColoredBox(
        color: const Color(0x1FF4511E),
        child: Center(child: Text(initial, style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: size * 0.4))),
      )
          : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
    ),
  );
  if (!ring) {
    return borderColor == null ? inner : Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: borderColor), child: inner);
  }
  return Container(
    padding: const EdgeInsets.all(2.5),
    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
    child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: borderColor ?? Colors.white), child: inner),
  );
}

// ---------------------------------------------------------------------------
// Classic cards (below the store banner): no frame, a rounded picture and
// three short lines — title, one grey line, one orange line. Tap anywhere.
// ---------------------------------------------------------------------------

const double _kWideW = 250; // campaigns, meets, lives, stores, communities, brands
const double _kWideImg = 141; // 16:9
const double _kSmallW = 140; // creators, products

TextStyle _cTitle(BuildContext context) => TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.25, color: context.palette.textPrimary);
TextStyle _cMeta(BuildContext context) => TextStyle(fontSize: 12.5, height: 1.3, color: context.palette.textSecondary);
const TextStyle _cAccent = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.3, color: AppColors.primary);

/// Rounded picture (or soft orange tint with an icon) with an optional chip.
class _ClassicImage extends StatelessWidget {
  const _ClassicImage({required this.url, required this.icon, required this.height, this.chip, this.chipRight});

  final String? url;
  final IconData icon;
  final double height;
  final Widget? chip;
  final Widget? chipRight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _coverOrGradient(url, icon: icon, colors: const []),
            if (chip != null) Positioned(left: 8, top: 8, child: chip!),
            if (chipRight != null) Positioned(right: 8, top: 8, child: chipRight!),
          ],
        ),
      ),
    );
  }
}

/// Picture + title + grey line + orange line. The whole thing is the button.
class _ClassicCard extends StatelessWidget {
  const _ClassicCard({required this.onTap, required this.media, required this.title, this.meta, this.metaWidget, this.accent, this.accentColor});

  final VoidCallback onTap;
  final Widget media;
  final String title;
  final String? meta;
  final Widget? metaWidget;
  final String? accent;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return _ImmersivePress(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          media,
          const SizedBox(height: 9),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cTitle(context)),
          if (metaWidget != null) ...[const SizedBox(height: 2), metaWidget!]
          else if (meta != null && meta!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cMeta(context)),
          ],
          if (accent != null) ...[
            const SizedBox(height: 4),
            Text(accent!, maxLines: 1, overflow: TextOverflow.ellipsis, style: accentColor == null ? _cAccent : _cAccent.copyWith(color: accentColor)),
          ],
        ],
      ),
    );
  }
}

/// Soft orange box with a round logo in the middle — for things without a
/// photo (campaigns, brands).
class _LogoPanel extends StatelessWidget {
  const _LogoPanel({required this.logoUrl, required this.name, required this.icon, this.tag, this.imageUrl});

  final String? logoUrl;

  /// Optional picture behind the logo (the campaign image the brand uploaded).
  final String? imageUrl;
  final String name;
  final IconData icon;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: _kWideImg,
        width: double.infinity,
        color: AppColors.primary.withValues(alpha: context.isDark ? 0.14 : 0.07),
        child: Stack(
          children: [
            if ((imageUrl ?? '').isNotEmpty) ...[
              Positioned.fill(child: _netImage(imageUrl, icon: icon)),
              // Light shade so the white logo ring stands out on any photo.
              const Positioned.fill(child: ColoredBox(color: Color(0x1F000000))),
            ],
            Center(
              child: Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface, border: Border.all(color: palette.border.withValues(alpha: 0.8))),
                child: ClipOval(
                  child: (logoUrl ?? '').isEmpty
                      ? Center(child: Text(initial, style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.w900)))
                      : CachedNetworkImage(
                    imageUrl: logoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => ColoredBox(color: palette.surfaceMuted),
                    errorWidget: (_, _, _) => Center(child: Icon(icon, color: AppColors.primary, size: 22)),
                  ),
                ),
              ),
            ),
            if (tag != null)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.sparkle, size: 11, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(tag!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ready-made rails
// ---------------------------------------------------------------------------

bool _profileIncomplete(BuildContext context) {
  final auth = context.read<AuthBloc>().state;
  return needsProfileCompletion(auth is AuthAuthenticated ? auth.user : null);
}

/// "Top creators" — 3–4 visible, swipe for more, See all → directory.
class CreatorsRail extends StatelessWidget {
  const CreatorsRail({super.key, this.title = 'Top creators', this.subtitle = 'Discover creators to work with', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Profiles that aren't complete can't browse creators (see profile_gate.dart).
    if (_profileIncomplete(context)) return const SizedBox.shrink();
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return HomeRail<CreatorProfile>(
      title: title,
      subtitle: subtitle,
      height: 200,
      itemWidth: _kSmallW,
      onSeeAll: () => context.push(AppRoutes.creatorsDirectory),
      load: () => pinnedFirst<CreatorProfile>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CreatorsRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CreatorsRepository>().list()).items,
        idOf: (c) => c.id,
      ).then((list) => list.where((c) => c.userId != myId).toList()),
      itemBuilder: (context, c) => _CreatorCard(creator: c),
    );
  }
}

/// Creator = round photo, name, niche · followers and a Follow button.
class _CreatorCard extends StatefulWidget {
  const _CreatorCard({required this.creator});

  final CreatorProfile creator;

  @override
  State<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends State<_CreatorCard> {
  late CreatorProfile c = widget.creator;
  bool _busy = false;

  /// Optimistic follow / unfollow; rolls back if the request fails.
  Future<void> _toggleFollow() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    final before = c;
    setState(() {
      _busy = true;
      c = c.copyWith(isFollowing: !c.isFollowing, followerCount: c.followerCount + (c.isFollowing ? -1 : 1));
    });
    try {
      final res = await sl<CreatorsRepository>().toggleFollow(before.id);
      if (mounted) setState(() => c = c.copyWith(isFollowing: res.following, followerCount: res.followerCount));
    } catch (_) {
      if (mounted) setState(() => c = before);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final verified = c.verificationStatus == VerificationStatus.verified;
    final niche = c.category?.label ?? (c.title.isEmpty ? 'Creator' : c.title);
    return _ImmersivePress(
      onTap: () => context.push(AppRoutes.creatorProfile(c.slug)),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _avatar(c.avatarUrl, c.name, 96),
              if (c.isAvailableForWork)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(width: 15, height: 15, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2.5))),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cTitle(context))),
              if (verified) ...[const SizedBox(width: 3), const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info)],
            ],
          ),
          const SizedBox(height: 2),
          Text('$niche · ${Fmt.compact(c.followerCount)}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _cMeta(context)),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleFollow,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 110,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.isFollowing ? palette.surfaceMuted : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: c.isFollowing ? palette.border : AppColors.primary, width: 1.5),
              ),
              child: Text(
                c.isFollowing ? 'Following' : 'Follow',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.isFollowing ? palette.textSecondary : AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class BrandsRail extends StatelessWidget {
  const BrandsRail({super.key, this.title = 'Brands on Fanitt', this.subtitle = 'Companies hiring creators', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return HomeRail<BrandListItem>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: () => context.push(AppRoutes.brands),
      load: () => pinnedFirst<BrandListItem>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<BrandsRepository>().list(ids: ids, limit: 30)).items,
        loadRest: () async => (await sl<BrandsRepository>().list()).items,
        idOf: (b) => b.profile.id,
      ),
      itemBuilder: (context, b) => _BrandCard(brand: b),
    );
  }
}

/// Brand = soft orange panel with the round logo, then name, industry ·
/// followers and campaigns count.
class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.brand});

  final BrandListItem brand;

  @override
  Widget build(BuildContext context) {
    final b = brand;
    final p = b.profile;
    final name = p.companyName.trim().isEmpty ? 'Brand' : p.companyName.trim();
    final verified = p.verificationStatus == VerificationStatus.verified;
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.brandProfile(p.slug)),
      media: _LogoPanel(logoUrl: b.logoUrl, name: name, icon: AppIcons.brand, tag: b.isPro ? 'PRO' : null),
      title: verified ? '$name ✓' : name,
      meta: [if (p.industry.isNotEmpty) p.industry, '${Fmt.compact(b.followerCount)} followers'].join(' · '),
      accent: p.totalCampaigns > 0 ? '${Fmt.compact(p.totalCampaigns)} campaigns' : 'New on Fanitt',
    );
  }
}




/// Press-to-shrink wrapper.
class _ImmersivePress extends StatefulWidget {
  const _ImmersivePress({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ImmersivePress> createState() => _ImmersivePressState();
}

class _ImmersivePressState extends State<_ImmersivePress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 140), child: widget.child),
    );
  }
}

class CampaignsRail extends StatelessWidget {
  const CampaignsRail({super.key, this.title = 'Open campaigns', this.subtitle = 'Paid & barter collaborations', this.onSeeAll, this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final isCreator = auth is AuthAuthenticated && auth.user.role == UserRole.creator;
    return HomeRail<Campaign>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: onSeeAll,
      load: () => pinnedFirst<Campaign>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CampaignRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CampaignRepository>().list()).items,
        idOf: (c) => c.id,
        max: 10,
      ),
      itemBuilder: (context, c) => _CampaignTicket(campaign: c, isCreator: isCreator),
    );
  }
}

/// Campaign = soft orange panel with the brand logo, then title, brand ·
/// place · applied (or why it matched) and the pay in orange.
class _CampaignTicket extends StatelessWidget {
  const _CampaignTicket({required this.campaign, required this.isCreator, this.matchLabel, this.reason});

  final Campaign campaign;
  final bool isCreator;

  /// Picked for you: small tag ("Top match") and why it matched.
  final String? matchLabel;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final brand = c.brand?.name ?? 'Brand';
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.campaignDetail(c.id)),
      media: _LogoPanel(logoUrl: c.brand?.logoUrl, name: brand, icon: AppIcons.brand, imageUrl: c.campaignImageUrl, tag: matchLabel ?? (c.isFeatured ? 'Featured' : null)),
      title: c.title,
      metaWidget: reason == null
          ? null
          : Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success),
          const SizedBox(width: 4),
          Expanded(child: Text(reason!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cMeta(context).copyWith(color: AppColors.success, fontWeight: FontWeight.w600))),
        ],
      ),
      meta: [brand, c.locationLabel, '${c.applicantCount} applied'].join(' · '),
      accent: c.isPaid ? '${Fmt.money(c.costPerInfluencer)} / creator' : 'Barter',
    );
  }
}



// ---------------------------------------------------------------------------
// Picked for you (creator home) — campaigns matched to the profile
// ---------------------------------------------------------------------------

/// Loads its own matches. Pro creators see a rail of matched campaigns
/// (each says why it matched); free plans see an upgrade card; no matches
/// shows a card to improve the profile.
class PickedForYouSection extends StatefulWidget {
  const PickedForYouSection({super.key, this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  State<PickedForYouSection> createState() => _PickedForYouSectionState();
}

class _PickedForYouSectionState extends State<PickedForYouSection> {
  late Future<({List<SuggestedCampaign> items, bool locked})> _future = _load();

  static Future<({List<SuggestedCampaign> items, bool locked})> _load() async {
    try {
      return (items: await sl<CampaignRepository>().suggested(), locked: false);
    } on ApiException catch (e) {
      if (e.errorCode == 'PRO_FEATURE_LOCKED') return (items: const <SuggestedCampaign>[], locked: true);
      return (items: const <SuggestedCampaign>[], locked: false);
    } catch (_) {
      return (items: const <SuggestedCampaign>[], locked: false);
    }
  }

  Future<void> _reloadAfter(String route) async {
    await context.push(route);
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeSectionHeader(title: 'Picked for you', subtitle: 'Campaigns that match your profile', onSeeAll: widget.onSeeAll),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<({List<SuggestedCampaign> items, bool locked})>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return SizedBox(
                height: 222,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  itemCount: 2,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, _) => const SizedBox(width: _kWideW, child: _Skeleton()),
                ),
              );
            }
            final data = snap.data!;
            if (data.locked) {
              return _PickedPrompt(
                icon: AppIcons.crown,
                title: 'Unlock campaigns made for you',
                message: 'Matches by category, skills & city',
                action: 'Plans',
                onTap: () => _reloadAfter(AppRoutes.plans),
              );
            }
            if (data.items.isEmpty) {
              return _PickedPrompt(
                icon: AppIcons.sparkle,
                title: 'No matching campaigns',
                message: 'Add category, skills & city',
                action: 'Edit',
                onTap: () => _reloadAfter(AppRoutes.editProfile),
              );
            }
            final items = data.items.take(8).toList();
            return SizedBox(
              height: 222,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) => SizedBox(
                  width: _kWideW,
                  child: _CampaignTicket(
                    campaign: items[i].campaign,
                    isCreator: true,
                    matchLabel: i == 0 ? 'Top match' : null,
                    reason: items[i].reasons.isNotEmpty ? items[i].reasons.first : null,
                  ).animate(delay: (60 * i).ms).fadeIn(duration: 300.ms).slideX(begin: 0.08),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Locked / no-match row: white box, orange icon, two lines and an orange link.
class _PickedPrompt extends StatelessWidget {
  const _PickedPrompt({required this.icon, required this.title, required this.message, required this.action, required this.onTap});

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = context.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border.withValues(alpha: dark ? 0.55 : 0.8))),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: dark ? 0.18 : 0.10), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: AppColors.primary, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cTitle(context)),
                      const SizedBox(height: 1),
                      Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cMeta(context)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('$action ›', style: _cAccent),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class LiveNowRail extends StatelessWidget {
  const LiveNowRail({super.key, this.title = 'Live streams', this.subtitle = 'Live now & coming up · see who can join'});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Public lives + the private ones this person is allowed into
    // (their communities, invites, hand-picked). Each card says who it's for.
    return HomeRail<LiveStream>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      leading: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fade(begin: 1, end: 0.3, duration: 700.ms),
      load: () => sl<StoreRepository>().discoverLives(limit: 12),
      itemBuilder: (context, live) => _LiveCard(live: live),
    );
  }
}

/// Live = picture with LIVE / start time, title, host · viewers, price.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live});

  final LiveStream live;

  static String _startsLabel(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'Starting soon';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) return 'In ${diff.inHours}h';
    return Fmt.weekdayDateTime(when);
  }

  @override
  Widget build(BuildContext context) {
    final when = (live.scheduledAt ?? live.startedAt)?.toLocal();
    final host = live.isHost ? 'You' : (live.hostName.isNotEmpty ? live.hostName : (live.storeName ?? 'Creator'));
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.liveDetail(live.id)),
      media: _ClassicImage(
        url: live.coverUrl,
        icon: AppIcons.videoCamera,
        height: _kWideImg,
        chip: live.isLive
            ? const _PicChip(label: '● LIVE', color: AppColors.error)
            : _PicChip(label: when == null ? 'Coming up' : _startsLabel(when)),
      ),
      title: live.title,
      meta: [host, if (live.isLive && live.viewers > 0) '${Fmt.compact(live.viewers)} watching'].join(' · '),
      accent: live.hasTicket ? 'Ticket ✓' : (live.isFree ? 'Free' : Fmt.money(live.price)),
    );
  }
}

class MeetsRail extends StatelessWidget {
  const MeetsRail({super.key, this.title = 'Virtual Meets', this.subtitle = 'Webinars & 1:1 sessions — join in the app', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<StoreMeet>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: () => context.push(AppRoutes.meets),
      load: () => pinnedFirst<StoreMeet>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().meets(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().meets()).items,
        idOf: (m) => m.id,
        max: 10,
      ),
      itemBuilder: (context, m) => _MeetPoster(meet: m),
    );
  }
}

/// Meet = picture with the date (or LIVE), title, host · length, price.
class _MeetPoster extends StatelessWidget {
  const _MeetPoster({required this.meet});

  final StoreMeet meet;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final m = meet;
    final when = m.scheduledAt?.toLocal();
    final full = m.spotsLeft != null && m.spotsLeft! <= 0 && !m.isHost && !m.booked;
    final String accent;
    if (m.isHost) {
      accent = m.isLive ? 'You\'re live — rejoin' : 'Your meet';
    } else if (m.booked) {
      accent = m.isLive ? 'Join now' : 'Booked ✓';
    } else if (full) {
      accent = 'Fully booked';
    } else {
      accent = m.isFree ? 'Free' : Fmt.money(m.price);
    }
    return _ClassicCard(
      onTap: () => (m.isLive && (m.isHost || m.booked)) ? openMeetRoom(context, m.id) : context.push(AppRoutes.meetDetail(m.id)),
      media: _ClassicImage(
        url: m.coverUrl,
        icon: AppIcons.videoCamera,
        height: _kWideImg,
        chip: m.isLive
            ? const _PicChip(label: '● LIVE', color: AppColors.error)
            : _PicChip(label: when == null ? 'Soon' : '${when.day} ${_months[when.month - 1]} · ${TimeOfDay.fromDateTime(when).format(context)}'),
      ),
      title: m.title,
      meta: [m.isHost ? 'You' : m.hostName, '${m.durationMinutes} min', if (m.spotsLeft != null && !m.isHost && m.spotsLeft! > 0 && m.spotsLeft! <= 10) '${m.spotsLeft} left'].join(' · '),
      accent: accent,
      accentColor: full ? context.palette.textTertiary : null,
    );
  }
}

class CommunitiesRail extends StatelessWidget {
  const CommunitiesRail({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeRail<Community>(
      title: 'Trending communities',
      subtitle: 'Join the conversation',
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: () => context.push(AppRoutes.communities),
      load: () async => (await sl<CommunityRepository>().list()).items.take(10).toList(),
      itemBuilder: (context, c) => _CommunityCard(community: c),
    );
  }
}

/// "Digital products" — the newest things creators are selling.
class ProductsRail extends StatelessWidget {
  const ProductsRail({super.key, this.title = 'Digital products', this.subtitle = 'Courses, ebooks, templates — instant download', this.pinned = const [], this.onlyPinned = false});

  final List<String> pinned;
  final bool onlyPinned;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return HomeRail<DigitalProduct>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kSmallW,
      onSeeAll: () => context.push(AppRoutes.products),
      load: () => pinnedFirst<DigitalProduct>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().products(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().products(sort: 'popular')).items,
        idOf: (p) => p.id,
        max: 10,
      ),
      itemBuilder: (context, p) => _ProductCard(product: p),
    );
  }
}

/// Product = square picture, title, store, price.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final DigitalProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.storeProduct(p.id)),
      media: _ClassicImage(
        url: p.coverUrl,
        icon: AppIcons.package,
        height: _kSmallW,
        chip: p.owned ? const _PicChip(label: 'OWNED', icon: AppIcons.check, color: AppColors.success) : null,
      ),
      title: p.title,
      meta: p.storeName,
      accent: p.isFree ? 'Free' : Fmt.money(p.price),
    );
  }
}

class StoresRail extends StatelessWidget {
  const StoresRail({super.key, this.title = 'Creator stores', this.subtitle = 'Courses, ebooks, templates & more', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<StoreInfo>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: () => context.push(AppRoutes.stores),
      load: () => pinnedFirst<StoreInfo>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<StoreRepository>().stores(ids: ids)).items,
        loadRest: () async => (await sl<StoreRepository>().stores()).items,
        idOf: (s) => s.id,
        max: 10,
      ),
      itemBuilder: (context, s) => _Storefront(store: s),
    );
  }
}

/// Store = banner picture, name, tagline, sales.
class _Storefront extends StatelessWidget {
  const _Storefront({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.storePage(s.slug)),
      media: _ClassicImage(url: s.bannerUrl, icon: AppIcons.storeFilled, height: _kWideImg),
      title: s.name,
      meta: s.tagline.isEmpty ? 'Courses, guides & templates' : s.tagline,
      accent: s.stats.orders > 0 ? '${Fmt.compact(s.stats.orders)} sold' : 'New store',
    );
  }
}

// ---------------------------------------------------------------------------
// Hero header (greeting card with the user's key number)
// ---------------------------------------------------------------------------

class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.label, required this.value, this.caption, this.primaryAction, this.trailing});

  final String label;
  final String value;
  final String? caption;
  final Widget? primaryAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14141F), Color(0xFF26131C)]),
          boxShadow: [BoxShadow(color: const Color(0xFFF4511E).withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFF4511E).withValues(alpha: 0.45), Colors.transparent])),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.9, end: 1.1, duration: 3.seconds, curve: Curves.easeInOut),
            ),
            Positioned(
              left: -30,
              bottom: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFEC2A78).withValues(alpha: 0.35), Colors.transparent])),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: Colors.white70))),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(value, style: context.text.headlineMedium?.copyWith(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  if (caption != null) ...[
                    const SizedBox(height: 4),
                    Text(caption!, style: context.text.bodySmall?.copyWith(color: AppColors.sunrise)),
                  ],
                  if (primaryAction != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    primaryAction!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }
}

/// Small numbers row under the hero.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({super.key, required this.stats});

  final List<({String label, String value, IconData icon, Color color})> stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        children: [
          for (final (i, s) in stats.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(kHomeCardRadius), border: Border.all(color: palette.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(s.icon, size: 18, color: s.color),
                    const SizedBox(height: 6),
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(s.value, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                    Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 120.ms, duration: 350.ms);
  }
}

/// Section spacing helper.
const homeGap = SizedBox(height: AppSpacing.xl);

/// Home search: pill with a thin brand-gradient edge, orange search badge,
/// "Search" + a rotating keyword in brand orange, and the gradient filter
/// button. Keywords come from [hint] ("Search creators, lives, products…").
class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({super.key, this.hint = 'Search creators, brands, communities…'});

  final String hint;

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  late final List<String> _words = _wordsFrom(widget.hint);
  int _i = 0;
  bool _pressed = false;
  Timer? _timer;

  static List<String> _wordsFrom(String hint) {
    final words = hint
        .replaceFirst(RegExp(r'^\s*search\s*', caseSensitive: false), '')
        .replaceAll('…', '')
        .replaceAll('...', '')
        .split(',')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    return words.isEmpty ? const ['creators', 'brands', 'communities'] : words;
  }

  @override
  void initState() {
    super.initState();
    if (_words.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
        if (mounted) setState(() => _i = (_i + 1) % _words.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _open({bool filters = false}) {
    HapticFeedback.selectionClick();
    context.push(filters ? '${AppRoutes.search}?filters=1' : AppRoutes.search);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = context.isDark;
    const brand = Color(0xFFF4511E);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          // Thin gradient edge: outer gradient box, inner surface 1.4px smaller.
          child: Container(
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  brand.withValues(alpha: dark ? 0.55 : 0.45),
                  const Color(0xFFEC2A78).withValues(alpha: dark ? 0.35 : 0.22),
                  palette.border.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: dark
                  ? null
                  : [
                BoxShadow(color: brand.withValues(alpha: 0.10), blurRadius: 22, offset: const Offset(0, 8)),
                const BoxShadow(color: Color(0x0A101828), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(99),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _open,
                child: SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      const SizedBox(width: 7),
                      // Orange search badge.
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: brand.withValues(alpha: dark ? 0.18 : 0.10)),
                        child: const Icon(AppIcons.search, size: 19, color: brand),
                      ),
                      const SizedBox(width: 10),
                      // "Search" + rotating keyword.
                      Expanded(
                        child: Row(
                          children: [
                            Text('Search ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: palette.textSecondary)),
                            Expanded(
                              child: ClipRect(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 450),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, anim) => SlideTransition(
                                    position: Tween<Offset>(begin: const Offset(0, 0.7), end: Offset.zero).animate(anim),
                                    child: FadeTransition(opacity: anim, child: child),
                                  ),
                                  child: Align(
                                    key: ValueKey(_i),
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _words[_i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: brand, letterSpacing: -0.2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Gradient filter button with a soft glow.
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: brand.withValues(alpha: dark ? 0.35 : 0.30), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: Ink(
                              decoration: const BoxDecoration(gradient: _brandGradient, shape: BoxShape.circle),
                              child: InkWell(
                                onTap: () => _open(filters: true),
                                child: const SizedBox(width: 42, height: 42, child: Icon(AppIcons.sliders, color: Colors.white, size: 18)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, end: 0, duration: 350.ms, curve: Curves.easeOutCubic);
  }
}

// ---------------------------------------------------------------------------
// Vertical list section (thumbnail, title, subtitle)
// ---------------------------------------------------------------------------

/// Shows up to [max] rows; hidden when empty. Skeleton rows while loading.
class HomeListSection<T> extends StatefulWidget {
  const HomeListSection({
    super.key,
    required this.title,
    required this.load,
    required this.thumbnail,
    required this.titleOf,
    required this.subtitleOf,
    required this.onTap,
    this.subtitle,
    this.onSeeAll,
    this.trailingOf,
    this.max = 4,
  });

  final String title;
  final String? subtitle;
  final Future<List<T>> Function() load;
  final Widget Function(T item) thumbnail;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;
  final Widget? Function(T item)? trailingOf;
  final void Function(T item) onTap;
  final VoidCallback? onSeeAll;
  final int max;

  @override
  State<HomeListSection<T>> createState() => _HomeListSectionState<T>();
}

class _HomeListSectionState<T> extends State<HomeListSection<T>> with AutomaticKeepAliveClientMixin {
  late Future<List<T>> _future = _safeLoad();

  @override
  bool get wantKeepAlive => true;

  Future<List<T>> _safeLoad() async {
    try {
      return (await widget.load()).take(widget.max).toList();
    } catch (error) {
      debugPrint('[home] list section failed to load: $error');
      return <T>[];
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _safeLoad();
    });
  }

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_reload);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    return FutureBuilder<List<T>>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? <T>[];
        if (!loading && items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeSectionHeader(title: widget.title, subtitle: widget.subtitle, onSeeAll: widget.onSeeAll),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(kHomeCardRadius),
                    border: Border.all(color: palette.border.withValues(alpha: context.isDark ? 0.55 : 0.7)),
                    boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < (loading ? 3 : items.length); i++) ...[
                        if (i > 0) Divider(height: 1, indent: 76, color: palette.border),
                        if (loading)
                          const _SkeletonRow()
                        else
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(items[i]);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                              child: Row(
                                children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(kHomeButtonRadius), child: SizedBox(width: 48, height: 48, child: widget.thumbnail(items[i]))),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(widget.titleOf(items[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text(widget.subtitleOf(items[i]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  widget.trailingOf?.call(items[i]) ?? Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                                ],
                              ),
                            ),
                          ).animate(delay: (50 * i).ms).fadeIn(duration: 250.ms),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(kHomeButtonRadius))),
          const SizedBox(width: AppSpacing.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 12), const SizedBox(height: 8), bar(90, 10)]),
        ],
      ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6)),
    );
  }
}

/// Communities as cover cards: big cover, the community icon on it, name,
/// members/posts and a one-tap Join button.
class CommunitiesList extends StatelessWidget {
  const CommunitiesList({super.key, this.title = 'Trending communities', this.subtitle = 'Join the conversation', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  Widget build(BuildContext context) {
    return HomeRail<Community>(
      title: title,
      subtitle: subtitle,
      height: 222,
      itemWidth: _kWideW,
      onSeeAll: () => context.push(AppRoutes.communities),
      load: () => pinnedFirst<Community>(
        pinned: pinned,
        onlyPinned: onlyPinned,
        loadPinned: (ids) async => (await sl<CommunityRepository>().list(ids: ids)).items,
        loadRest: () async => (await sl<CommunityRepository>().list()).items,
        idOf: (c) => c.id,
      ),
      itemBuilder: (context, c) => _CommunityCard(community: c),
    );
  }
}

/// Community = cover picture, name, category · members, price / free.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    final category = c.category?.label ?? '';
    final joined = c.membership?.status == MembershipStatus.active;
    return _ClassicCard(
      onTap: () => context.push(AppRoutes.communityDetail(c.slug)),
      media: _ClassicImage(
        url: c.coverImageUrl,
        icon: AppIcons.users,
        height: _kWideImg,
        chip: c.isPaid ? const _PicChip(label: 'Paid', icon: AppIcons.crown) : (c.isPrivate ? const _PicChip(label: 'Private', icon: AppIcons.lock) : null),
      ),
      title: c.isVerified ? '${c.name} ✓' : c.name,
      meta: [if (category.isNotEmpty) category, '${Fmt.compact(c.memberCount)} ${c.memberCount == 1 ? 'member' : 'members'}'].join(' · '),
      accent: joined ? 'Joined ✓' : (c.isPaid ? communityPriceLabel(c) : (c.isPrivate ? 'Request to join' : 'Free to join')),
    );
  }
}

/// Picture or, when there is none, a soft brand tint with a faded icon.
/// ([colors] is kept for older calls; everything uses the one tint now.)
Widget _coverOrGradient(String? url, {required IconData icon, required List<Color> colors}) {
  if (url != null && url.isNotEmpty) return _netImage(url, icon: icon);
  return ColoredBox(
    color: const Color(0x14F4511E),
    child: Stack(
      children: [
        Positioned(right: -14, top: -10, child: Icon(icon, size: 96, color: const Color(0x1FF4511E))),
        Center(child: Icon(icon, size: 26, color: const Color(0x80F4511E))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Small pieces used by the cards above
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Admin-managed sections (order, titles, pinned items)
// ---------------------------------------------------------------------------

class _SectionConfig {
  const _SectionConfig({required this.key, required this.title, required this.subtitle, required this.pinned, this.onlyPinned = false});

  factory _SectionConfig.fromJson(Map<String, dynamic> json) => _SectionConfig(
    key: J.str(json, 'key'),
    title: J.str(json, 'title'),
    subtitle: J.str(json, 'subtitle'),
    pinned: [for (final id in (json['pinned'] is List ? json['pinned'] as List : const [])) id.toString()],
    onlyPinned: J.boolean(json, 'onlyPinned'),
  );

  final String key;
  final String title;
  final String subtitle;
  final List<String> pinned;
  final bool onlyPinned;
}

/// All discover sections, in the order (and with the titles and pinned
/// items) set in the admin panel → App home screen. Falls back to the
/// built-in order if the layout can't load.
/// The admin's "brands" section (title / pinned), shared with [HomeBrandsSlot].
/// null = brands are hidden in the admin panel.
final ValueNotifier<_SectionConfig?> _brandsSection = ValueNotifier<_SectionConfig?>(null);

/// Put this where the "Brands on Fanitt" logo strip should sit when the
/// screen uses `HomeSections(showBrands: false)` — e.g. just above a
/// card at the very bottom of the home.
class HomeBrandsSlot extends StatelessWidget {
  const HomeBrandsSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_SectionConfig?>(
      valueListenable: _brandsSection,
      builder: (context, c, _) => c == null
          ? const SizedBox.shrink()
          : BrandLogoStrip(
        key: ValueKey('brands-${c.title}-${c.onlyPinned}-${c.pinned.join(',')}'),
        title: c.title.isEmpty ? 'Brands on Fanitt' : c.title,
        pinned: c.pinned,
        onlyPinned: c.onlyPinned,
      ),
    );
  }
}

class HomeSections extends StatefulWidget {
  const HomeSections({super.key, this.campaignsSeeAll, this.showBrands = true, this.showCampaigns = true, this.hide = const {}});

  /// Section keys this screen places itself (or doesn't want), e.g. {'live'}.
  final Set<String> hide;

  final VoidCallback? campaignsSeeAll;

  /// false = no "Open campaigns" rail (brands shouldn't see other brands' campaigns).
  final bool showCampaigns;

  /// false = the screen places [HomeBrandsSlot] itself (lower down).
  final bool showBrands;

  @override
  State<HomeSections> createState() => _HomeSectionsState();
}

class _HomeSectionsState extends State<HomeSections> {
  static const _fallback = ['creators', 'campaigns', 'live', 'meets', 'brands', 'communities', 'products', 'stores'];
  List<_SectionConfig>? _sections;

  @override
  void initState() {
    super.initState();
    _load();
    homeRefreshTick.addListener(_load);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sections = (await sl<ApiClient>().get(
        '/home/layout',
        parser: (d) => J.list(J.asMap(d), 'sections', _SectionConfig.fromJson),
      ))
          .data;
      if (mounted) setState(() => _sections = sections);
    } catch (_) {
      if (mounted && _sections == null) {
        setState(() => _sections = [for (final k in _fallback) _SectionConfig(key: k, title: '', subtitle: '', pinned: const [])]);
      }
    }
    _brandsSection.value = _sections?.where((c) => c.key == 'brands').firstOrNull;
  }

  Widget _build(_SectionConfig c) {
    String t(String fallback) => c.title.isEmpty ? fallback : c.title;
    String sub(String fallback) => c.subtitle.isEmpty ? fallback : c.subtitle;
    return switch (c.key) {
    // Creators live now / coming up — round photos with names.
      'live' => LiveNowStories(refresh: homeRefreshTick),
      'creators' => CreatorsRail(title: t('Top creators'), subtitle: sub('Discover creators to work with'), pinned: c.pinned, onlyPinned: c.onlyPinned),
      'campaigns' => CampaignsRail(title: t('Open campaigns'), subtitle: sub('Paid & barter collaborations'), pinned: c.pinned, onlyPinned: c.onlyPinned, onSeeAll: widget.campaignsSeeAll),
      'meets' => MeetsRail(title: t('Virtual Meets'), subtitle: sub('Webinars & 1:1 sessions — join in the app'), pinned: c.pinned, onlyPinned: c.onlyPinned),
    // Brands now show as a moving logo strip at the bottom (see build).
      'brands' => const SizedBox.shrink(),
      'communities' => CommunitiesList(title: t('Trending communities'), subtitle: sub('Join the conversation'), pinned: c.pinned, onlyPinned: c.onlyPinned),
      'products' => ProductsRail(title: t('Digital products'), subtitle: sub('Courses, ebooks, templates — instant download'), pinned: c.pinned, onlyPinned: c.onlyPinned),
    // Creator stores are reached from their products ("Visit store").
      'stores' => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the moment the admin's products-shop switch arrives or changes
    // (off = no "Fanitt Store" physical-products section).
    return ValueListenableBuilder<bool>(
      valueListenable: FeatureFlags.store,
      builder: (context, storeOn, _) => _sectionsFor(storeOn),
    );
  }

  Widget _sectionsFor(bool storeOn) {
    final all = _sections;
    if (all == null) return const SizedBox.shrink();
    final sections = all;
    final brands = sections.where((c) => c.key == 'brands').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Creators live right now — round photos in one row (hidden when no one is live).
        // Admin layout has no 'live' section → show the live row at the top instead.
        if (!widget.hide.contains('livenow') && !widget.hide.contains('live') && !sections.any((c) => c.key == 'live')) LiveNowStories(refresh: homeRefreshTick),
        // Keyed by the layout so a changed order or pin list rebuilds the rails.
        for (final c in sections) ...[
          // Fanitt Store (physical products) sits just before Digital products.
          if (storeOn && c.key == 'products' && !widget.hide.contains('shop')) ShopHomeSection(refresh: homeRefreshTick),
          if (c.key != 'brands' && c.key != 'stores' && !widget.hide.contains(c.key) && (widget.showCampaigns || c.key != 'campaigns'))
            KeyedSubtree(key: ValueKey('${c.key}-${c.title}-${c.onlyPinned}-${c.pinned.join(',')}'), child: _build(c)),
        ],
        if (storeOn && !sections.any((c) => c.key == 'products') && !widget.hide.contains('shop')) ShopHomeSection(refresh: homeRefreshTick),
        // Brands: a slow, endless logo strip at the very bottom.
        if (brands != null && widget.showBrands)
          BrandLogoStrip(
            key: ValueKey('brands-${brands.title}-${brands.onlyPinned}-${brands.pinned.join(',')}'),
            title: brands.title.isEmpty ? 'Brands on Fanitt' : brands.title,
            pinned: brands.pinned,
            onlyPinned: brands.onlyPinned,
          ),
      ],
    );
  }
}

/// Brands on Fanitt — a wall of logos in 2 endless rows (right → left,
/// then left → right). Touch to pause / drag, tap a logo to open the brand.
class BrandLogoStrip extends StatefulWidget {
  const BrandLogoStrip({super.key, this.title = 'Brands on Fanitt', this.pinned = const [], this.onlyPinned = false});

  final String title;
  final List<String> pinned;
  final bool onlyPinned;

  @override
  State<BrandLogoStrip> createState() => _BrandLogoStripState();
}

class _BrandLogoStripState extends State<BrandLogoStrip> with SingleTickerProviderStateMixin {
  /// Pixels per second for each row — slightly different so the wall feels alive.
  static const _speeds = [24.0];
  static const _itemWidth = 82.0;
  static const _rowHeight = 94.0;

  final _scrolls = List.generate(1, (_) => ScrollController());
  late final Ticker _ticker = createTicker(_tick);
  List<BrandListItem> _brands = const [];
  List<List<BrandListItem>> _rows = const [];
  bool _held = false;
  Duration _last = Duration.zero;

  /// Up to 3 logos fit the screen — show them still in one row.
  bool get _moving => _brands.length > 3;

  @override
  void initState() {
    super.initState();
    _load();
    homeRefreshTick.addListener(_load);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    _ticker.dispose();
    for (final c in _scrolls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only the brands marked in the admin panel (Home screen sections →
  /// Brands → pinned), in that order, at most this many.
  static const _maxBrands = 30;

  /// Splits the brands into 2 rows — first half on top, second half below
  /// (30 brands → 15 + 15). With only a few, both rows show all of them,
  /// shifted, so the rows never look the same.
  static List<List<BrandListItem>> _split(List<BrandListItem> all) => [all];

  Future<void> _load() async {
    if (widget.pinned.isEmpty) {
      if (mounted) setState(() => _brands = const []);
      return;
    }
    try {
      final ids = widget.pinned.take(_maxBrands).toList();
      final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      final brands = [...(await sl<BrandsRepository>().list(ids: ids, limit: _maxBrands)).items]
        ..sort((a, b) => (order[a.profile.id] ?? 999).compareTo(order[b.profile.id] ?? 999));
      if (!mounted) return;
      setState(() {
        _brands = brands;
        _rows = _split(brands);
      });
      if (_moving && !_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } catch (_) {
      // No strip when brands can't load.
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !_moving) return;
    for (var r = 0; r < _scrolls.length; r++) {
      final c = _scrolls[r];
      if (c.hasClients) c.jumpTo(c.offset + _speeds[r] * dt);
    }
  }

  void _open(BrandListItem b) {
    if (b.profile.slug.isEmpty) return;
    HapticFeedback.selectionClick();
    context.push(AppRoutes.brandProfile(b.profile.slug));
  }

  Widget _logo(BrandListItem b) {
    final name = b.profile.companyName.trim().isEmpty ? 'Brand' : b.profile.companyName.trim();
    final verified = b.profile.verificationStatus == VerificationStatus.verified;
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x1FF4511E)),
      child: Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w800))),
    );
    final palette = context.palette;
    return GestureDetector(
      onTap: () => _open(b),
      child: SizedBox(
        width: _itemWidth,
        child: Column(
          children: [
            // Logo tile — white rounded square, like a partner wall.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: palette.border.withValues(alpha: 0.7)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox.expand(
                      child: (b.logoUrl ?? '').isEmpty
                          ? fallback
                          : CachedNetworkImage(
                        imageUrl: b.logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const ColoredBox(color: Color(0xFFF3F4F7)),
                        errorWidget: (_, _, _) => fallback,
                      ),
                    ),
                  ),
                ),
                if (verified)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(1.2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                      child: const Icon(AppIcons.sealCheck, size: 13, color: AppColors.info),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.textSecondary, letterSpacing: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One endless row. Row 1 slides right → left; row 2 (reverse) slides
  /// left → right.
  Widget _row(int r) {
    final items = _rows[r];
    return SizedBox(
      height: _rowHeight,
      child: ListView.builder(
        controller: _scrolls[r],
        scrollDirection: Axis.horizontal,
        reverse: r == 1,
        padding: const EdgeInsets.only(top: 5),
        itemBuilder: (context, i) => _logo(items[i % items.length]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_brands.isEmpty) return const SizedBox.shrink();
    final Widget strip = _moving
        ? Listener(
      onPointerDown: (_) => _held = true,
      onPointerUp: (_) => _held = false,
      onPointerCancel: (_) => _held = false,
      child: _row(0),
    )
        : SizedBox(
      height: _rowHeight,
      child: Center(
        child: ListView(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(top: 5),
          children: [for (final b in _brands) _logo(b)],
        ),
      ),
    );

    // Same look as every other section: header, then a plain row of logos.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl - 4, bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader(title: widget.title, subtitle: '${_brands.length} brands working with creators'),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: EdgeInsets.zero,
            child: SizedBox(
              child: ClipRect(
                // Logos fade out at both edges.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                    stops: [0, 0.07, 0.93, 1],
                  ).createShader(r),
                  child: strip,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}