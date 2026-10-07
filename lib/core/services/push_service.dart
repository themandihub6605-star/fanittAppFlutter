import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// - Background / killed: the OS shows the notification; tapping it opens
///   the app and [taps] emits its data.
/// - Foreground: Android shows it through a local notification; iOS shows
///   the system banner (presentation options).
class PushService {
  PushService(this._api);

  final ApiClient _api;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _taps = StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<String>? _refreshSubscription;
  String? _token;
  Map<String, dynamic>? _initialTap;
  bool _initialized = false;

  // New channel id: Android fixes a channel's sound when it's first created,
  // so the custom sound needs a fresh channel.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'fanitt_alerts',
    'Fanitt',
    description: 'Proposals, payments and messages',
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('notification_app'),
  );

  /// Notification taps (data payload: type, relatedModel, relatedId).
  Stream<Map<String, dynamic>> get taps => _taps.stream;

  /// The tap that launched the app from a killed state, consumed once.
  Map<String, dynamic>? takeInitialTap() {
    final tap = _initialTap;
    _initialTap = null;
    return tap;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null) return;
          final data = jsonDecode(payload);
          if (data is Map<String, dynamic>) _taps.add(data);
        },
      );
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      // Remove the old silent-default channel so settings show just one.
      await android?.deleteNotificationChannel('fanitt_default');

      await _messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _taps.add(message.data));
      _initialTap = (await _messaging.getInitialMessage())?.data;
    } catch (error) {
      debugPrint('Push init failed: $error');
    }
  }

  /// Asks for permission and registers this device for the signed-in user.
  Future<void> register() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // The FCM token needs the APNs token first (null on simulators).
        final apns = await _messaging.getAPNSToken();
        if (apns == null) return;
      }

      final token = await _messaging.getToken();
      if (token != null) await _send(token);
      _refreshSubscription ??= _messaging.onTokenRefresh.listen(_send);
    } catch (error) {
      debugPrint('Push register failed: $error');
    }
  }

  /// Call before the session is cleared on logout.
  Future<void> unregister() async {
    final token = _token;
    _token = null;
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    try {
      if (token != null) {
        await _api.delete('/users/me/push-token', data: {'token': token}, parser: (_) => null);
      }
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('Push unregister failed: $error');
    }
  }

  Future<void> _send(String token) async {
    _token = token;
    try {
      await _api.post(
        '/users/me/push-token',
        data: {'token': token, 'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'},
        parser: (_) => null,
      );
    } catch (error) {
      debugPrint('Push token upload failed: $error');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    // iOS already shows the banner via presentation options.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification_app'),
          color: const Color(0xFFF4511E),
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}