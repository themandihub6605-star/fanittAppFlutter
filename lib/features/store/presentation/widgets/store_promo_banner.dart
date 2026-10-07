import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/store_repository.dart';

/// The Fanitt Store banner the admin uploads (Fanitt Store → Settings →
/// Website banner), shown on the app's home screens too. The whole image is
/// shown at its own shape — never cropped. Hidden when the admin switches
/// the banner off or hasn't uploaded an image.
class StorePromoBanner extends StatefulWidget {
  const StorePromoBanner({super.key, this.tappable = true});

  /// False on screens that already are the store (fan home).
  final bool tappable;

  @override
  State<StorePromoBanner> createState() => _StorePromoBannerState();
}

class _StorePromoBannerState extends State<StorePromoBanner> {
  // One request per app session, shared by every home screen.
  static Future<String?>? _imageUrl;

  @override
  void initState() {
    super.initState();
    _imageUrl ??= _load();
  }

  static Future<String?> _load() async {
    try {
      return await sl<StoreRepository>().webBanner();
    } catch (_) {
      // No banner if it can't load — the home screen stays as it was.
      return null;
    }
  }

  void _open(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final role = auth is AuthAuthenticated ? auth.user.role : null;
    HapticFeedback.selectionClick();
    context.push(role == UserRole.creator ? AppRoutes.store : AppRoutes.stores);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imageUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            fadeInDuration: const Duration(milliseconds: 300),
            // While loading or on error: take no space instead of a gap.
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: widget.tappable
              ? Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(borderRadius: BorderRadius.circular(AppRadius.lg), onTap: () => _open(context), child: image),
          )
              : image,
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, curve: Curves.easeOutCubic);
      },
    );
  }
}