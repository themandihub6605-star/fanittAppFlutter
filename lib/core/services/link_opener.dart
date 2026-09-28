import 'package:url_launcher/url_launcher.dart';

import '../network/api_exception.dart';

abstract final class LinkOpener {
  static Future<void> open(String url) async {
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(url);
    final normalized = hasScheme ? url : 'https://$url';
    final uri = Uri.tryParse(normalized);
    final mode = uri?.scheme == 'tel' ? LaunchMode.platformDefault : LaunchMode.externalApplication;
    if (uri == null || !await launchUrl(uri, mode: mode)) {
      throw const ApiException('Couldn’t open this link.');
    }
  }

  static Future<void> email(String address) async {
    final uri = Uri(scheme: 'mailto', path: address);
    if (!await launchUrl(uri)) throw const ApiException('No email app found on this device.');
  }
}