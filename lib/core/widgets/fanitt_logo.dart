import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The Fanitt logo image. The artwork already contains the "fanitt" name,
/// so no separate wordmark is shown unless [showWordmark] is set.
class FanittLogo extends StatelessWidget {
  const FanittLogo({
    super.key,
    this.size = 40,
    this.showWordmark = false,
    this.wordmarkColor,
  });

  /// Logo height. Width follows the image's own aspect ratio.
  final double size;
  final bool showWordmark;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/images/appLogo.png',
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!showWordmark) return Semantics(label: 'Fanitt', image: true, child: mark);

    return Semantics(
      label: 'Fanitt',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.28),
          ExcludeSemantics(
            child: Text(
              'fanitt',
              style: context.text.headlineSmall?.copyWith(
                fontSize: size * 0.62,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1,
                color: wordmarkColor ?? context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}