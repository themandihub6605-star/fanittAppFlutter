// File: lib/main.dart
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/di/injection.dart';
import 'core/network/api_client.dart';
import 'core/services/feature_flags.dart';
import 'core/services/push_service.dart';
import 'firebase_options.dart';

/// Runs in a background isolate for data-only pushes. Notification pushes
/// are shown by the OS, so nothing else is needed here.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() {
  // Catch every error so a failure shows up in the log instead of a frozen app.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[main] start');
    // Draw a screen straight away — the system splash goes away on the first
    // Flutter frame, so the app can never get stuck on it. Set-up runs
    // inside _Boot and the real app opens when it's done.
    runApp(const _Boot());
  }, (error, stack) {
    debugPrint('[main] UNCAUGHT: $error');
    debugPrintStack(stackTrace: stack, maxFrames: 12);
  });
}

/// Does the start-up work while showing a brand screen, then opens the app.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 8));
        FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
        debugPrint('[main] firebase ok');
      } catch (e) {
        // The app works without Firebase (only push / Google sign-in need it).
        debugPrint('[main] firebase skipped: $e');
      }

      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      // Only once — a retry must not register everything twice.
      if (!sl.isRegistered<ApiClient>()) {
        await configureDependencies().timeout(const Duration(seconds: 15));
      }
      debugPrint('[main] dependencies ok');

      // Admin switches (e.g. Fanitt Store on/off) — cached value first, then refreshed.
      FeatureFlags.init(sl<ApiClient>(), sl<SharedPreferences>());

      if (!mounted) return;
      setState(() => _ready = true);
      debugPrint('[main] app on screen');

      // Push setup needs the network — after the app is on screen, with a time limit.
      unawaited(_initPush());
    } catch (e, st) {
      debugPrint('[main] start-up failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 12);
      if (mounted) setState(() => _error = 'Fanitt couldn’t start. Please try again.');
    }
  }

  Future<void> _initPush() async {
    try {
      await sl<PushService>().init().timeout(const Duration(seconds: 20));
      debugPrint('[main] push ok');
    } catch (e) {
      debugPrint('[main] push skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const FanittApp();
    // Same look as the app's splash, shown for a moment while setting up.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4511E),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
          ),
          child: Center(
            child: _error == null
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _init,
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFF4511E)),
                    child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}