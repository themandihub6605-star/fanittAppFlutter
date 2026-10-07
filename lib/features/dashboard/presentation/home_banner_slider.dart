import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/json.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../notifications/data/notification_repository.dart';
import 'home_discover.dart' show homeRefreshTick;
import 'home_widgets.dart' show HomeAppBar;

// Full-bleed home hero slider (banners from Admin → Home Slider).
//
// • Edge to edge at the very top, under the status bar, with the avatar,
//   bell and messages floating on it.
// • The picture melts into the page at the bottom; dots sit below it.
// • Auto-slides every 4s, loops, pauses while held; tap opens the link.
// • No banners → the normal greeting header (HomeAppBar) instead.

class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.linkType,
    required this.linkValue,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
    id: J.id(json),
    imageUrl: J.str(json, 'imageUrl'),
    title: J.str(json, 'title'),
    subtitle: J.str(json, 'subtitle'),
    ctaLabel: J.str(json, 'ctaLabel'),
    linkType: J.str(json, 'linkType', 'none'),
    linkValue: J.str(json, 'linkValue'),
  );

  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final String linkType;
  final String linkValue;

  bool get hasText => title.isNotEmpty || subtitle.isNotEmpty || ctaLabel.isNotEmpty;
  bool get tappable => linkType != 'none' && linkValue.isNotEmpty;
}

const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

String? _roleOf(BuildContext context) {
  final auth = context.read<AuthBloc>().state;
  return auth is AuthAuthenticated ? auth.user.role.value : null;
}

/// Opens whatever the admin linked the banner to.
Future<void> openHomeBanner(BuildContext context, HomeBanner b) async {
  if (!b.tappable) return;
  HapticFeedback.selectionClick();
  sl<ApiClient>().post('/home/banners/${b.id}/click', parser: (_) => null).ignore();
  final v = b.linkValue;
  final role = _roleOf(context);
  switch (b.linkType) {
    case 'screen':
      if (v == 'campaigns') {
        if (role == 'creator') {
          context.go(AppRoutes.creatorCampaigns);
        } else if (role == 'brand') {
          context.go(AppRoutes.brandCampaigns);
        } else {
          context.push(AppRoutes.search).ignore();
        }
        return;
      }
      final route = switch (v) {
        'plans' => AppRoutes.plans,
        'wallet' => AppRoutes.wallet,
        'referrals' => AppRoutes.referrals,
        'store' => AppRoutes.store,
        'products' => AppRoutes.products,
        'stores' => AppRoutes.stores,
        'communities' => AppRoutes.communities,
        'meets' => AppRoutes.meets,
        'creators' => AppRoutes.creatorsDirectory,
        'brands' => AppRoutes.brands,
        'notifications' => AppRoutes.notifications,
        'library' => AppRoutes.library,
        'feed' => AppRoutes.feed,
        'search' => AppRoutes.search,
        'editProfile' => AppRoutes.editProfile,
        _ => null,
      };
      if (route != null) context.push(route).ignore();
    case 'url':
      final uri = Uri.tryParse(v);
      // Our own share links (fanitt.com/open/…) open inside the app.
      if (uri != null && uri.host.endsWith('fanitt.com') && uri.path.startsWith('/open/')) {
        context.push(uri.path).ignore();
      } else {
        try {
          await LinkOpener.open(v);
        } catch (_) {}
      }
    case 'campaign':
      context.push(AppRoutes.campaignDetail(v)).ignore();
    case 'creator':
      context.push(AppRoutes.creatorProfile(v)).ignore();
    case 'brand':
      context.push(AppRoutes.brandProfile(v)).ignore();
    case 'community':
      context.push(AppRoutes.communityDetail(v)).ignore();
    case 'store':
      context.push(AppRoutes.storePage(v)).ignore();
    case 'product':
      context.push(AppRoutes.storeProduct(v)).ignore();
    case 'live':
      context.push(AppRoutes.liveDetail(v)).ignore();
    case 'meet':
      context.push(AppRoutes.meetDetail(v)).ignore();
  }
}

/// Put this as the FIRST child of the home ListView, and remove the
/// Scaffold's `appBar` — this widget draws the header itself.
class HomeHeroSlider extends StatefulWidget {
  const HomeHeroSlider({super.key, this.topInset});

