import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';

class ShellDestination {
  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
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
  void didUpdateWidget(covariant RoleShell old) {
    super.didUpdateWidget(old);
    // New tab → always show the bar.
    if (old.navigationShell.currentIndex != _shell.currentIndex) _show();
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.palette.border)),
            ),
            child: NavigationBar(
              selectedIndex: _shell.currentIndex,
              onDestinationSelected: _onSelected,
              destinations: [
                for (final destination in widget.destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                    tooltip: destination.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}