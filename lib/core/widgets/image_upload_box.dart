import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/media_picker.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';

/// Where an image is shown in the app — its shape, best upload size and
/// the tip shown under the upload box. Every upload uses one of these, so
/// the box has exactly the shape of the card the image appears in.
class ImageSlot {
  const ImageSlot({
    required this.aspectRatio,
    required this.bestSize,
    required this.tip,
    this.circle = false,
    this.radius = 16,
    this.label = 'Upload image',
    this.shownOn = 'This is how it looks in the app',
    this.displayWidth,
    this.alignment = Alignment.center,
  });

  /// width / height of the card that shows the image.
  final double aspectRatio;

  /// e.g. "1380 × 1000 px".
  final String bestSize;

  /// 2–3 short lines of guidance.
  final String tip;
  final bool circle;
  final double radius;
  final String label;

  /// Caption under the preview once an image is picked.
  final String shownOn;

  /// Real width of the card in the app. Tall (portrait) boxes are drawn at
  /// this width so the preview is the true size, not a full-screen poster.
  final double? displayWidth;

  /// Which part of the picture stays visible when it is cropped.
  final Alignment alignment;

  static const String _noText = 'Use a clear photo with no text on it — the title is added on top for you.';

  /// Live stream poster — home "Live" rail card (292 × 212).
  static const livePoster = ImageSlot(
    aspectRatio: 292 / 212,
    bestSize: '1380 × 1000 px',
    label: 'Upload live poster',
    tip: '$_noText Keep faces in the middle; the top corners show the date and price.',
    shownOn: 'Preview — exactly how your live shows on the home screen',
  );

  /// Online session (meet) poster — home "Online sessions" card (300 × 192).
  static const meetPoster = ImageSlot(
    aspectRatio: 300 / 192,
    bestSize: '1500 × 960 px',
    label: 'Upload session poster',
    tip: '$_noText Keep the main subject in the centre; edges may be trimmed.',
    shownOn: 'Preview — exactly how your session shows on the home screen',
  );

  /// Digital product cover — full-bleed product card (184 × 280).
  static const productCover = ImageSlot(
    aspectRatio: 184 / 280,
    bestSize: '1000 × 1520 px (portrait)',
    displayWidth: 184,
    label: 'Upload product cover',
    tip: '$_noText Portrait works best — the price and title sit on the bottom part.',
    shownOn: 'Preview — exactly how your product shows in the shop',
  );

  /// Store banner — full-bleed store card (300 × 196).
  static const storeBanner = ImageSlot(
    aspectRatio: 300 / 196,
    bestSize: '1500 × 980 px',
    label: 'Upload store banner',
    tip: 'Use a clean photo or pattern with no text. Your logo and store name are placed on the bottom-left.',
    shownOn: 'Preview — exactly how your store shows on the home screen',
  );

  /// Community cover — full-bleed community card (236 × 286).
  static const communityCover = ImageSlot(
    aspectRatio: 236 / 286,
    bestSize: '1180 × 1430 px (portrait)',
    displayWidth: 236,
    label: 'Upload community cover',
    tip: '$_noText Keep the main subject in the top half — the name and Join button sit at the bottom.',
    shownOn: 'Preview — exactly how your community shows on the home screen',
  );

  /// Campaign cover — campaign page header image (16 : 10).
  static const campaignCover = ImageSlot(
    aspectRatio: 16 / 10,
    bestSize: '1600 × 1000 px',
    label: 'Upload campaign cover',
    tip: 'Show your product or brand clearly, with no text on the image. Creators see this first on the campaign page.',
    shownOn: 'Preview — how creators see your campaign',
  );

  /// Creator photo — fills the portrait creator card on Home (160 × 244)
  /// and is also shown in a circle across the app.
  static const creatorPhoto = ImageSlot(
    aspectRatio: 160 / 244,
    bestSize: '1080 × 1650 px (portrait)',
    displayWidth: 160,
    alignment: Alignment.topCenter,
    label: 'Upload your photo',
    tip: 'A clear photo of you with your face near the top and no text on it. It fills your card on Home and also shows in a circle.',
    shownOn: 'Preview — exactly how your card shows on the home screen',
  );

  /// Round logo / profile photo.
  static const logo = ImageSlot(
    aspectRatio: 1,
    bestSize: '600 × 600 px',
    circle: true,
    label: 'Upload logo',
    tip: 'A square logo or photo on a plain background. It is shown in a circle.',
    shownOn: 'Preview — your logo across the app',
  );

  /// Rounded-square icon (communities).
  static const squareIcon = ImageSlot(
    aspectRatio: 1,
    bestSize: '600 × 600 px',
    radius: 18,
    label: 'Upload icon',
    tip: 'A square image or logo with no small text — it is shown small.',
    shownOn: 'Preview — your icon across the app',
  );
}

