import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../brands/data/brands_repository.dart';
import '../../creators/data/creators_repository.dart';
import '../../notifications/data/notification_repository.dart';

// Activity (♥ in the feed): who liked your posts / reels and who followed you.

const _types = 'like,follow';

/// The person behind an activity, as a creator / brand profile (null for fans).
class _FromProfile {
  const _FromProfile({required this.isBrand, required this.profileId, required this.slug, required this.isFollowing});

  factory _FromProfile.fromJson(Map<String, dynamic> json) => _FromProfile(
    isBrand: J.str(json, 'role') == 'brand',
    profileId: J.str(json, 'profileId'),
    slug: J.str(json, 'slug'),
    isFollowing: J.boolean(json, 'isFollowing'),
  );

  final bool isBrand;
  final String profileId;
  final String slug;
  final bool isFollowing;

  String get route => isBrand ? AppRoutes.brandProfile(slug) : AppRoutes.creatorProfile(slug);

  _FromProfile withFollowing(bool f) => _FromProfile(isBrand: isBrand, profileId: profileId, slug: slug, isFollowing: f);
}

class _Activity {
  const _Activity(this.n, this.profile);

  final AppNotification n;
  final _FromProfile? profile;
}

Future<({List<_Activity> items, int unread})> _loadActivity() async =>
    (await sl<ApiClient>().get(
      '/notifications/me',
      query: {'types': _types},
      parser: (d) {
        final m = J.asMap(d);
        final raw = (m['notifications'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
        return (
        items: [
          for (final j in raw) _Activity(AppNotification.fromJson(j), J.map(j, 'fromProfile') == null ? null : _FromProfile.fromJson(J.map(j, 'fromProfile')!)),
        ],
        unread: J.integer(m, 'unreadCount'),
        );
      },
    ))
        .data;

/// ♥ in the feed app bar, with a dot when there's something new.
class ActivityButton extends StatefulWidget {
  const ActivityButton({super.key});

  @override
  State<ActivityButton> createState() => _ActivityButtonState();
}

class _ActivityButtonState extends State<ActivityButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final r = await _loadActivity();
      if (mounted) setState(() => _unread = r.unread);
    } catch (_) {}
  }

  Future<void> _open() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ActivityScreen()));
    if (mounted) _check();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Activity',
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(AppIcons.heart, size: 26, color: context.palette.textPrimary),
          if (_unread > 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle, border: Border.all(color: context.palette.background, width: 1.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<_Activity>? _items;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _loadActivity();
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _error = null;
      });
      // Opening the screen = seen.
      final repo = sl<NotificationRepository>();
      for (final a in r.items.where((a) => !a.n.isRead)) {
        repo.markRead(a.n.id).ignore();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t load your activity');
    }
  }

  /// Tap the row: open the post that was liked. Tap the person: their profile.
  void _open(_Activity a) {
    final id = a.n.relatedId;
    if (a.n.type == 'like' && id != null && a.n.relatedModel == 'Post') {
      context.push(AppRoutes.postDetail(id));
    } else {
      _openProfile(a);
    }
  }

  void _openProfile(_Activity a) {
    final p = a.profile;
    if (p == null || p.slug.isEmpty) return;
    context.push(p.route);
  }

  /// Follow back (or unfollow) the person who followed me.
  Future<void> _toggleFollow(_Activity a) async {
    final p = a.profile;
    if (p == null || _busy.contains(p.profileId)) return;
    HapticFeedback.selectionClick();
    void apply(bool following) {
      setState(() {
        _items = [for (final x in _items ?? const <_Activity>[]) x.profile?.profileId == p.profileId ? _Activity(x.n, x.profile!.withFollowing(following)) : x];
      });
    }

    apply(!p.isFollowing);
    setState(() => _busy.add(p.profileId));
    try {
      final now = p.isBrand ? await sl<BrandsRepository>().toggleFollow(p.profileId) : (await sl<CreatorsRepository>().toggleFollow(p.profileId)).following;
      if (mounted) apply(now);
    } on ApiException catch (e) {
      if (!mounted) return;
      apply(p.isFollowing);
      AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy.remove(p.profileId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final palette = context.palette;
    final now = DateTime.now();
    final today = [for (final a in items ?? const <_Activity>[]) if (now.difference(a.n.createdAt).inHours < 24) a];
    final earlier = [for (final a in items ?? const <_Activity>[]) if (now.difference(a.n.createdAt).inHours >= 24) a];
    Widget row(_Activity a) => _Row(
      item: a.n,
      profile: a.profile,
      busy: a.profile != null && _busy.contains(a.profile!.profileId),
      onTap: () => _open(a),
      onProfile: () => _openProfile(a),
      onFollow: () => _toggleFollow(a),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Activity'), centerTitle: true),
      body: items == null
          ? Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : TextButton(onPressed: _load, child: Text('$_error — tap to retry')),
      )
          : RefreshIndicator.adaptive(
        onRefresh: _load,
        color: AppColors.primary,
        child: items.isEmpty
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(AppIcons.heart, size: 44, color: palette.textTertiary),
            const SizedBox(height: 12),
            Center(child: Text('No activity yet', style: context.text.titleMedium)),
            const SizedBox(height: 4),
            Center(child: Text('Likes on your posts and new followers show here.', style: context.text.bodySmall)),
          ],
        )
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            if (today.isNotEmpty) ...[const _Header('Today'), for (final a in today) row(a)],
            if (earlier.isNotEmpty) ...[const _Header('Earlier'), for (final a in earlier) row(a)],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xs),
    child: Text(text, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.profile, required this.busy, required this.onTap, required this.onProfile, required this.onFollow});

  final AppNotification item;
  final _FromProfile? profile;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onProfile;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final from = item.from;
    final name = from?.name ?? 'Someone';
    final isFollow = item.type == 'follow';
    final what = isFollow ? 'started following you.' : (item.message.contains('reel') ? 'liked your reel.' : 'liked your post.');
    final p = profile;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: item.isRead ? null : AppColors.primary.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: onProfile,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(initials: name.isEmpty ? '?' : name[0].toUpperCase(), imageUrl: from?.avatarUrl, size: 44),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: isFollow ? AppColors.primary : AppColors.error, shape: BoxShape.circle, border: Border.all(color: palette.background, width: 2)),
                      child: Icon(isFollow ? AppIcons.userPlus : AppIcons.heartFilled, size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: isFollow ? onProfile : onTap,
                child: Text.rich(
                  TextSpan(
                    style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.3),
                    children: [
                      TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' $what '),
                      TextSpan(text: Fmt.relative(item.createdAt), style: TextStyle(color: palette.textTertiary, fontSize: 12.5)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Follow back — only for people who have a creator / brand profile.
            if (isFollow && p != null) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 32,
                child: p.isFollowing
                    ? OutlinedButton(
                  onPressed: busy ? null : onFollow,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: BorderSide(color: palette.border),
                    foregroundColor: palette.textPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Following', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                )
                    : FilledButton(
                  onPressed: busy ? null : onFollow,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Follow back', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}