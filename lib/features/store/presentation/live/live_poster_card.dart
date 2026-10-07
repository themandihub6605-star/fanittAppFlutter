import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/store_models.dart';

/// Live stream "poster" for the home screen and community pages.
/// Full cover photo, a LIVE / date badge, a clear chip saying WHO can join
/// (Everyone · <Community> only · Invite only · Selected people), price,
/// host and one action button.
class LivePosterCard extends StatelessWidget {
  const LivePosterCard({super.key, required this.live, this.locked = false, this.onLockedTap});

  final LiveStream live;

  /// Community page, viewer isn't a member yet → button says "Join to watch".
  final bool locked;
  final VoidCallback? onLockedTap;

  static const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);
  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  ({String label, IconData icon}) get _cta {
    if (locked) return (label: 'Join to watch', icon: AppIcons.lock);
    if (live.isHost) return (label: live.isLive ? 'Open live' : 'Your live', icon: AppIcons.broadcast);
    if (live.isLive) {
      return live.canWatchFree ? (label: 'Watch now', icon: AppIcons.play) : (label: 'Ticket · ${Fmt.money(live.price)}', icon: AppIcons.receipt);
    }
    if (live.hasTicket) return (label: 'Ticket ✓', icon: AppIcons.check);
    return live.isFree ? (label: 'View', icon: AppIcons.arrowRightSimple) : (label: 'Get ticket · ${Fmt.money(live.price)}', icon: AppIcons.receipt);
  }

  void _open(BuildContext context) {
    HapticFeedback.selectionClick();
    if (locked) {
      onLockedTap?.call();
      return;
    }
    context.push(AppRoutes.liveDetail(live.id));
  }

  @override
  Widget build(BuildContext context) {
    final when = (live.scheduledAt ?? live.startedAt)?.toLocal();
    final cta = _cta;
    final hostName = live.hostName.isNotEmpty ? live.hostName : (live.storeName ?? 'Creator');
    final avatarUrl = live.hostAvatarUrl.isNotEmpty ? live.hostAvatarUrl : (live.storeLogoUrl ?? '');

    return GestureDetector(
      onTap: () => _open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover
            live.coverUrl.isEmpty
                ? const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A1A2E), Color(0xFF1B1B3A)])),
              child: Center(child: Icon(AppIcons.broadcast, size: 56, color: Colors.white24)),
            )
                : CachedNetworkImage(
              imageUrl: live.coverUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => const ColoredBox(color: Color(0xFF1B1B2A)),
              errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF1B1B2A), child: Center(child: Icon(AppIcons.broadcast, color: Colors.white24, size: 40))),
            ),
            // Readability shade
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x00000000), Color(0xEB000000)],
                  stops: [0, 0.32, 1],
                ),
              ),
            ),
            // Top-left: LIVE + viewers, or a calendar tile
            Positioned(left: 12, top: 12, child: live.isLive ? _LiveBadge(viewers: live.viewers) : _DateTile(when: when)),
            // Top-right: price
            Positioned(
              right: 12,
              top: 12,
              child: _Glass(
                child: Text(
                  live.isFree ? 'FREE' : Fmt.money(live.price),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                ),
              ),
            ),
            // Bottom: who can join, title, host + button
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AudienceChip(audience: live.audience, locked: locked),
                  const SizedBox(height: 7),
                  Text(
                    live.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.22),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Avatar(url: avatarUrl, name: hostName),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hostName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                            if (!live.isLive && when != null)
                              Text(Fmt.weekdayDateTime(when), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Cta(label: cta.label, icon: cta.icon, onTap: () => _open(context), outlined: locked || (live.hasTicket && !live.isLive)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String monthOf(DateTime d) => _months[d.month - 1];
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.viewers});

  final int viewers;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fade(begin: 1, end: 0.25, duration: 700.ms),
              const SizedBox(width: 5),
              const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _Glass(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.eye, size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(Fmt.compact(viewers), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.when});

  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    final w = when;
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(w == null ? 'SOON' : LivePosterCard.monthOf(w), style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          Text(w == null ? '—' : '${w.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
        ],
      ),
    );
  }
}

/// The "who can join" chip — the most important line on the card.
class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.audience, required this.locked});

  final LiveAudience audience;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint) = switch (audience.type) {
      LiveAudienceType.everyone => (AppIcons.globe, const Color(0xFF34D399)),
      LiveAudienceType.community => (AppIcons.users, const Color(0xFFFFB86B)),
      LiveAudienceType.invite => (AppIcons.link, const Color(0xFF93C5FD)),
      LiveAudienceType.selected => (AppIcons.star, const Color(0xFFF9A8D4)),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: Icon(locked ? AppIcons.lock : icon, size: 11, color: tint),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              locked ? 'Members only' : audience.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
      child: child,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LivePosterCard._gradient),
      child: ClipOval(
        child: SizedBox(
          width: 24,
          height: 24,
          child: url.isEmpty
              ? DecoratedBox(
            decoration: const BoxDecoration(gradient: LivePosterCard._gradient),
            child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))),
          )
              : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.icon, required this.onTap, this.outlined = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: outlined
            ? BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white38))
            : const BoxDecoration(gradient: LivePosterCard._gradient),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: content,
        ),
      ),
    );
  }
}