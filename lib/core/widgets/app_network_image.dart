import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_palette.dart';

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.radius = 0,
    this.fit = BoxFit.cover,
    this.placeholderIcon = AppIcons.image,
  });

  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final placeholder = Container(
      width: width,
      height: height,
      color: palette.surfaceMuted,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: palette.textTertiary, size: 24),
    );

    final image = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );

    return radius == 0 ? image : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}
