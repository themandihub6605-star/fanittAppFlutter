import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// A file chosen on the device, ready to upload.
class PickedMedia {
  const PickedMedia({required this.path, required this.name, this.isVideo = false});

  final String path;
  final String name;
  final bool isVideo;
}

class MediaPicker {
  MediaPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// JPEG output keeps iPhone HEIC photos compatible with the backend.
  Future<PickedMedia?> image({ImageSource source = ImageSource.gallery}) async {
    final file = await _picker.pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    return file == null ? null : PickedMedia(path: file.path, name: file.name);
  }

  Future<List<PickedMedia>> images({int limit = 5}) async {
    final files = await _picker.pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 85, limit: limit);
    return files.take(limit).map((f) => PickedMedia(path: f.path, name: f.name)).toList();
  }

  /// Photos and videos together (posts, campaign sample media).
  Future<List<PickedMedia>> media({int limit = 5}) async {
    final files = await _picker.pickMultipleMedia(maxWidth: 2000, maxHeight: 2000, imageQuality: 85, limit: limit);
    return files.take(limit).map((f) {
      final lower = f.name.toLowerCase();
      final isVideo = lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm');
      return PickedMedia(path: f.path, name: f.name, isVideo: isVideo);
    }).toList();
  }

  /// Images and common documents for milestone work and dispute evidence.
  Future<List<PickedMedia>> attachments({int limit = 5}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
    );
    if (result == null) return const [];
    return result.files
        .where((f) => f.path != null)
        .take(limit)
        .map((f) => PickedMedia(path: f.path!, name: f.name))
        .toList();
  }
}
