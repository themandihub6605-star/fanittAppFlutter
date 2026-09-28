import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.initials, this.imageUrl, this.size = 48});

  final String initials;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.palette.primarySoft, shape: BoxShape.circle),
      child: Text(
        initials,
        style: context.text.titleMedium?.copyWith(
          color: AppColors.primary,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (imageUrl == null) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}
