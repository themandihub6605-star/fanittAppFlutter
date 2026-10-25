import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps Fanitt off tampered / debuggable phones (Android, release builds).
///
/// * USB or wireless debugging ON → app is blocked until it's switched off.
/// * Rooted phone → app is blocked.
/// * Only Developer options ON → a small warning the user can close.
///
/// Debug & profile builds (`flutter run` from Android Studio) are never
/// checked, so development with USB debugging keeps working. To test a
/// release build on your own phone:
///   flutter run --release --dart-define=ALLOW_DEV_MODE=true
class DeviceSecurity {
  DeviceSecurity._();

  static const _channel = MethodChannel('fanitt/device_security');
  static const _allowDevMode = bool.fromEnvironment('ALLOW_DEV_MODE');

  /// Checks run only in real release builds on Android.
  static bool get enforced => kReleaseMode && !_allowDevMode && !kIsWeb && Platform.isAndroid;

  static Future<DeviceSecurityStatus> check() async {
    if (!enforced) return const DeviceSecurityStatus();
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      return DeviceSecurityStatus(
        developerOptions: m['developerOptions'] == true,
        usbDebugging: m['usbDebugging'] == true || m['wirelessDebugging'] == true,
        rooted: m['rooted'] == true,
      );
    } catch (_) {
      // Native side missing (older build): don't lock anyone out.
      return const DeviceSecurityStatus();
    }
  }

  static Future<void> openDeveloperSettings() async {
    try {
      await _channel.invokeMethod<void>('openDeveloperSettings');
    } catch (_) {}
  }
}

class DeviceSecurityStatus {
  const DeviceSecurityStatus({this.developerOptions = false, this.usbDebugging = false, this.rooted = false});

  final bool developerOptions;
  final bool usbDebugging;
  final bool rooted;

  bool get blocked => usbDebugging || rooted;
}

/// Wrap the whole app (MaterialApp.router `builder`). Re-checks every time
/// the app comes back to the front, so switching debugging off unlocks it.
class DeviceSecurityGate extends StatefulWidget {
  const DeviceSecurityGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceSecurityGate> createState() => _DeviceSecurityGateState();
}

class _DeviceSecurityGateState extends State<DeviceSecurityGate> with WidgetsBindingObserver {
  DeviceSecurityStatus _status = const DeviceSecurityStatus();
  bool _warningClosed = false;

  @override
  void initState() {
    super.initState();
    if (!DeviceSecurity.enforced) return;
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    if (DeviceSecurity.enforced) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = await DeviceSecurity.check();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Stack(
      children: [
        // The app can't be used underneath the block screen.
        AbsorbPointer(absorbing: s.blocked, child: widget.child),
        if (s.blocked) Positioned.fill(child: _BlockScreen(status: s, onRetry: _check)),
        if (!s.blocked && s.developerOptions && !_warningClosed)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 84,
            child: _Warning(onClose: () => setState(() => _warningClosed = true)),
          ),
      ],
    );
  }
}

class _BlockScreen extends StatelessWidget {
  const _BlockScreen({required this.status, required this.onRetry});

  final DeviceSecurityStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final rooted = status.rooted;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF0F1115) : Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 24),
              Text(
                rooted ? 'This phone isn’t supported' : 'Turn off USB debugging',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                rooted
                    ? 'For your account and payments to stay safe, Fanitt can’t run on rooted phones.'
                    : 'For your account and payments to stay safe, please turn off USB debugging (and Developer options) in your phone Settings, then come back to Fanitt.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: dark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 28),
              if (!rooted) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF4511E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: DeviceSecurity.openDeveloperSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextButton(onPressed: onRetry, child: const Text('I’ve turned it off — check again')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F2430),
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB020)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Developer options are on. For better safety, turn them off in Settings.',
                style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: DeviceSecurity.openDeveloperSettings, child: const Text('Settings')),
            IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Colors.white70, size: 18)),
          ],
        ),
      ),
    );
  }
}