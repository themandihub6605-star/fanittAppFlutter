import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../data/story_repository.dart';
import '../story_viewer_screen.dart';

const _ring = LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFF4511E), Color(0xFFEC2A78), Color(0xFF7C4DFF)]);

/// Round story rings at the top of the feed. "Your story" first for
/// creators and brands (tap + to add one).
class StoriesBar extends StatefulWidget {
  const StoriesBar({super.key, required this.canPost, required this.onAddStory, this.refresh});

  final bool canPost;
  final Future<bool> Function() onAddStory;

  /// Fires when the feed is pulled to refresh.
  final Listenable? refresh;

  @override
  State<StoriesBar> createState() => _StoriesBarState();
}

class _StoriesBarState extends State<StoriesBar> {
  List<StoryGroup>? _groups;

  @override
  void initState() {
    super.initState();
    _load();
    widget.refresh?.addListener(_load);
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = await StoryRepository.i.feed();
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      if (mounted && _groups == null) setState(() => _groups = const []);
    }
  }

  Future<void> _open(int index) async {
    final groups = _groups ?? const <StoryGroup>[];
    HapticFeedback.selectionClick();
    final updated = await StoryViewerScreen.open(context, groups: groups, index: index);
    if (!mounted) return;
    if (updated != null) setState(() => _groups = updated);
    if (updated == null || updated.length != groups.length) _load();
  }

  Future<void> _add() async {
    if (await widget.onAddStory() && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) return const SizedBox(height: 96);
    final mineIndex = groups.indexWhere((g) => g.isMine);
    final others = [for (var i = 0; i < groups.length; i++) if (i != mineIndex) i];
    if (!widget.canPost && others.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 2, AppSpacing.gutter, 0),
        children: [
          if (widget.canPost)
            _Ring(
              label: 'Your story',
              avatarUrl: mineIndex >= 0 ? groups[mineIndex].author.avatarUrl : '',
              initials: mineIndex >= 0 ? groups[mineIndex].author.initials : '+',
              state: mineIndex >= 0 ? _RingState.seen : _RingState.none,
              showPlus: true,
              onTap: mineIndex >= 0 ? () => _open(mineIndex) : _add,
              onPlus: _add,
            ),
          for (final i in others)
            _Ring(
              label: groups[i].author.name,
              avatarUrl: groups[i].author.avatarUrl,
              initials: groups[i].author.initials,
              state: groups[i].hasUnseen ? _RingState.unseen : _RingState.seen,
              onTap: () => _open(i),
            ),
        ],
      ),
    );
  }
}

enum _RingState { none, unseen, seen }

class _Ring extends StatelessWidget {
  const _Ring({required this.label, required this.avatarUrl, required this.initials, required this.state, required this.onTap, this.showPlus = false, this.onPlus});

  final String label;
  final String avatarUrl;
  final String initials;
  final _RingState state;
  final VoidCallback onTap;
  final bool showPlus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const size = 64.0;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size + 6,
                    height: size + 6,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: state == _RingState.unseen ? _ring : null,
                      color: state == _RingState.seen ? palette.border : (state == _RingState.none ? Colors.transparent : null),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: palette.background),
                      child: ClipOval(
                        child: avatarUrl.isEmpty
                            ? Container(
                          color: palette.surfaceMuted,
                          alignment: Alignment.center,
                          child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: palette.textSecondary)),
                        )
                            : AppNetworkImage(url: avatarUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  if (showPlus)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: onPlus,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2)),
                          child: const Icon(AppIcons.plus, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall?.copyWith(fontSize: 11.5, color: palette.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}