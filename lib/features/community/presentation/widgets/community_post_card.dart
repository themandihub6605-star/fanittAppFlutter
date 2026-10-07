import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/community_repository.dart';
import '../community_comments_screen.dart';
import 'community_post_media.dart';

/// A community post: author, badges, text, media, poll, like & comments.
/// Owns its optimistic updates and reports changes through [onChanged].
class CommunityPostCard extends StatefulWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.myUserId,
    required this.canInteract,
    required this.canModerate,
    required this.onChanged,
    required this.onDeleted,
  });

  final CommunityPost post;
  final String? myUserId;
  final bool canInteract;
  final bool canModerate;
  final ValueChanged<CommunityPost> onChanged;
  final VoidCallback onDeleted;

  @override
  State<CommunityPostCard> createState() => _CommunityPostCardState();
}

class _CommunityPostCardState extends State<CommunityPostCard> {
  bool _busy = false;

  CommunityPost get _post => widget.post;
  bool get _isAuthor => widget.myUserId != null && _post.author.id == widget.myUserId;
  CommunityRepository get _repo => sl<CommunityRepository>();

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _like() async {
    if (!widget.canInteract) {
      AppSnackbar.info(context, 'Join the community to like posts');
      return;
    }
    HapticFeedback.lightImpact();
    final before = _post;
    widget.onChanged(before.copyWith(isLiked: !before.isLiked, likeCount: before.likeCount + (before.isLiked ? -1 : 1)));
    try {
      final res = await _repo.likePost(before.id);
      widget.onChanged(before.copyWith(isLiked: res.liked, likeCount: res.likeCount));
    } on ApiException catch (error) {
      widget.onChanged(before);
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  Future<void> _vote(int index) => _run(() async {
    HapticFeedback.selectionClick();
    final poll = await _repo.vote(_post.id, index);
    widget.onChanged(_post.copyWith(poll: poll));
  });

  Future<void> _openComments() async {
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => CommunityCommentsScreen(
          postId: _post.id,
          initialCount: _post.commentCount,
          canComment: widget.canInteract,
          canModerate: widget.canModerate,
          myUserId: widget.myUserId,
        ),
      ),
    );
    if (count != null && count != _post.commentCount) widget.onChanged(_post.copyWith(commentCount: count));
  }

  Future<void> _edit() async {
    final controller = TextEditingController(text: _post.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit post'),
        content: TextField(controller: controller, maxLines: 6, minLines: 3, maxLength: 3000, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text == _post.text) return;
    await _run(() async {
      final updated = await _repo.editPost(_post.id, text);
      widget.onChanged(_post.copyWith(text: updated.text, editedAt: updated.editedAt));
    });
  }

  Future<void> _pin() => _run(() async {
    final pinned = await _repo.togglePin(_post.id);
    widget.onChanged(_post.copyWith(isPinned: pinned));
    if (mounted) AppSnackbar.success(context, pinned ? 'Pinned to the top' : 'Unpinned');
  });

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: 'Delete this post?',
      message: 'The post and all its comments will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _run(() async {
      await _repo.deletePost(_post.id);
      widget.onDeleted();
    });
  }

  void _menu() {
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetBody(
        title: 'Post options',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isAuthor && _post.text.isNotEmpty)
              ListTile(leading: const Icon(AppIcons.pencil), title: const Text('Edit'), onTap: () { Navigator.pop(ctx); _edit(); }),
            if (widget.canModerate)
              ListTile(
                leading: const Icon(AppIcons.pushPin),
                title: Text(_post.isPinned ? 'Unpin' : 'Pin to top'),
                onTap: () { Navigator.pop(ctx); _pin(); },
              ),
            ListTile(
              leading: const Icon(AppIcons.trash, color: AppColors.error),
              title: const Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () { Navigator.pop(ctx); _delete(); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final post = _post;

    return AppCard(
      color: post.isAnnouncement ? palette.primarySoft : null,
      borderColor: post.isAnnouncement ? AppColors.primary.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isPinned || post.isAnnouncement)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  if (post.isPinned) _Tag(icon: AppIcons.pushPin, label: 'Pinned', color: palette.textSecondary),
                  if (post.isAnnouncement) const _Tag(icon: AppIcons.campaigns, label: 'Announcement', color: AppColors.primary),
                ],
              ),
            ),
          Row(
            children: [
              UserAvatar(initials: post.author.initials, imageUrl: post.author.avatarUrl, size: 40),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.author.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        Fmt.relative(post.createdAt),
                        if (post.editedAt != null) 'edited',
                        if (post.author.role != null) post.author.role!.label,
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_isAuthor || widget.canModerate)
                IconButton(
                  tooltip: 'Post options',
                  onPressed: _busy ? null : _menu,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(AppIcons.dotsThree, color: palette.textSecondary),
                ),
            ],
          ),
          if (post.text.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(post.text, style: context.text.bodyLarge?.copyWith(color: palette.textPrimary, height: 1.45)),
          ],
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            // Same as Feed: each photo/video keeps its real shape (vertical
            // stays vertical, horizontal stays horizontal), nothing cropped.
            CommunityPostMedia(media: post.media),
          ],
          if (post.poll != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PollView(poll: post.poll!, canVote: widget.canInteract, busy: _busy, onVote: _vote),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: _like,
                style: TextButton.styleFrom(foregroundColor: post.isLiked ? AppColors.error : palette.textSecondary),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Icon(post.isLiked ? AppIcons.heartFilled : AppIcons.heart, key: ValueKey(post.isLiked), size: 20),
                ),
                label: Text('${post.likeCount}'),
              ),
              TextButton.icon(
                onPressed: _openComments,
                style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                icon: const Icon(AppIcons.messages, size: 20),
                label: Text('${post.commentCount}'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: context.text.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _PollView extends StatelessWidget {
  const _PollView({required this.poll, required this.canVote, required this.busy, required this.onVote});

  final PostPoll poll;
  final bool canVote;
  final bool busy;
  final ValueChanged<int> onVote;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final showResults = poll.myVote != null || poll.isClosed || !canVote;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (poll.question.isNotEmpty) ...[
            Row(
              children: [
                const Icon(AppIcons.chartBar, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(poll.question, style: context.text.titleSmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final (i, option) in poll.options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: showResults
                  ? _ResultBar(
                text: option.text,
                fraction: poll.totalVotes == 0 ? 0 : option.votes / poll.totalVotes,
                mine: poll.myVote == i,
              )
                  : OutlinedButton(
                onPressed: busy ? null : () => onVote(i),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  side: BorderSide(color: palette.borderStrong),
                ),
                child: Text(option.text, style: context.text.labelLarge?.copyWith(color: palette.textPrimary)),
              ),
            ),
          Text(
            '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'} · '
                '${poll.isClosed ? 'Poll ended' : poll.endsAt != null ? 'Ends ${Fmt.date(poll.endsAt!)}' : 'Open'}',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.text, required this.fraction, required this.mine});

  final String text;
  final double fraction;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: palette.surface)),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0, 1).toDouble(),
              child: ColoredBox(color: mine ? AppColors.primary.withValues(alpha: 0.28) : palette.surfaceMuted),
            ).animate().scaleX(begin: 0, alignment: Alignment.centerLeft, duration: 500.ms, curve: Curves.easeOutCubic),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: context.text.labelLarge?.copyWith(color: mine ? AppColors.primary : palette.textPrimary),
                  ),
                ),
                if (mine) const Icon(AppIcons.check, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text('${(fraction * 100).round()}%', style: context.text.labelMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}