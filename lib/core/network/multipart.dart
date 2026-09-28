import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import '../services/media_picker.dart';

/// Builds a multipart file with the correct content type — the backend
/// rejects uploads by mimetype, and Dio would otherwise send
/// application/octet-stream.
Future<MultipartFile> multipartFrom(PickedMedia media) {
  final mimeType = lookupMimeType(media.path) ?? lookupMimeType(media.name) ?? 'application/octet-stream';
  return MultipartFile.fromFile(
    media.path,
    filename: media.name,
    contentType: DioMediaType.parse(mimeType),
  );
}
