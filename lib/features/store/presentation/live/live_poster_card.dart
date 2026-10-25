import 'dart:ui' show ImageFilter;

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

  /// "Starts in 2h 10m" for the next 24 hours, otherwise the date.
  static String _startsLabel(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'Starting soon';
    if (diff.inMinutes < 60) return 'Starts in ${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) {
      final m = diff.inMinutes % 60;
      return m == 0 ? 'Starts in ${diff.inHours}h' : 'Starts in ${diff.inHours}h ${m}m';
    }
    return Fmt.weekdayDateTime(when);
  }

  @override
  Widget build(BuildContext context) {
    final when = (live.scheduledAt ?? live.startedAt)?.toLocal();
    final cta = _cta;
    final hostName = live.hostName.isNotEmpty ? live.hostName : (live.storeName ?? 'Creator');
    final avatarUrl = live.hostAvatarUrl.isNotEmpty ? live.hostAvatarUrl : (live.storeLogoUrl ?? '');
    final isLive = live.isLive;

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          // A soft red glow while it's live.
          boxShadow: [
            BoxShadow(
              color: (isLive ? const Color(0xFFE11D48) : Colors.black).withValues(alpha: isLive ? 0.35 : 0.18),
              blurRadius: isLive ? 18 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover
              live.coverUrl.isEmpty
                  ? const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B0F2A), Color(0xFF1B1B3A), Color(0xFF0F172A)])),
                child: Center(child: Icon(AppIcons.broadcast, size: 64, color: Colors.white12)),
              )
                  : CachedNetworkImage(
                imageUrl: live.coverUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: Color(0xFF1B1B2A)),
                errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF1B1B2A), child: Center(child: Icon(AppIcons.broadcast, color: Colors.white24, size: 40))),
              ),
              // Top shade
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Color(0x73000000), Color(0x00000000)]),
                ),
              ),
              // Thin border (red while live)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: isLive ? const Color(0xCCE11D48) : Colors.white.withValues(alpha: 0.10), width: isLive ? 1.6 : 1),
                ),
              ),
              // Top-left: LIVE + viewers, or a date tile
              Positioned(left: 12, top: 12, child: isLive ? _LiveBadge(viewers: live.viewers) : _DateTile(when: when)),
              // Top-right: price
              Positioned(right: 12, top: 12, child: _PriceTag(free: live.isFree, price: live.price)),
              // Bottom: frosted panel with who can join, title, host + button
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(child: _AudienceChip(audience: live.audience, locked: locked)),
                              if (!isLive && when != null) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(AppIcons.clock, size: 12, color: Colors.white70),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          _startsLabel(when),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            live.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -0.2),
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              _Avatar(url: avatarUrl, name: hostName),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(hostName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    Text(isLive ? 'Streaming now' : 'Host', maxLines: 1, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _Cta(label: cta.label, icon: cta.icon, onTap: () => _open(context), outlined: locked || (live.hasTicket && !isLive)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
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

class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.free, required this.price});

  final bool free;
  final int price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: free ? null : LivePosterCard._gradient,
        color: free ? const Color(0xE610B981) : null,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Text(
        free ? 'FREE' : Fmt.money(price),
        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.3),
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
          width: 30,
          height: 30,
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