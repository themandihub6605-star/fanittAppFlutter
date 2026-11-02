// File: lib/core/services/image_crop.dart
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../di/injection.dart';
import '../theme/app_colors.dart';
import '../widgets/image_upload_box.dart';
import 'media_picker.dart';

/// Pick a photo, then crop it to the exact shape it's shown in.
///
/// Every banner / poster / cover / logo upload goes through here, so the
/// user zooms and moves the picture inside the real frame (the same
/// [ImageSlot] the upload box and the card use) — nothing gets cut off
/// later. A tall card gets a tall crop, a wide banner a wide one, round
/// photos a circle.
abstract final class ImageCrop {
  /// Square photos (shop products, affiliate products, campaign products).
  static const square = ImageSlot(
    aspectRatio: 1,
    bestSize: '1000 × 1000 px',
    label: 'Upload photo',
    tip: 'A clear square photo of the product.',
  );

  /// Gallery → crop. Null when the user backs out of either step.
  static Future<PickedMedia?> pick(ImageSlot slot, {String? title}) async {
    final picked = await sl<MediaPicker>().image();
    if (picked == null) return null;
    return crop(picked, slot, title: title);
  }

  /// Several photos → each one cropped. A photo whose crop is cancelled is
  /// left out.
  static Future<List<PickedMedia>> pickMany(ImageSlot slot, {int limit = 5, String? title}) async {
    final picker = sl<MediaPicker>();
    final picked = limit >= 2 ? await picker.images(limit: limit) : [if (await picker.image() case final one?) one];
    final out = <PickedMedia>[];
    for (var i = 0; i < picked.length; i++) {
      final cropped = await crop(picked[i], slot, title: picked.length > 1 ? '${title ?? slot.label} (${i + 1}/${picked.length})' : title);
      if (cropped != null) out.add(cropped);
    }
    return out;
  }

  /// Opens the crop screen locked to the slot's shape: pinch to zoom, drag
  /// to move, rotate. Null = cancelled. If the cropper can't open on this
  /// phone, the original photo is used so the upload still works.
  static Future<PickedMedia?> crop(PickedMedia picked, ImageSlot slot, {String? title}) async {
    if (picked.isVideo) return picked;
    final heading = title ?? _title(slot);
    final style = slot.circle ? CropStyle.circle : CropStyle.rectangle;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: CropAspectRatio(ratioX: slot.aspectRatio, ratioY: 1),
        maxWidth: 2000,
        maxHeight: 2000,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: heading,
            toolbarColor: Colors.white,
            toolbarWidgetColor: const Color(0xFF101828),
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.primary,
            cropStyle: style,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.original,
            hideBottomControls: false,
            showCropGrid: true,
          ),
          IOSUiSettings(
            title: heading,
            cropStyle: style,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
          ),
        ],
      );
      if (cropped == null) return null;
      return PickedMedia(path: cropped.path, name: _jpgName(picked.name));
    } catch (e) {
      debugPrint('[ImageCrop] cropper failed, using the original photo: $e');
      return picked;
    }
  }

  /// Crop screen heading, e.g. "Fit your live poster" (the crop screen has
  /// room for one short line only).
  static String _title(ImageSlot slot) {
    final label = slot.label.replaceAll('*', '').replaceFirst(RegExp(r'^Upload\s+', caseSensitive: false), '').replaceFirst(RegExp(r'^your\s+', caseSensitive: false), '').trim();
    if (label.isEmpty) return 'Fit your photo';
    return 'Fit your ${label[0].toLowerCase()}${label.substring(1)}';
  }

  static String _jpgName(String name) {
    final base = name.replaceAll(RegExp(r'\.\w+$'), '');
    return '${base.isEmpty ? 'photo' : base}.jpg';
  }
}