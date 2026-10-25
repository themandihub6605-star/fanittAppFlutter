// File: lib/features/dashboard/presentation/fan_home_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_update_banner.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../store/data/store_models.dart';
import '../../store/data/store_repository.dart';
import '../../store/presentation/call/request_call_sheet.dart';
import '../../store/presentation/live/live_now_stories.dart';
import 'home_banner_slider.dart';
import 'home_discover.dart';

/// Fan home — everything a fan comes for: creators to follow and message,
/// lives to join, products to buy, posts to watch and communities to join.
/// (No campaigns — those are for creators and brands.)
class FanHomeScreen extends StatelessWidget {
  const FanHomeScreen({super.key});

  static const _gutter = EdgeInsets.symmetric(horizontal: AppSpacing.gutter);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppRefresh(
        onRefresh: () async {
          context.read<AuthBloc>().add(const AuthRefreshRequested());
          homeRefreshTick.value++;
        },
        // The hero draws under the status bar itself.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 4000,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            children: [
              HomeHeroSlider(topInset: MediaQuery.paddingOf(context).top),
              const Padding(padding: _gutter, child: AppUpdateBanner()),
              const HomeSearchBar(hint: 'Search creators, lives, products…'),
              const SizedBox(height: AppSpacing.lg),

              // What a fan does on Fanitt.
              const HomeSectionHeader(title: 'Quick actions'),
              const SizedBox(height: AppSpacing.sm),
              HomeQuickActions(
                actions: [
                  HomeAction(icon: AppIcons.creators, label: 'Creators', isNew: true, onTap: () => context.go(AppRoutes.fanLibrary)),
                  HomeAction(icon: AppIcons.feed, label: 'Feed', color: const Color(0xFF6366F1), onTap: () => context.go(AppRoutes.fanFeed)),
                  HomeAction(icon: AppIcons.messages, label: 'Messages', color: const Color(0xFF0EA5E9), onTap: () => context.go(AppRoutes.fanMessages)),
                  HomeAction(icon: AppIcons.download, label: 'Products', color: AppColors.success, onTap: () => context.push(AppRoutes.products)),
                  HomeAction(icon: AppIcons.users, label: 'Communities', color: AppColors.warning, onTap: () => context.push(AppRoutes.communities)),
                  HomeAction(icon: AppIcons.storeFilled, label: 'Stores', color: const Color(0xFF00A3A3), onTap: () => context.push(AppRoutes.stores)),
                  HomeAction(icon: AppIcons.library, label: 'My library', color: const Color(0xFFDB2777), onTap: () => context.push(AppRoutes.library)),
                ],
                more: [
                  HomeAction(icon: AppIcons.userPlus, label: 'Following', color: const Color(0xFF14B8A6), onTap: () => context.push(AppRoutes.following)),
                  HomeAction(icon: AppIcons.bookmark, label: 'Saved', color: const Color(0xFFE11D48), onTap: () => context.push(AppRoutes.savedPosts)),
                  HomeAction(icon: AppIcons.package, label: 'My orders', color: const Color(0xFF7C4DFF), onTap: () => context.push(AppRoutes.shopOrders)),
                  HomeAction(icon: AppIcons.gift, label: 'Refer & earn', color: AppColors.error, onTap: () => context.push(AppRoutes.referrals)),
                ],
              ),

              // Lives first — join your creators while they're on.
              homeGap,
              LiveNowStories(refresh: homeRefreshTick),

              // 1-to-1 audio / video calls — at the creator's own per-minute rate (or free).
              homeGap,
              const CallCreatorsRail(),

              // Creators, products, communities… in the order set in the admin panel.
              // No campaigns for fans; lives are shown above.
              const HomeSections(showCampaigns: false, hide: {'live'}),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Talk 1:1" — creators taking audio / video calls. Online first; each card
/// shows the creator's own per-minute rate (or Free) and a Call button.
class CallCreatorsRail extends StatelessWidget {
  const CallCreatorsRail({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeRail<({StoreInfo store, CallInfo calls})>(
      title: 'Talk 1:1 with creators',
      subtitle: 'Audio & video calls · pay per minute or free',
      height: 196,
      itemWidth: 236,
      leading: const Icon(AppIcons.phone, size: 16, color: AppColors.primary),
      load: () => sl<StoreRepository>().callCreators(),
      itemBuilder: (context, item) => _CallCreatorCard(store: item.store, info: item.calls),
    );
  }
}

class _CallCreatorCard extends StatelessWidget {
  const _CallCreatorCard({required this.store, required this.info});

  final StoreInfo store;
  final CallInfo info;

  static const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

  String _rate(int paise) => paise <= 0 ? 'Free' : '${Fmt.money(paise)}/min';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canCall = info.online && !info.busy;
    final (statusText, statusColor) = info.busy
        ? ('In a call', AppColors.warning)
        : info.online
        ? ('Online now', const Color(0xFF22C55E))
        : ('Offline', palette.textTertiary);
    final initial = store.name.trim().isEmpty ? '?' : store.name.trim()[0].toUpperCase();

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.storePage(store.slug)),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: canCall ? const Color(0xFF22C55E).withValues(alpha: 0.45) : palette.border.withValues(alpha: 0.8)),
            boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0D101828), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _gradient),
                        child: ClipOval(
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: store.logoUrl.isEmpty
                                ? DecoratedBox(
                              decoration: const BoxDecoration(gradient: _gradient),
                              child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
                            )
                                : CachedNetworkImage(imageUrl: store.logoUrl, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: palette.surface, width: 2.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 2),
                        Text(statusText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: statusColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (info.audioEnabled) _RateChip(icon: AppIcons.phone, label: 'Audio · ${_rate(info.audioRate)}'),
                  if (info.videoEnabled) _RateChip(icon: AppIcons.videoCamera, label: 'Video · ${_rate(info.videoRate)}'),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: canCall
                    ? DecoratedBox(
                  decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(12)),
                  child: TextButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      showRequestCallSheet(context, store: store, info: info);
                    },
                    icon: const Icon(AppIcons.phone, size: 16, color: Colors.white),
                    label: const Text('Call now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                )
                    : OutlinedButton(
                  onPressed: () => context.push(AppRoutes.storePage(store.slug)),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: palette.border)),
                  child: Text(info.busy ? 'In a call · visit store' : 'Offline · visit store', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateChip extends StatelessWidget {
  const _RateChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: palette.textPrimary)),
        ],
      ),
    );
  }
}