// File: lib/features/shell/presentation/role_shell.dart
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/enums/user_role.dart';
import '../../../core/services/app_rating.dart';
import '../../../core/services/feature_flags.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_tour.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // First time on this account → the walkthrough; otherwise maybe ask
      // for a Google Play rating (rules in AppRating). Never both at once.
      final id = _tourId();
      if (id != null && !AppTour.seen(id)) {
        Future<void>.delayed(const Duration(milliseconds: 1200), () {
          if (mounted && _shell.currentIndex == 0) AppTour.start(context, id: id, steps: _tourSteps());
        });
      } else {
        _maybeAskRating();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // First-time walkthrough — one per role, shown once per account.
  // ---------------------------------------------------------------------------

  UserRole? get _role {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.role : null;
  }

  String? _tourId() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return null;
    final role = auth.user.role;
    // Agencies have their own dashboard — no walkthrough for them.
    if (role != UserRole.creator && role != UserRole.brand && role != UserRole.fan) return null;
    return '${role.name}_${auth.user.id}';
  }

  List<TourStep> _tourSteps() {
    final steps = <TourStep>[];
    void tab(String label, String title, String body) {
      final i = widget.destinations.indexWhere((d) => d.label == label);
      if (i >= 0 && i < 5) steps.add(TourStep(target: TourTargets.tab(i), title: title, body: body));
    }

    void home(GlobalKey key, String title, String body) => steps.add(TourStep(target: key, title: title, body: body));

    switch (_role) {
      case UserRole.creator:
        home(TourTargets.quickActions, 'Everything in one tap', 'Your store, Live, Live sessions, Communities and Plans. Tap More for the rest.');
        home(TourTargets.search, 'Find anything', 'Search creators, brands, stores and more.');
        tab('Feed', 'Share your work', 'Post photos, reels and stories — and see what other creators share.');
        tab('Campaigns', 'Want paid brand deals?', 'Open campaigns, send proposals and track every deal here.');
        tab('Messages', 'Talk to brands', 'All your chats with brands and fans in one place.');
        tab('Profile', 'Your account & settings', 'Edit your profile, see your earnings and open Settings & more.');
        tab('Home', 'Your control center', 'Come back to Home for everything new.');
      case UserRole.brand:
        home(TourTargets.quickActions, 'Run your brand from here', 'My campaigns, Find creators, Live, Live sessions and Communities.');
        home(TourTargets.search, 'Find the right creators', 'Search creators, stores and more by name or niche.');
        tab('Feed', 'Show your brand', 'Post photos, reels and stories, and see what creators share.');
        tab('Messages', 'Chat with creators', 'Every conversation with the creators you work with.');
        tab('Profile', 'Your brand profile', 'Edit your brand page, see your plan and open Settings & more.');
        tab('Home', 'Your control center', 'Come back to Home for everything new.');
      case UserRole.fan:
        home(TourTargets.quickActions, 'Everything for fans', 'Fanitt Store, Live, Live sessions, Communities and more. Tap More for the rest.');
        home(TourTargets.search, 'Find anything', 'Search creators, lives, products and stores.');
        tab('Feed', 'See what creators post', 'Photos, reels and stories from the creators you follow.');
        tab('Creators', 'Discover creators', 'Find creators you love and follow them.');
        tab('Messages', 'Chat with creators', 'Your conversations, all in one place.');
        tab('Profile', 'Your library & orders', 'Purchases, orders, saved posts and Settings & more.');
        tab('Home', 'Your control center', 'Come back to Home for everything new.');
      default:
        break;
    }
    return steps;
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
    // Not on top of (or right after starting) the walkthrough.
    final id = _tourId();
    if (AppTour.isRunning || (id != null && !AppTour.seen(id))) return;
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
                              // Keyed so the first-time walkthrough can point at each tab.
                              child: KeyedSubtree(
                                key: i < 5 ? TourTargets.tab(i) : null,
                                child: _NavItem(destination: destinations[i], selected: i == index, onTap: () => onSelected(i)),
                              ),
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