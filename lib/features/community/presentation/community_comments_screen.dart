import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/community_repository.dart';

/// Comments with one level of replies. Pops with the new comment count.
class CommunityCommentsScreen extends StatefulWidget {
  const CommunityCommentsScreen({
    super.key,
    required this.postId,
    required this.initialCount,
    required this.canComment,
    required this.canModerate,
    required this.myUserId,
  });

  final String postId;
  final int initialCount;
  final bool canComment;
  final bool canModerate;
  final String? myUserId;

  @override
  State<CommunityCommentsScreen> createState() => _CommunityCommentsScreenState();
}

class _CommunityCommentsScreenState extends State<CommunityCommentsScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<CommunityComment> _comments = [];
  late int _count = widget.initialCount;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  CommunityComment? _replyTo;

  CommunityRepository get _repo => sl<CommunityRepository>();

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.comments(widget.postId, page: page);
      if (!mounted) return;
      setState(() {
        if (page == 1) _comments.clear();
        _comments.addAll(res.items);
        _page = res.page;
        _pages = res.pages;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.displayMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await _repo.addComment(widget.postId, text, parentId: _replyTo?.id);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        if (comment.parentId != null) {
          final i = _comments.indexWhere((c) => c.id == comment.parentId);
          if (i >= 0) _comments[i] = _comments[i].copyWith(replies: [..._comments[i].replies, comment]);
        } else {
          _comments.add(comment);
        }
        _count += 1;
        _replyTo = null;
      });
      _input.clear();
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _like(CommunityComment comment) async {
    if (!widget.canComment) return;
    try {
      final res = await _repo.likeComment(comment.id);
      if (!mounted) return;
      CommunityComment apply(CommunityComment c) => c.id == comment.id
          ? c.copyWith(isLiked: res.liked, likeCount: res.likeCount)
          : c.copyWith(replies: c.replies.map(apply).toList());
      setState(() {
        for (var i = 0; i < _comments.length; i++) {
          _comments[i] = apply(_comments[i]);
        }
      });
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  Future<void> _delete(CommunityComment comment) async {
    final ok = await confirmAction(
      context,
      title: 'Delete comment?',
      message: comment.parentId == null ? 'Its replies will be removed too.' : 'This reply will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      final removed = await _repo.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        if (comment.parentId == null) {
          _comments.removeWhere((c) => c.id == comment.id);
        } else {
          final i = _comments.indexWhere((c) => c.id == comment.parentId);
          if (i >= 0) {
            _comments[i] = _comments[i].copyWith(replies: _comments[i].replies.where((r) => r.id != comment.id).toList());
          }
        }
        _count = (_count - removed).clamp(0, 1 << 30);
      });
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  void _reply(CommunityComment comment) {
    // Replies to a reply attach to the same top-level comment.
    final root = comment.parentId == null ? comment : _comments.firstWhere((c) => c.id == comment.parentId, orElse: () => comment);
    setState(() => _replyTo = root);
    _focus.requestFocus();
  }

  Widget _comment(CommunityComment c, {bool reply = false}) {
    final palette = context.palette;
    final canDelete = widget.myUserId != null && (c.author.id == widget.myUserId || widget.canModerate);
    return Padding(
      padding: EdgeInsets.only(top: reply ? AppSpacing.sm : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(initials: c.author.initials, imageUrl: c.author.avatarUrl, size: reply ? 28 : 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.author.name, style: context.text.labelLarge),
                      const SizedBox(height: 2),
                      Text(c.text, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(Fmt.relative(c.createdAt), style: context.text.bodySmall),
                    _Action(
                      label: c.likeCount > 0 ? '${c.likeCount}' : 'Like',
                      icon: c.isLiked ? AppIcons.heartFilled : AppIcons.heart,
                      color: c.isLiked ? AppColors.error : null,
                      onTap: widget.canComment ? () => _like(c) : null,
                    ),
                    if (widget.canComment) _Action(label: 'Reply', onTap: () => _reply(c)),
                    if (canDelete) _Action(label: 'Delete', onTap: () => _delete(c)),
                  ],
                ),
                for (final r in c.replies) _comment(r, reply: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_count);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Comments ($_count)')),
        body: Column(
          children: [
            Expanded(
              child: _loading && _comments.isEmpty
                  ? const LoadingView()
                  : _error != null && _comments.isEmpty
                  ? ErrorView(message: _error!, onRetry: () => _load(1))
                  : _comments.isEmpty
                  ? const MessageView(icon: AppIcons.messages, title: 'No comments yet', message: 'Start the conversation.')
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.lg),
                itemCount: _comments.length + (_page < _pages ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) {
                  if (i == _comments.length) {
                    return Center(
                      child: TextButton(
                        onPressed: _loading ? null : () => _load(_page + 1),
                        child: Text(_loading ? 'Loading…' : 'Load more comments'),
                      ),
                    );
                  }
                  return _comment(_comments[i]);
                },
              ),
            ),
            if (widget.canComment)
              Container(
                decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
                padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyTo != null)
                      Row(
                        children: [
                          Expanded(child: Text('Replying to ${_replyTo!.author.name}', style: context.text.labelMedium?.copyWith(color: AppColors.primary))),
                          IconButton(icon: const Icon(AppIcons.close, size: 16), onPressed: () => setState(() => _replyTo = null)),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: _replyTo == null ? 'Write a comment…' : 'Write a reply…',
                              counterText: '',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Send',
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(AppIcons.send, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Text('Join the community to comment', style: context.text.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, this.icon, this.color, this.onTap});

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 3)],
            Text(label, style: context.text.labelSmall?.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}