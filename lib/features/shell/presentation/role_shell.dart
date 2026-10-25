// File: lib/features/shell/presentation/role_shell.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/app_rating.dart';
import '../../../core/services/feature_flags.dart';
import '../../../core/theme/app_palette.dart';

class ShellDestination {
  const ShellDestination(this.label, this.icon, this.selectedIcon, {this.whenStoreOff});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Shown instead of this tab's label and icons while the Fanitt Store is off.
  final ShellDestination? whenStoreOff;
}

/// Bottom-navigation frame shared by the creator, brand, agency and fan areas.
///
/// The bar slides away while you scroll down (more room for content) and
/// comes back as soon as you scroll up, reach the top, or switch tabs.
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.navigationShell, required this.destinations});

  final StatefulNavigationShell navigationShell;
  final List<ShellDestination> destinations;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 200),
    value: 1, // 1 = shown, 0 = hidden
  );
  late final Animation<double> _size = CurvedAnimation(parent: _bar, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

  /// How far you scroll down (px) before the bar hides — small jitters don't hide it.
  static const double _hideAfter = 24;
  double _downBy = 0;

  StatefulNavigationShell get _shell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    // On Home: maybe ask for a Google Play rating (rules in AppRating).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskRating());
  }

  @override
  void didUpdateWidget(covariant RoleShell old) {
    super.didUpdateWidget(old);
    // New tab → always show the bar.
    if (old.navigationShell.currentIndex != _shell.currentIndex) {
      _show();
      _maybeAskRating();
    }
  }

  void _maybeAskRating() {
    if (mounted && _shell.currentIndex == 0) AppRating.maybeAsk(context);
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  void _show() {
    _downBy = 0;
    if (_bar.status != AnimationStatus.forward && _bar.value < 1) _bar.forward();
  }

  void _hide() {
    if (_bar.status != AnimationStatus.reverse && _bar.value > 0) _bar.reverse();
  }

  bool _onScroll(ScrollNotification n) {
    final m = n.metrics;
    // Only vertical lists (story rings, carousels etc. scroll sideways).
    if (m.axis != Axis.vertical) return false;

    // Nothing to scroll, or back at the top → show.
    if (m.maxScrollExtent <= 0 || m.pixels <= m.minScrollExtent) {
      _show();
      return false;
    }

    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.forward) _show(); // finger moving down = scrolling up
      if (n.direction == ScrollDirection.idle) _downBy = 0;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final delta = n.scrollDelta ?? 0;
      if (delta > 0) {
        _downBy += delta;
        if (_downBy > _hideAfter) _hide();
      } else if (delta < 0) {
        _downBy = 0;
        _show();
      }
    }
    return false; // let others (pull-to-refresh, paging) see it too
  }

  void _onSelected(int index) {
    if (index != _shell.currentIndex) HapticFeedback.selectionClick();
    _show();
    // Tapping the active tab again returns it to its first screen.
    _shell.goBranch(index, initialLocation: index == _shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final onFirstTab = _shell.currentIndex == 0;
    // Back on any other tab goes to the first tab; only the first tab exits the app.
    return PopScope(
      canPop: onFirstTab,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || onFirstTab) return;
        HapticFeedback.selectionClick();
        _shell.goBranch(0);
      },
      child: Scaffold(
        body: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: _shell),
        bottomNavigationBar: SizeTransition(
          sizeFactor: _size,
          axisAlignment: -1, // slides down out of view
          child: ValueListenableBuilder<bool>(
            valueListenable: FeatureFlags.store,
            builder: (context, storeOn, _) => _ProNavBar(
              currentIndex: _shell.currentIndex,
              onSelected: _onSelected,
              destinations: [
                for (final d in widget.destinations) (!storeOn && d.whenStoreOff != null) ? d.whenStoreOff! : d,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom bar: a floating rounded dock. The selected tab grows into a
/// brand-gradient pill with a white filled icon and its label; the others
/// are clean outline icons. Width changes animate smoothly.
class _ProNavBar extends StatelessWidget {
  const _ProNavBar({required this.currentIndex, required this.onSelected, required this.destinations});

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<ShellDestination> destinations;

  static const double _dockHeight = 64;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = context.isDark;
    final count = destinations.length;
    final index = currentIndex.clamp(0, count - 1);

    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: dark
                  ? const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))]
                  : const [BoxShadow(color: Color(0x1F101828), blurRadius: 28, offset: Offset(0, 10)), BoxShadow(color: Color(0x0A101828), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: _dockHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: dark ? 0.9 : 0.96),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: palette.border.withValues(alpha: dark ? 0.5 : 0.7)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // The selected tab gets more room for its label.
                      final selectedW = (box.maxWidth * (count >= 5 ? 0.34 : 0.38)).clamp(100.0, 156.0);
                      final otherW = (box.maxWidth - selectedW) / (count - 1);
                      return Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              width: i == index ? selectedW : otherW,
                              height: _dockHeight,
                              child: _NavItem(destination: destinations[i], selected: i == index, onTap: () => onSelected(i)),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _down = false;

  static const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final d = widget.destination;
    final on = widget.selected;

    return Semantics(
      button: true,
      selected: on,
      label: d.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              height: 46,
              padding: EdgeInsets.symmetric(horizontal: on ? 14 : 0),
              decoration: BoxDecoration(
                gradient: on ? _gradient : null,
                borderRadius: BorderRadius.circular(23),
                boxShadow: on ? const [BoxShadow(color: Color(0x59F4511E), blurRadius: 14, offset: Offset(0, 6))] : null,
              ),
              // Long labels shrink to fit instead of overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: Tween<double>(begin: 0.6, end: 1).animate(anim), child: FadeTransition(opacity: anim, child: child)),
                      child: Icon(
                        on ? d.selectedIcon : d.icon,
                        key: ValueKey(on),
                        size: on ? 21 : 24,
                        color: on ? Colors.white : palette.textSecondary,
                      ),
                    ),
                    // Label only on the selected tab — grows in.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: on
                          ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          d.label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: -0.1),
                        ),
                      )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}