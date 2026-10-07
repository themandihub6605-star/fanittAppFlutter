import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/community_models.dart';

/// Cover that fills the banner, with the bottom fading into the page so
/// the icon and text below sit on a smooth edge. Best upload: 1500 × 500.
class CommunityCover extends StatelessWidget {
  const CommunityCover({super.key, this.url, this.fadeTo, this.child});

  final String? url;
  final Color? fadeTo;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fade = fadeTo ?? context.palette.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x55F4511E), Color(0x33EC2A78), Color(0x110A1325)],
            ),
          ),
        ),
        if (url != null)
          CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 250),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 70,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [fade.withValues(alpha: 0), fade.withValues(alpha: 0.6), fade],
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class CommunityIcon extends StatelessWidget {
  const CommunityIcon({super.key, required this.name, this.url, this.size = 48, this.borderColor});

  final String name;
  final String? url;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final fallback = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0x55F4511E), Color(0x40EC2A78)]),
      ),
      child: Text(
        name.isEmpty ? '#' : name.trim()[0].toUpperCase(),
        style: TextStyle(color: AppColors.sunrise, fontWeight: FontWeight.w800, fontSize: size * 0.4),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: borderColor == null ? null : Border.all(color: borderColor!, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28 - (borderColor == null ? 0 : 3)),
        child: url == null
            ? fallback
            : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, errorWidget: (_, _, _) => fallback, placeholder: (_, _) => fallback),
      ),
    );
  }
}

/// Small badges next to a community name.
class CommunityBadges extends StatelessWidget {
  const CommunityBadges({super.key, required this.community, this.size = 16});

  final Community community;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (community.isVerified) ...[
          const SizedBox(width: 4),
          Icon(AppIcons.sealCheck, size: size, color: AppColors.info),
        ],
        if (community.isPrivate) ...[
          const SizedBox(width: 4),
          Icon(AppIcons.lock, size: size - 2, color: context.palette.textTertiary),
        ],
      ],
    );
  }
}

class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final CommunityRole role;

  @override
  Widget build(BuildContext context) {
    return switch (role) {
      CommunityRole.owner => const StatusChip(label: 'Owner', color: AppColors.warning, icon: AppIcons.crown),
      CommunityRole.moderator => const StatusChip(label: 'Moderator', color: AppColors.info, icon: AppIcons.shieldCheck),
      CommunityRole.member => const SizedBox.shrink(),
    };
  }
}

/// Label for the join button in its current state.
String joinLabelFor(Community c) {
  if (c.isMember) return 'Joined';
  if (c.isPending) return 'Requested';
  return c.isPrivate ? 'Request' : 'Join';
}

const communityGap = SizedBox(height: AppSpacing.sm);