  /// Status-bar height. Pass it when the parent removed the top padding
  /// (MediaQuery.removePadding); otherwise it is read from MediaQuery.
  final double? topInset;

  @override
  State<HomeHeroSlider> createState() => _HomeHeroSliderState();
}

class _HomeHeroSliderState extends State<HomeHeroSlider> with AutomaticKeepAliveClientMixin {
  static const _autoEvery = Duration(seconds: 4);

  /// Hero picture height = width × this — best upload 1440 × 1150.
  static const double _heightFactor = 1.05;
  static const _loopBase = 1000;
  /// Share of the hero used for the soft fade into the page.
  static const double _fadeShare = 0.30;

  @override
  bool get wantKeepAlive => true;

  List<HomeBanner>? _banners;
  PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    homeRefreshTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final role = _roleOf(context);
      final banners = (await sl<ApiClient>().get(
        '/home/banners',
        query: {'platform': 'app', if (role != null) 'role': role},
        parser: (d) => J.list(J.asMap(d), 'banners', HomeBanner.fromJson).where((b) => b.imageUrl.isNotEmpty).toList(),
      ))
          .data;
      if (!mounted) return;
      final old = _controller;
      _controller = PageController(initialPage: banners.length > 1 ? _loopBase * banners.length : 0);
      setState(() {
        _banners = banners;
        _index = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _restartTimer();
    } catch (_) {
      if (mounted && _banners == null) setState(() => _banners = const []);
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if ((_banners?.length ?? 0) < 2) return;
    _timer = Timer.periodic(_autoEvery, (_) {
      if (_holding || !_controller.hasClients || !mounted) return;
      _controller.nextPage(duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final banners = _banners;
    // No banners → the usual greeting header.
    final topInset = widget.topInset ?? MediaQuery.paddingOf(context).top;
    if (banners != null && banners.isEmpty) {
      return Padding(padding: EdgeInsets.only(top: widget.topInset == null ? 0 : topInset), child: const HomeAppBar());
    }

    final width = MediaQuery.sizeOf(context).width;
    // Whole pixels — a fractional height draws a hairline at the edge.
    final height = (width * _heightFactor).roundToDouble();
    final count = banners?.length ?? 0;
    final bg = context.palette.background;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // Paint the hero in its own layer, flush to whole pixels — stops the
      // hairline that showed at the bottom while scrolling.
      child: RepaintBoundary(
        child: ColoredBox(
          color: bg,
          child: Column(
            children: [
              SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (banners == null)
                      const _HeroLoading()
                    else
                      Listener(
                        onPointerDown: (_) => _holding = true,
                        onPointerUp: (_) => _holding = false,
                        onPointerCancel: (_) => _holding = false,
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: count == 1 ? 1 : null, // null = endless loop
                          onPageChanged: (i) {
                            setState(() => _index = i % count);
                            _restartTimer();
                          },
                          itemBuilder: (context, i) => _HeroPage(
                            textBottom: height * _fadeShare + 6,
                            banner: banners[i % count],
                            controller: _controller,
                            page: i,
                            onTap: () => openHomeBanner(context, banners[i % count]),
                          ),
                        ),
                      ),
                    // Top shade so the header buttons always read.
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 130,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x59000000), Color(0x00000000)])),
                        ),
                      ),
                    ),
                    // Bottom: a long, eased fade into the page — no hard edge,
                    // no grey band.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -1,
                      height: height * _fadeShare + 1,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                bg.withValues(alpha: 0),
                                bg.withValues(alpha: 0.05),
                                bg.withValues(alpha: 0.16),
                                bg.withValues(alpha: 0.34),
                                bg.withValues(alpha: 0.56),
                                bg.withValues(alpha: 0.78),
                                bg.withValues(alpha: 0.93),
                                bg,
                              ],
                              stops: const [0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.85, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Solid last pixels: no thin line at the edge while scrolling
                    // or pulling to refresh.
                    Positioned(left: 0, right: 0, bottom: -1, height: 4, child: IgnorePointer(child: ColoredBox(color: bg))),
                    // Floating header: avatar · bell
                    Positioned(
                      left: AppSpacing.gutter,
                      right: AppSpacing.gutter,
                      top: topInset + 10,
                      child: const _HeroHeader(),
                    ),
                    // Dots float inside the soft fade, like a premium store app.
                    if (count > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 14,
                        child: _Dots(count: count, index: _index),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slide: picture with a slight parallax, optional text bottom-left.
class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.banner, required this.controller, required this.page, required this.onTap, required this.textBottom});

