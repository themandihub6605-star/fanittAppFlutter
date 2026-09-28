import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stream_video_player.dart';
import '../data/content_repository.dart';

class MyPostsScreen extends StatelessWidget {
  const MyPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<Post>>(sl<ContentRepository>().myPosts),
        child: const _PostsView(),
      ),
    );
  }
}

class _PostsView extends StatelessWidget {
  const _PostsView();

  Future<void> _create(BuildContext context) async {
    final created = await showCreatePostSheet(context);
    if (created && context.mounted) {
      AppSnackbar.success(context, 'Post published');
      context.read<LoadCubit<List<Post>>>().refresh();
    }
  }

  Future<void> _delete(BuildContext context, Post post) async {
    final ok = await confirmAction(context, title: 'Delete this post?', message: 'It’s removed from your profile for everyone.', confirmLabel: 'Delete', destructive: true);
    if (!ok || !context.mounted) return;
    final done = await context.read<ActionCubit>().run('delete-${post.id}', () async {
      await sl<ContentRepository>().deletePost(post.id);
      return true;
    }, success: 'Post deleted');
    if (done != null && context.mounted) context.read<LoadCubit<List<Post>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Post>>>();
    final posts = cubit.state.data ?? const <Post>[];
    final canAdd = cubit.state.data != null && posts.length < ContentRepository.maxPosts;

    return Scaffold(
      appBar: AppBar(title: const Text('My posts')),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(AppIcons.plus), label: const Text('New post'))
          : null,
      body: AsyncView<List<Post>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (posts) => AppRefresh(
          onRefresh: cubit.refresh,
          child: posts.isEmpty
              ? const ScrollableMessage(
            child: MessageView(
              icon: AppIcons.image,
              title: 'Show brands your work',
              message: 'Add up to 5 posts with photos or videos. They appear on your public profile.',
            ),
          )
              : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
            itemCount: posts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text('${posts.length} of ${ContentRepository.maxPosts} posts used', style: context.text.bodySmall);
              }
              final post = posts[index - 1];
              return _PostCard(post: post, onDelete: () => _delete(context, post));
            },
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onDelete});

  final Post post;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: PageView(
              children: [
                for (final media in post.media)
                  media.isVideo ? StreamVideoPlayer(key: ValueKey(media.url), url: media.url) : AppNetworkImage(url: media.url),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.caption.isNotEmpty) Text(post.caption, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                      Text('${post.likeCount} likes · ${Fmt.relative(post.createdAt)}${post.media.length > 1 ? ' · ${post.media.length} items' : ''}', style: context.text.bodySmall),
                    ],
                  ),
                ),
                IconButton(tooltip: 'Delete', icon: const Icon(AppIcons.trash, size: 20), onPressed: onDelete),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the "New post" sheet. Returns true when a post was published.
/// Used by My posts and the Feed.
Future<bool> showCreatePostSheet(BuildContext context) async {
  final created = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _NewPostSheet()));
  return created ?? false;
}

class _NewPostSheet extends StatefulWidget {
  const _NewPostSheet();

  @override
  State<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends State<_NewPostSheet> {
  final _caption = TextEditingController();
  List<PickedMedia> _media = const [];

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await sl<MediaPicker>().media(limit: ContentRepository.maxMediaPerPost - _media.length);
    if (picked.isNotEmpty) setState(() => _media = [..._media, ...picked].take(ContentRepository.maxMediaPerPost).toList());
  }

  Future<void> _publish() async {
    final ok = await context.read<ActionCubit>().run('post', () => sl<ContentRepository>().createPost(media: _media, caption: _caption.text.trim()));
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final palette = context.palette;
    return SheetBody(
      title: 'New post',
      subtitle: 'Up to ${ContentRepository.maxMediaPerPost} photos or videos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final item in _media)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.sm)),
                          child: Icon(item.isVideo ? AppIcons.video : AppIcons.image, color: palette.textSecondary),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton.filledTonal(
                            iconSize: 14,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _media = _media.where((m) => m != item).toList()),
                            icon: const Icon(AppIcons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_media.length < ContentRepository.maxMediaPerPost)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: _pick,
                    child: Container(
                      width: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: palette.borderStrong),
                      ),
                      child: Icon(AppIcons.plus, color: palette.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: 'Caption (optional)', controller: _caption, minLines: 2, maxLines: 5, maxLength: 2200, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Publish', isLoading: busy, onPressed: busy || _media.isEmpty ? null : _publish),
        ],
      ),
    );
  }
}