/// Upload box with the exact shape of the card the image appears in.
///
/// Empty: dotted border, upload icon, best size and a short tip.
/// Picked: [previewBuilder] draws the real card (title, badges…) on top of
/// the image so the user sees the final look; tap to change.
class ImageUploadBox extends StatelessWidget {
  const ImageUploadBox({
    super.key,
    required this.slot,
    required this.onPick,
    this.picked,
    this.url,
    this.onRemove,
    this.previewBuilder,
    this.enabled = true,
    this.optional = false,
    this.errorText,
    this.width,
  });

  final ImageSlot slot;

  /// Local pick (shown first) and/or the saved image.
  final PickedMedia? picked;
  final String? url;

  final VoidCallback onPick;
  final VoidCallback? onRemove;

  /// Draws the card's overlay (title, badges…) over [image].
  final Widget Function(BuildContext context, Widget image)? previewBuilder;
  final bool enabled;
  final bool optional;
  final String? errorText;

  /// Fixed width (for small round / square boxes); null = full width.
  final double? width;

  bool get _hasImage => picked != null || (url ?? '').isNotEmpty;

  Widget _image() {
    if (picked != null) return Image.file(File(picked!.path), fit: BoxFit.cover, alignment: slot.alignment);
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      alignment: slot.alignment,
      placeholder: (_, _) => const ColoredBox(color: Color(0x14000000)),
      errorWidget: (_, _, _) => const ColoredBox(color: Color(0x14000000), child: Center(child: Icon(AppIcons.image))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderRadius = BorderRadius.circular(slot.radius);
    final hasError = (errorText ?? '').isNotEmpty;

    Widget box;
    if (_hasImage) {
      final image = SizedBox.expand(child: _image());
      final card = previewBuilder == null ? image : previewBuilder!(context, image);
      box = Stack(
        fit: StackFit.expand,
        children: [
          slot.circle ? ClipOval(child: card) : ClipRRect(borderRadius: borderRadius, child: card),
          if (enabled)
            Positioned(
              right: slot.circle ? 0 : 8,
              bottom: slot.circle ? 0 : null,
              top: slot.circle ? null : 8,
              child: slot.circle || (width ?? 999) < 140
                  ? _RoundIcon(icon: AppIcons.camera, onTap: onPick)
                  : _Chip(icon: AppIcons.camera, label: 'Change', onTap: onPick),
            ),
          if (enabled && onRemove != null && !slot.circle && (width ?? 999) >= 140)
            Positioned(left: 8, top: 8, child: _RoundIcon(icon: AppIcons.trash, onTap: onRemove!, dark: true)),
        ],
      );
    } else {
      final small = (width ?? 999) < 140;
      box = CustomPaint(
        painter: _DashedBorder(
          color: hasError ? AppColors.error : AppColors.primary.withValues(alpha: 0.55),
          radius: slot.circle ? 999 : slot.radius,
          circle: slot.circle,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: context.isDark ? 0.08 : 0.04),
            shape: slot.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: slot.circle ? null : borderRadius,
          ),
          child: Center(
            child: small
                ? const _UploadIcon(size: 34)
                : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _UploadIcon(size: 46),
                  const SizedBox(height: 10),
                  Text(
                    optional ? '${slot.label} (optional)' : slot.label,
                    textAlign: TextAlign.center,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Best size ${slot.bestSize}',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final shaped = AspectRatio(aspectRatio: slot.aspectRatio, child: box);
    final tappable = GestureDetector(
      onTap: enabled
          ? () {
        HapticFeedback.selectionClick();
        onPick();
      }
          : null,
      child: width == null ? shaped : SizedBox(width: width, child: shaped),
    );
    final sized = width == null && slot.displayWidth != null
        ? Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: slot.displayWidth!), child: tappable))
        : tappable;

    // Small boxes (icons / logos) show the tip next to them.
    if (width != null && width! < 140) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          tappable,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(optional ? '${slot.label} (optional)' : slot.label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Best size ${slot.bestSize}', style: context.text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(slot.tip, style: context.text.bodySmall?.copyWith(height: 1.35)),
                if (hasError) ...[
                  const SizedBox(height: 4),
                  Text(errorText!, style: context.text.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sized,
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_hasImage ? AppIcons.eye : AppIcons.info, size: 14, color: palette.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _hasImage ? slot.shownOn : slot.tip,
                style: context.text.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(errorText!, style: context.text.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}

class _UploadIcon extends StatelessWidget {
  const _UploadIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
      ),
      child: Icon(AppIcons.camera, color: Colors.white, size: size * 0.45),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.dark = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Ink(
          decoration: dark
              ? null
              : const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
          child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 14, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Dotted outline for the empty upload box.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius, this.circle = false});

  final Color color;
  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(0.8), Radius.circular(circle ? size.shortestSide / 2 : radius)));
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color || old.radius != radius || old.circle != circle;
}