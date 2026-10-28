// File: lib/features/store/presentation/live/live_discover_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/async_view.dart';
import '../../data/live_call_models.dart';
import '../../data/store_repository.dart';
import 'live_now_stories.dart' show LiveStoryAvatar;

const _liveRed = Color(0xFFFF3B5C);

enum _Show {
  live('Live now', 'Creators streaming right now', AppIcons.broadcast),
  upcoming('Upcoming', 'Lives planned for later', AppIcons.calendar);

  const _Show(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

/// Other creators' lives — the same round photos as on Home.
/// The filter icon in the app bar switches between Live now and Upcoming.
/// Your own lives are in My store.
class LiveDiscoverScreen extends StatefulWidget {
  const LiveDiscoverScreen({super.key});

  /// Route for this screen (registered in app_router.dart).
  static const route = '/app/lives';

  @override
  State<LiveDiscoverScreen> createState() => _LiveDiscoverScreenState();
}

class _LiveDiscoverScreenState extends State<LiveDiscoverScreen> {
  List<LiveStream>? _lives;
  String? _error;
  _Show? _show;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep "who's live" fresh while the screen is open.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await sl<StoreRepository>().discoverLives(limit: 60);
      if (!mounted) return;
      setState(() {
        _lives = all.where((l) => !l.isHost && (l.isLive || l.status == LiveStatus.scheduled)).toList();
        _error = null;
      });
    } catch (_) {
      if (mounted && _lives == null) setState(() => _error = 'Couldn’t load lives.');
    }
  }

  Future<void> _pickFilter(_Show current) async {
    HapticFeedback.selectionClick();
    final picked = await showAppSheet<_Show>(
      context,
      builder: (sheet) => SheetBody(
        title: 'Show',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _Show.values) ...[
              _Option(show: s, selected: s == current, onTap: () => Navigator.of(sheet).pop(s)),
              if (s != _Show.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _show = picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lives = _lives;
    final liveNow = [for (final l in lives ?? const <LiveStream>[]) if (l.isLive) l]..sort((a, b) => b.viewers.compareTo(a.viewers));
    final upcoming = [for (final l in lives ?? const <LiveStream>[]) if (!l.isLive) l]
      ..sort((a, b) => (a.scheduledAt ?? DateTime(2100)).compareTo(b.scheduledAt ?? DateTime(2100)));
    // Opens on Upcoming when nobody is live.
    final show = _show ?? (liveNow.isEmpty && upcoming.isNotEmpty ? _Show.upcoming : _Show.live);
    final items = show == _Show.live ? liveNow : upcoming;
    final other = show == _Show.live ? _Show.upcoming : _Show.live;
    final otherCount = show == _Show.live ? upcoming.length : liveNow.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: lives == null ? null : () => _pickFilter(show),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(AppIcons.sliders, color: palette.textPrimary),
                if (show == _Show.upcoming)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 1.5)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator.adaptive(
        color: AppColors.primary,
        onRefresh: _load,
        child: lives == null && _error == null
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.lg),
                child: _Header(show: show, count: items.length),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: MessageView(
                  icon: show.icon,
                  title: show == _Show.live ? 'No one is live right now' : 'Nothing planned yet',
                  message: show == _Show.live ? 'Pull down to check again.' : 'When creators plan a live, it shows up here.',
                  action: otherCount == 0
                      ? null
                      : FilledButton(
                    onPressed: () => setState(() => _show = other),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: const StadiumBorder()),
                    child: Text('See ${other.label.toLowerCase()} · $otherCount'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter - 4, 0, AppSpacing.gutter - 4, AppSpacing.xxl),
                sliver: SliverLayoutBuilder(
                  builder: (context, c) {
                    final cols = c.crossAxisExtent < 340 ? 3 : 4;
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 18, crossAxisSpacing: 4, mainAxisExtent: 116),
                      itemCount: items.length,
                      itemBuilder: (context, i) => Center(
                        child: LiveStoryAvatar(key: ValueKey(items[i].id), live: items[i], size: 68)
                            .animate(delay: (30 * i.clamp(0, 12)).ms)
                            .fadeIn(duration: 240.ms)
                            .scale(begin: const Offset(0.88, 0.88), curve: Curves.easeOutBack),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "● Live now · 3" (or "Upcoming · 5") with one line under it.
class _Header extends StatelessWidget {
  const _Header({required this.show, required this.count});

  final _Show show;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (show == _Show.live && count > 0) ...[
              Container(width: 9, height: 9, decoration: const BoxDecoration(color: _liveRed, shape: BoxShape.circle))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fade(begin: 1, end: 0.3, duration: 700.ms),
              const SizedBox(width: 8),
            ],
            Text(show.label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: palette.textPrimary)),
            const SizedBox(width: 6),
            Text('· $count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: palette.textSecondary)),
          ],
        ),
        const SizedBox(height: 2),
        Text(show == _Show.live ? 'Tap a creator to join' : 'Tap a creator to see time and ticket', style: TextStyle(fontSize: 13, color: palette.textSecondary)),
      ],
    ).animate(key: ValueKey(show)).fadeIn(duration: 250.ms);
  }
}

/// One choice in the filter sheet: icon, name, one line, radio.
class _Option extends StatelessWidget {
  const _Option({required this.show, required this.selected, required this.onTap});

  final _Show show;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = show == _Show.live ? _liveRed : palette.textPrimary;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.4 : 1)),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: Icon(show.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(show.label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                    Text(show.hint, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 6 : 2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}