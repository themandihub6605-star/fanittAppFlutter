import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/community_repository.dart';

const _maxMedia = 5;

/// Full-screen composer: text, photos/videos, poll, @tags and (for
/// owner/moderators) announcements. Pops with the created post.
class CommunityComposerScreen extends StatelessWidget {
  const CommunityComposerScreen({super.key, required this.community});

  final Community community;

  static Future<CommunityPost?> open(BuildContext context, Community community) {
    return Navigator.of(context, rootNavigator: true).push<CommunityPost>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => CommunityComposerScreen(community: community)),
    );
  }

  @override
  Widget build(BuildContext context) => ActionScope(child: _ComposerView(community: community));
}

class _ComposerView extends StatefulWidget {
  const _ComposerView({required this.community});

  final Community community;

  @override
  State<_ComposerView> createState() => _ComposerViewState();
}

class _ComposerViewState extends State<_ComposerView> {
  final _text = TextEditingController();
  final _question = TextEditingController();
  final List<TextEditingController> _options = [TextEditingController(), TextEditingController()];
  final List<PickedMedia> _media = [];
  final List<UserLite> _mentions = [];
  bool _showPoll = false;
  int _pollDays = 3;
  bool _announcement = false;

  @override
  void dispose() {
    _text.dispose();
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final left = _maxMedia - _media.length;
    if (left <= 0) return;
    final picked = await sl<MediaPicker>().media(limit: left);
    if (picked.isNotEmpty) setState(() => _media.addAll(picked.take(left)));
  }

  Future<void> _tagMember() async {
    final user = await showAppSheet<UserLite>(context, builder: (_) => _MentionPicker(communityId: widget.community.id));
    if (user == null) return;
    setState(() {
      if (!_mentions.any((m) => m.id == user.id)) _mentions.add(user);
      final current = _text.text;
      _text.text = '$current${current.isEmpty || current.endsWith(' ') ? '' : ' '}@${user.name} ';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
  }

  Future<void> _post() async {
    FocusScope.of(context).unfocus();
    final text = _text.text.trim();
    final options = _options.map((c) => c.text.trim()).where((o) => o.isNotEmpty).toList();
    if (_showPoll && options.length < 2) {
      AppSnackbar.error(context, 'Add at least 2 poll options');
      return;
    }
    if (text.isEmpty && _media.isEmpty && !_showPoll) {
      AppSnackbar.error(context, 'Write something, add media or create a poll');
      return;
    }
    final input = NewCommunityPost(
      text: text,
      media: _media,
      pollQuestion: _showPoll ? _question.text.trim() : '',
      pollOptions: _showPoll ? options : const [],
      pollDays: _pollDays,
      isAnnouncement: _announcement,
      // Only people still named in the text.
      mentionIds: _mentions.where((m) => text.contains('@${m.name}')).map((m) => m.id).toList(),
    );
    final post = await context.read<ActionCubit>().run('post', () => sl<CommunityRepository>().createPost(widget.community.id, input));
    if (post != null && mounted) Navigator.of(context).pop(post);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final busy = context.watch<ActionCubit>().state.isBusy;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.community.name, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: AppButton(
              label: _announcement ? 'Announce' : 'Post',
              expand: false,
              height: 38,
              isLoading: busy,
              onPressed: busy ? null : _post,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xl),
              children: [
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 5,
                  maxLines: null,
                  maxLength: 3000,
                  textCapitalization: TextCapitalization.sentences,
                  style: context.text.bodyLarge?.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Share something with ${widget.community.name}…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (_media.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _media.length,
                      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, i) {
                        final m = _media[i];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: m.isVideo
                                    ? ColoredBox(color: Colors.black, child: Icon(AppIcons.video, color: palette.textSecondary))
                                    : Image.file(File(m.path), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _media.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), shape: BoxShape.circle),
                                  child: const Icon(AppIcons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (_showPoll) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(AppIcons.chartBar, size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Poll', style: context.text.titleSmall)),
                            IconButton(
                              tooltip: 'Remove poll',
                              onPressed: () => setState(() => _showPoll = false),
                              icon: const Icon(AppIcons.close, size: 18),
                            ),
                          ],
                        ),
                        TextField(controller: _question, maxLength: 200, decoration: const InputDecoration(hintText: 'Question (optional)', counterText: '')),
                        const SizedBox(height: AppSpacing.xs),
                        for (final (i, c) in _options.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(controller: c, maxLength: 80, decoration: InputDecoration(hintText: 'Option ${i + 1}', counterText: '')),
                                ),
                                if (_options.length > 2)
                                  IconButton(
                                    onPressed: () => setState(() => _options.removeAt(i).dispose()),
                                    icon: Icon(AppIcons.close, size: 16, color: palette.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            if (_options.length < 6)
                              TextButton.icon(
                                onPressed: () => setState(() => _options.add(TextEditingController())),
                                icon: const Icon(AppIcons.plus, size: 16),
                                label: const Text('Add option'),
                              ),
                            const Spacer(),
                            Text('Ends in ', style: context.text.bodySmall),
                            DropdownButton<int>(
                              value: _pollDays,
                              underline: const SizedBox.shrink(),
                              items: [1, 3, 7, 14].map((d) => DropdownMenuItem(value: d, child: Text('$d day${d == 1 ? '' : 's'}'))).toList(),
                              onChanged: (d) => setState(() => _pollDays = d ?? 3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (_announcement) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    color: palette.primarySoft,
                    borderColor: AppColors.primary.withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        const Icon(AppIcons.campaigns, color: AppColors.primary, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text('Announcement — every member gets a notification.', style: context.text.bodySmall?.copyWith(color: palette.textPrimary))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const InlineActionError(),
              ],
            ),
          ),

          // Toolbar
          Container(
            decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
            padding: EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs, AppSpacing.xxs + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                _Tool(icon: AppIcons.image, label: 'Photo / video', onTap: _media.length >= _maxMedia ? null : _pickMedia),
                _Tool(icon: AppIcons.chartBar, label: 'Poll', active: _showPoll, onTap: () => setState(() => _showPoll = !_showPoll)),
                _Tool(icon: AppIcons.at, label: 'Tag a member', onTap: _tagMember),
                if (widget.community.canModerate)
                  _Tool(icon: AppIcons.campaigns, label: 'Announcement', active: _announcement, onTap: () => setState(() => _announcement = !_announcement)),
                const Spacer(),
                Text('${_media.length}/$_maxMedia', style: context.text.bodySmall),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(backgroundColor: active ? context.palette.primarySoft : null),
      icon: Icon(icon, color: active ? AppColors.primary : context.palette.textSecondary),
    );
  }
}

/// Searchable member list for @tagging.
class _MentionPicker extends StatefulWidget {
  const _MentionPicker({required this.communityId});

  final String communityId;

  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<CommunityMember> _members = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await sl<CommunityRepository>().members(widget.communityId, search: _search.text.trim());
      if (mounted) setState(() => _members = res.items);
    } on ApiException {
      if (mounted) setState(() => _members = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Tag a member',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _load);
              },
              decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Icon(AppIcons.search, size: 20)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _members.isEmpty
                  ? Center(child: Text('No members found', style: context.text.bodySmall))
                  : ListView.builder(
                itemCount: _members.length,
                itemBuilder: (context, i) {
                  final u = _members[i].user;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(initials: u.initials, imageUrl: u.avatarUrl, size: 36),
                    title: Text(u.name, style: context.text.titleSmall),
                    onTap: () => Navigator.of(context).pop(u),
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