  final HomeBanner banner;
  final double textBottom;
  final PageController controller;
  final int page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    return GestureDetector(
      onTap: b.tappable ? onTap : null,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(decoration: BoxDecoration(gradient: _brandGradient)),
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                var offset = 0.0;
                if (controller.hasClients && controller.position.haveDimensions) {
                  offset = ((controller.page ?? page.toDouble()) - page).clamp(-1.0, 1.0);
                }
                // Picture moves slower than the page → depth.
                return Transform.translate(
                  offset: Offset(offset * MediaQuery.sizeOf(context).width * 0.06, 0),
                  child: Transform.scale(scale: 1.12, child: child),
                );
              },
              child: CachedNetworkImage(
                imageUrl: b.imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 300),
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => const Center(child: Icon(AppIcons.image, color: Colors.white54, size: 36)),
              ),
            ),
            if (b.hasText) ...[
              // Soft shade on the left only, so white text reads on any picture.
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0x47000000), Color(0x1A000000), Color(0x00000000)],
                        stops: [0, 0.4, 0.65],
                      ),
                    ),
                  ),
                ),
              ),
              // Text stays on the left ~58% so the picture on the right shows.
              Positioned(
                left: AppSpacing.gutter,
                right: MediaQuery.sizeOf(context).width * 0.42,
                bottom: textBottom,
                child: _HeroText(banner: b),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  const _HeroText({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 1))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (b.title.isNotEmpty)
          Text(
            b.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.18, letterSpacing: -0.4, shadows: shadow),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.25, curve: Curves.easeOutCubic),
        if (b.subtitle.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            b.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xF2FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.35, shadows: shadow),
          ).animate().fadeIn(delay: 80.ms, duration: 400.ms).slideY(begin: 0.25, curve: Curves.easeOutCubic),
        ],
        if (b.ctaLabel.isNotEmpty && b.tappable) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: _brandGradient,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(b.ctaLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800))),
                const SizedBox(width: 6),
                const Icon(AppIcons.arrowRightSimple, size: 13, color: Colors.white),
              ],
            ),
          ).animate().fadeIn(delay: 160.ms, duration: 400.ms).slideY(begin: 0.25, curve: Curves.easeOutCubic),
        ],
      ],
    );
  }
}

/// Left: avatar + "Good morning, Name 👋". Right: notification bell.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    const shadow = [Shadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 1))];
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push(AppRoutes.editProfile),
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
            child: UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 42),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_greeting()},',
                maxLines: 1,
                style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12, fontWeight: FontWeight.w600, shadows: shadow),
              ),
              const SizedBox(height: 1),
              Text(
                '${user?.firstName ?? ''} 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, shadows: shadow),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const _HeroBell(),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: Icon(icon, size: 22, color: const Color(0xFF111111)),
        ),
      ),
    );
  }
}

class _HeroBell extends StatefulWidget {
  const _HeroBell();

  @override
  State<_HeroBell> createState() => _HeroBellState();
}

class _HeroBellState extends State<_HeroBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
    homeRefreshTick.addListener(_load);
  }

  @override
  void dispose() {
    homeRefreshTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final feed = await sl<NotificationRepository>().feed();
      if (mounted) setState(() => _unread = feed.unreadCount);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _RoundButton(
          icon: AppIcons.bell,
          onTap: () async {
            await context.push(AppRoutes.notifications);
            _load();
          },
        ),
        if (_unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 19),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 2)),
              child: Text(_unread > 99 ? '99+' : '$_unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }
}

/// Dots under the hero: the active one is a long dark pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: i == index ? 26 : 8,
            height: 8,
            decoration: BoxDecoration(
              gradient: i == index ? _brandGradient : null,
              color: i == index ? null : palette.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _HeroLoading extends StatelessWidget {
  const _HeroLoading();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(decoration: BoxDecoration(gradient: _brandGradient))
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1400.ms, color: Colors.white.withValues(alpha: 0.18));
  }
}