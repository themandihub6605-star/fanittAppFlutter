import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/di/injection.dart';
import 'core/enums/user_role.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'core/services/push_service.dart';
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
  late final StreamSubscription<Map<String, dynamic>> _tapSubscription;
  Map<String, dynamic>? _pendingTap;

  @override
  void initState() {
    super.initState();
    final push = sl<PushService>();
    _pendingTap = push.takeInitialTap();
    _tapSubscription = push.taps.listen(_openFromPush);
  }

  @override
  void dispose() {
    _tapSubscription.cancel();
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
          themeMode: ThemeMode.dark,
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
