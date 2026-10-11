import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/media_aspect.dart';
import '../../feed/data/story_repository.dart';
import '../data/content_repository.dart';

const _gradient = LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// One picked photo or video, with its real shape.
class _Draft {
  _Draft(this.media);

  PickedMedia media;
  double? ratio;
  VideoPlayerController? video;

  /// Video length in whole seconds (0 for photos).
  int get seconds => video == null ? 0 : (video!.value.duration.inMilliseconds / 1000).ceil();

  bool get isVideo => media.isVideo;

  Future<void> prepare() async {
    if (isVideo) {
      final c = VideoPlayerController.file(File(media.path));
      video = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      ratio = c.value.aspectRatio;
    } else {
      ratio = await MediaAspect.ofFile(media.path);
    }
  }

  void dispose() => video?.dispose();
}

/// What the creator / brand is making.
enum CreateMode {
  post('New post', 'Photos & videos together in one post'),
  reel('New reel', 'One short vertical video'),
  story('New story', 'Disappears after 24 hours');

  const CreateMode(this.title, this.hint);
  final String title;
  final String hint;
}

/// "Create" sheet: Post / Reel / Story. Opens the editor for the choice and
/// returns what was published (null if nothing).
Future<CreateMode?> showCreateChooser(BuildContext context) async {
  final mode = await showModalBottomSheet<CreateMode>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            _ChoiceTile(mode: CreateMode.post, icon: AppIcons.image, color: AppColors.primary),
            _ChoiceTile(mode: CreateMode.reel, icon: AppIcons.video, color: const Color(0xFFEC2A78)),
            _ChoiceTile(mode: CreateMode.story, icon: AppIcons.camera, color: const Color(0xFF7C4DFF)),
          ],
        ),
      ),
    ),
  );
  if (mode == null || !context.mounted) return null;
  final done = await CreatePostScreen.open(context, mode: mode);
  return done ? mode : null;
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.mode, required this.icon, required this.color});

  final CreateMode mode;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: palette.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).pop(mode),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.name[0].toUpperCase() + mode.name.substring(1), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(mode.hint, style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen editor for a post, reel or story: real previews in their own
/// shape, crop for photos, caption, share. Returns true when published.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.mode = CreateMode.post});

  final CreateMode mode;

  static Future<bool> open(BuildContext context, {CreateMode mode = CreateMode.post}) async {
    final created = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => CreatePostScreen(mode: mode),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        ),
      ),
    );
    return created ?? false;
  }

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _caption = TextEditingController();
  final List<_Draft> _items = [];
  int _selected = 0;
  bool _preparing = false;
  bool _publishing = false;
  bool _soundOn = false;

  _Draft? get _current => _items.isEmpty ? null : _items[_selected.clamp(0, _items.length - 1)];

  CreateMode get _mode => widget.mode;

  /// How many items this mode takes.
  int get _maxItems => _mode == CreateMode.post ? ContentRepository.maxMediaPerPost : 1;

  @override
  void initState() {
    super.initState();
    // Go straight to the gallery, like every modern app.
    WidgetsBinding.instance.addPostFrameCallback((_) => _add(closeIfEmpty: true));
  }

  @override
  void dispose() {
    _caption.dispose();
    for (final d in _items) {
      d.dispose();
    }
    super.dispose();
  }

  /// Reels: one video from the gallery.
  Future<List<PickedMedia>> _pickReel() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: ContentRepository.reelMaxSeconds));
    return file == null ? const [] : [PickedMedia(path: file.path, name: file.name, isVideo: true)];
  }

  /// One photo or video (stories, or the last free slot of a post).
  /// pickMultipleMedia doesn't accept a limit below 2.
  Future<List<PickedMedia>> _pickOne() async {
    final f = await ImagePicker().pickMedia(maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (f == null) return const [];
    final lower = f.name.toLowerCase();
    final isVideo = lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm');
    return [PickedMedia(path: f.path, name: f.name, isVideo: isVideo)];
  }

  Future<void> _add({bool closeIfEmpty = false}) async {
    final room = _maxItems - _items.length;
    if (room <= 0) return;
    final picked = _mode == CreateMode.reel ? await _pickReel() : (room == 1 ? await _pickOne() : await sl<MediaPicker>().media(limit: room));
    if (!mounted) return;
    if (picked.isEmpty) {
      if (closeIfEmpty && _items.isEmpty) Navigator.of(context).pop(false);
      return;
    }
    setState(() => _preparing = true);
    final drafts = picked.map(_Draft.new).toList();
    await Future.wait(drafts.map((d) => d.prepare().catchError((_) {})));
    if (!mounted) {
      for (final d in drafts) {
        d.dispose();
      }
      return;
    }
    // Length limits: reels up to 90 s, story videos up to 60 s.
    final limit = _mode == CreateMode.reel ? ContentRepository.reelMaxSeconds : (_mode == CreateMode.story ? StoryRepository.videoMaxSeconds : 0);
    final tooLong = limit > 0 ? drafts.where((d) => d.isVideo && d.seconds > limit).toList() : const <_Draft>[];
    if (tooLong.isNotEmpty) {
      for (final d in tooLong) {
        d.dispose();
      }
      drafts.removeWhere(tooLong.contains);
      AppSnackbar.error(context, _mode == CreateMode.reel ? 'Reels can be up to $limit seconds. Post longer videos as a normal post.' : 'Story videos can be up to $limit seconds.');
      if (drafts.isEmpty) {
        setState(() => _preparing = false);
        if (closeIfEmpty && _items.isEmpty) Navigator.of(context).pop(false);
        return;
      }
    }
    setState(() {
      _items.addAll(drafts);
      _selected = _items.length - drafts.length;
      _preparing = false;
    });
    _syncPlayback();
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    setState(() => _selected = i);
    _syncPlayback();
  }

  /// Only the selected video plays.
  void _syncPlayback() {
    for (var i = 0; i < _items.length; i++) {
      final v = _items[i].video;
      if (v == null) continue;
      if (i == _selected) {
        v.setVolume(_soundOn ? 1 : 0);
        v.play();
      } else {
        v.pause();
      }
    }
  }

  void _remove(int i) {
    HapticFeedback.lightImpact();
    final d = _items.removeAt(i);
    d.dispose();
    setState(() => _selected = _selected.clamp(0, _items.isEmpty ? 0 : _items.length - 1));
    _syncPlayback();
  }

  Future<void> _crop() async {
    final d = _current;
    if (d == null || d.isVideo) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: d.media.path,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit photo',
          toolbarColor: const Color(0xFF0E0E14),
          toolbarWidgetColor: Colors.white,
          statusBarColor: const Color(0xFF0E0E14),
          backgroundColor: Colors.black,
          activeControlsWidgetColor: AppColors.primary,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            _Ratio4x5(),
            _Ratio9x16(),
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Edit photo',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            _Ratio4x5(),
            _Ratio9x16(),
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );
    if (cropped == null || !mounted) return;
    final media = PickedMedia(path: cropped.path, name: d.media.name.replaceAll(RegExp(r'\.\w+$'), '.jpg'));
    final ratio = await MediaAspect.ofFile(cropped.path);
    if (!mounted) return;
    setState(() {
      d.media = media;
      d.ratio = ratio;
    });
  }

  Future<void> _publish() async {
    if (_items.isEmpty || _publishing) return;
    FocusScope.of(context).unfocus();
    setState(() => _publishing = true);
    for (final d in _items) {
      d.video?.pause();
    }
    try {
      if (_mode == CreateMode.story) {
        final d = _items.first;
        await StoryRepository.i.create(media: d.media, caption: _caption.text.trim(), duration: d.seconds);
      } else {
        await sl<ContentRepository>().createPost(
          media: [for (final d in _items) d.media],
          caption: _caption.text.trim(),
          aspectRatios: [for (final d in _items) d.ratio],
          durations: [for (final d in _items) d.seconds],
          reel: _mode == CreateMode.reel,
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      AppSnackbar.success(context, switch (_mode) { CreateMode.post => 'Posted 🎉', CreateMode.reel => 'Reel posted 🎬', CreateMode.story => 'Added to your story' });
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      AppSnackbar.error(context, e.displayMessage);
      _syncPlayback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = _current;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(AppIcons.close), onPressed: () => Navigator.of(context).maybePop(false)),
        title: Text(_mode.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _ShareButton(enabled: _items.isNotEmpty && !_preparing, busy: _publishing, onTap: _publish),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _publishing,
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.huge),
          children: [
            // Big preview in the item's own shape
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
              child: current == null
                  ? _EmptyPreview(loading: _preparing, onAdd: _add, mode: _mode)
                  : _Preview(draft: current, soundOn: _soundOn, onToggleSound: () {
                setState(() => _soundOn = !_soundOn);
                current.video?.setVolume(_soundOn ? 1 : 0);
              }),
            ),

            // Tools for the selected item
            if (current != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
                child: Row(
                  children: [
                    if (!current.isVideo) _Tool(icon: AppIcons.crop, label: 'Crop & rotate', onTap: _crop),
                    if (current.isVideo)
                      Expanded(
                        child: Text('Videos are posted in their original shape.', style: context.text.bodySmall),
                      ),
                    if (!current.isVideo) const Spacer(),
                    _Tool(icon: AppIcons.trash, label: 'Remove', onTap: () => _remove(_selected), danger: true),
                  ],
                ),
              ),

            // Thumbnails (posts only — reels and stories are one item)
            if (_items.isNotEmpty && _mode == CreateMode.post)
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
                  itemCount: _items.length + (_items.length < ContentRepository.maxMediaPerPost ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _preparing ? null : () => _add(),
                        child: Container(
                          width: 64,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: palette.border, width: 1.5)),
                          child: _preparing
                              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                              : Icon(AppIcons.plus, color: palette.textSecondary),
                        ),
                      );
                    }
                    return _Thumb(draft: _items[i], selected: i == _selected, onTap: () => _select(i))
                        .animate(delay: (40 * i).ms)
                        .fadeIn(duration: 220.ms)
                        .scaleXY(begin: 0.85, curve: Curves.easeOutBack);
                  },
                ),
              ),
            if (_items.isNotEmpty && _mode == CreateMode.post)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
                child: Text('${_items.length} of ${ContentRepository.maxMediaPerPost} · all show together in one post', style: context.text.bodySmall?.copyWith(fontSize: 12)),
              ),
            if (_items.isNotEmpty && _mode != CreateMode.post)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
                child: OutlinedButton.icon(
                  onPressed: _preparing
                      ? null
                      : () async {
                    _remove(0);
                    await _add();
                  },
                  icon: const Icon(AppIcons.refresh, size: 18),
                  label: Text(_mode == CreateMode.reel ? 'Choose another video' : 'Choose another photo or video'),
                ),
              ),

            // Caption
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
              child: TextField(
                controller: _caption,
                minLines: _mode == CreateMode.story ? 1 : 3,
                maxLines: 8,
                maxLength: _mode == CreateMode.story ? 200 : 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _mode == CreateMode.story ? 'Add text (optional)…' : 'Write a caption…',
                  filled: true,
                  fillColor: palette.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: palette.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: palette.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.draft, required this.soundOn, required this.onToggleSound});

  final _Draft draft;
  final bool soundOn;
  final VoidCallback onToggleSound;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaAspect.clamp(draft.ratio ?? 1);
    final video = draft.video;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: AspectRatio(
        key: ValueKey('${draft.media.path}-$ratio'),
        aspectRatio: ratio,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF0E0E14), borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video != null && video.value.isInitialized)
                GestureDetector(
                  onTap: () => video.value.isPlaying ? video.pause() : video.play(),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)),
                  ),
                )
              else if (!draft.isVideo)
                Image.file(File(draft.media.path), fit: BoxFit.contain)
              else
                const Center(child: CircularProgressIndicator()),
              if (video != null)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onToggleSound,
                      child: Padding(padding: const EdgeInsets.all(10), child: Icon(soundOn ? AppIcons.speakerOn : AppIcons.speakerOff, color: Colors.white, size: 18)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.loading, required this.onAdd, required this.mode});

  final bool loading;
  final VoidCallback onAdd;
  final CreateMode mode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loading ? null : onAdd,
        child: Container(
          decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
          child: Center(
            child: loading
                ? const CircularProgressIndicator()
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(gradient: _gradient, shape: BoxShape.circle),
                  child: Icon(mode == CreateMode.reel ? AppIcons.video : AppIcons.image, color: Colors.white, size: 28),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(switch (mode) { CreateMode.post => 'Add photos or videos', CreateMode.reel => 'Choose a short video', CreateMode.story => 'Add a photo or video' }, style: context.text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  switch (mode) {
                    CreateMode.post => 'Up to ${ContentRepository.maxMediaPerPost} · shown together in one post',
                    CreateMode.reel => 'Up to ${ContentRepository.reelMaxSeconds} seconds · vertical works best',
                    CreateMode.story => 'Videos up to ${StoryRepository.videoMaxSeconds} seconds · gone after 24 hours',
                  },
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.draft, required this.selected, required this.onTap});

  final _Draft draft;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final video = draft.video;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        padding: EdgeInsets.all(selected ? 2.5 : 0),
        decoration: BoxDecoration(gradient: selected ? _gradient : null, borderRadius: BorderRadius.circular(14)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(selected ? 11 : 12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (video != null && video.value.isInitialized)
                FittedBox(fit: BoxFit.cover, child: SizedBox(width: video.value.size.width, height: video.value.size.height, child: VideoPlayer(video)))
              else if (!draft.isVideo)
                Image.file(File(draft.media.path), fit: BoxFit.cover, cacheWidth: 200)
              else
                const ColoredBox(color: Colors.black26),
              if (draft.isVideo)
                const Positioned(left: 4, bottom: 4, child: Icon(AppIcons.play, color: Colors.white, size: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : context.palette.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: context.palette.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: context.text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.enabled, required this.busy, required this.onTap});

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled || busy ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: _gradient),
          child: InkWell(
            onTap: enabled && !busy ? onTap : null,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Text('Share', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Extra crop shapes for portrait posts.
class _Ratio4x5 implements CropAspectRatioPresetData {
  @override
  (int, int)? get data => (4, 5);

  @override
  String get name => '4x5';
}

class _Ratio9x16 implements CropAspectRatioPresetData {
  @override
  (int, int)? get data => (9, 16);

  @override
  String get name => '9x16';
}