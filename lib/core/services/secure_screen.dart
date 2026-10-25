// File: lib/core/services/secure_screen.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots and screen recording while it's on screen (Android
/// FLAG_SECURE) — used for wallet, payments history, paid lives, calls and
/// bought products. Nested screens are counted, so leaving one secure screen
/// for another keeps protection on.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('fanitt/device_security');
  static int _open = 0;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> _set(bool on) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _open++;
    if (_open == 1) _set(true);
  }

  @override
  void dispose() {
    _open = (_open - 1).clamp(0, 1 << 20);
    if (_open == 0) _set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}