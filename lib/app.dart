import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/di/injection.dart';
import 'core/network/api_client.dart';
import 'core/enums/user_role.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'core/services/link_opener.dart';
import 'core/services/push_service.dart';
import 'core/services/screen_tracker.dart';
import 'core/services/socket_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

class FanittApp extends StatefulWidget {
  const FanittApp({super.key});

  @override
  State<FanittApp> createState() => _FanittAppState();
}

class _FanittAppState extends State<FanittApp> {
  late final AuthBloc _authBloc = sl<AuthBloc>()..add(const AuthStarted());
  late final GoRouter _router = AppRouter(_authBloc).router;
  // Screen analytics for the admin panel (screen names + time only).
  late final ScreenTracker _screenTracker = ScreenTracker(sl<ApiClient>(), sl<SharedPreferences>());
  late final StreamSubscription<Map<String, dynamic>> _tapSubscription;
  StreamSubscription<SocketEvent>? _socketSubscription;
  Map<String, dynamic>? _pendingTap;

  @override
  void initState() {
    super.initState();
    _screenTracker.attach(_router);
    final push = sl<PushService>();
    _pendingTap = push.takeInitialTap();
    _tapSubscription = push.taps.listen(_openFromPush);
    // Someone is calling this creator — open the ringing screen.
    _socketSubscription = sl<SocketService>().events.listen((event) {
      if (event.name != 'store_call_request') return;
      final callId = event.data['callId']?.toString();
      if (callId != null && callId.isNotEmpty && _authBloc.state is AuthAuthenticated) {
        _router.push(AppRoutes.storeCall(callId));
      }
    });
  }

  @override
  void dispose() {
    _tapSubscription.cancel();
    _socketSubscription?.cancel();
    _screenTracker.detach();
    _router.dispose();
    super.dispose();
  }

  /// Signed in (launch, login or register): enable push and realtime.
  void _onAuthChanged(BuildContext context, AuthState state) {
    if (state is! AuthAuthenticated) return;
    sl<PushService>().register();
    sl<SocketService>().connect();
    final tap = _pendingTap;
    _pendingTap = null;
    if (tap != null) {
      // Let the router settle on the home route first.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openFromPush(tap));
    }
  }

  void _openFromPush(Map<String, dynamic> data) {
    final auth = _authBloc.state;
    if (auth is! AuthAuthenticated) {
      _pendingTap = data;
      return;
    }
    // Admin broadcast with a link.
    final link = data['link']?.toString();
    if (link != null && link.isNotEmpty) {
      LinkOpener.open(link.startsWith('/') ? 'https://app.fanitt.com$link' : link).ignore();
      return;
    }
    final id = data['relatedId']?.toString();
    if (id == null || id.isEmpty) {
      _router.push(AppRoutes.notifications);
      return;
    }
    switch (data['relatedModel']) {
      case 'Campaign':
        _router.push(auth.user.role == UserRole.brand ? AppRoutes.manageCampaign(id) : AppRoutes.campaignDetail(id));
      case 'Conversation':
        _router.push(AppRoutes.chat(id));
      case 'Community':
        _router.push(AppRoutes.communityDetail(id));
      case 'Session':
        _router.push(AppRoutes.meetDetail(id));
      case 'CommunityPost':
        _router.push(AppRoutes.communityPost(id));
      case 'CallSession':
        _router.push(AppRoutes.storeCall(id));
      case 'LiveStream':
        _router.push(AppRoutes.liveDetail(id));
      case 'StoreOrder':
        _router.push(data['type'] == 'store_sale' ? AppRoutes.storeSales : AppRoutes.library);
      case 'Store':
        _router.push(AppRoutes.store);
      default:
        _router.push(AppRoutes.notifications);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _authBloc,
      child: BlocListener<AuthBloc, AuthState>(
        listenWhen: (previous, current) => previous is! AuthAuthenticated && current is AuthAuthenticated,
        listener: _onAuthChanged,
        child: MaterialApp.router(
          title: 'Fanitt',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          routerConfig: _router,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              // Respect accessibility text sizes, but keep layouts intact.
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25),
              ),
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}