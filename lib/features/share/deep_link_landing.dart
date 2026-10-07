import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums/user_role.dart';
import '../../core/router/app_routes.dart';
import '../auth/presentation/bloc/auth_bloc.dart';

/// A shared link that arrived before sign-in; opened right after.
abstract final class PendingDeepLink {
  static String? value;
}

/// Where a shared link (/open/<type>/<id>) should take a signed-in user.
String? deepLinkTarget(String type, String id, UserRole role) => switch (type) {
  'campaign' => AppRoutes.campaignDetail(id),
  'session' || 'meet' => AppRoutes.meetDetail(id),
  'brand' => AppRoutes.brandProfile(id),
  'community' => AppRoutes.communityDetail(id),
  'product' => AppRoutes.storeProduct(id),
  'store' => AppRoutes.storePage(id),
  'creator' => AppRoutes.creatorProfile(id),
  'post' => AppRoutes.postDetail(id),
  _ => null,
};

/// Opened by a shared link: puts the user's home underneath and the shared
/// screen on top, so Back returns to home instead of closing the app.
class DeepLinkLanding extends StatefulWidget {
  const DeepLinkLanding({super.key, required this.type, required this.id});

  final String type;
  final String id;

  @override
  State<DeepLinkLanding> createState() => _DeepLinkLandingState();
}

class _DeepLinkLandingState extends State<DeepLinkLanding> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) return; // the router sends them to sign in first
      final role = auth.user.role;
      final target = deepLinkTarget(widget.type, widget.id, role);
      final router = GoRouter.of(context);
      router.go(role.homeRoute);
      if (target != null) router.push(target);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}