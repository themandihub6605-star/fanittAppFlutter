// File: lib/features/store/presentation/widgets/store_promo_banner.dart
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
import '../../data/store_access.dart';
import '../../data/store_repository.dart';

/// "Open your Fanitt Store" banner the admin uploads (Fanitt Store →
/// Settings → Website banner) — nearly edge to edge, at the picture's own
/// shape: the whole image, no cropping and no empty bands.
///
/// Shown only to a creator who hasn't opened a store yet (or whose store
/// needs changes). Hidden for brands, fans and agencies, once the creator's
/// store is live or under review, and when the admin switches the banner off.
/// (The Fanitt Store switch only controls the physical shop, so it doesn't
/// hide this banner.)
class StorePromoBanner extends StatefulWidget {
  const StorePromoBanner({super.key, this.tappable = true, this.aspectRatio = 3.2});

  /// False on screens that already are the store (fan home).
  final bool tappable;

  /// Width : height used only while the picture loads (1600 × 500 = 3.2),
  /// so the page doesn't jump; then the picture's real shape is used.
  final double aspectRatio;

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
    HapticFeedback.selectionClick();
    context.push(AppRoutes.store);
  }

  @override
  Widget build(BuildContext context) {
    // Creators only.
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthAuthenticated || auth.user.role != UserRole.creator) return const SizedBox.shrink();
    final myId = auth.user.id;
    // Hidden once this creator has opened a store — rebuilds the moment it changes.
    return ValueListenableBuilder<StoreGate>(
      valueListenable: StoreAccess.gate,
      builder: (context, gate, _) => _needsStore(gate, myId) ? _banner(context) : const SizedBox.shrink(),
    );
  }

  /// True while the creator still has to open (or fix) a store.
  /// Unknown = not checked yet → stay hidden, so it never flashes for a
  /// creator whose store is already live.
  bool _needsStore(StoreGate gate, String myId) {
    if (gate == StoreGate.unknown) {
      // Not during build — the check updates the gate this widget listens to.
      WidgetsBinding.instance.addPostFrameCallback((_) => StoreAccess.refresh(myId));
      return false;
    }
    return gate == StoreGate.none || gate == StoreGate.rejected;
  }

  Widget _banner(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imageUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        final image = ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            // Full width, height from the picture itself — nothing cut, no gaps.
            fit: BoxFit.fitWidth,
            fadeInDuration: const Duration(milliseconds: 300),
            placeholder: (_, _) => AspectRatio(aspectRatio: widget.aspectRatio, child: const ColoredBox(color: Color(0x14F4511E))),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: widget.tappable
              ? Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _open(context), child: image),
          )
              : image,
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, curve: Curves.easeOutCubic);
      },
    );
  }
}