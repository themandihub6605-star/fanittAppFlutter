import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../campaigns/presentation/widgets/campaign_widgets.dart';
import '../data/brands_repository.dart';

class BrandsScreen extends StatelessWidget {
  const BrandsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<BrandsRepository>();
    return BlocProvider(
      create: (_) => PagedCubit<BrandListItem>((page) => repo.list(page: page)),
      child: const _BrandsView(),
    );
  }
}

class _BrandsView extends StatefulWidget {
  const _BrandsView();

  @override
  State<_BrandsView> createState() => _BrandsViewState();
}

class _BrandsViewState extends State<_BrandsView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PagedCubit<BrandListItem>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Brands')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), () {
                  final repo = sl<BrandsRepository>();
                  final text = _search.text.trim();
                  cubit.updateQuery((page) => repo.list(page: page, search: text));
                });
              },
              decoration: const InputDecoration(hintText: 'Search brands', prefixIcon: Icon(AppIcons.search, size: 20)),
            ),
          ),
          Expanded(
            child: PagedListView<BrandListItem>(
              cubit: cubit,
              empty: const MessageView(icon: AppIcons.brand, title: 'No brands found'),
              itemBuilder: (context, item) => _BrandTile(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.item});

  final BrandListItem item;

  @override
  Widget build(BuildContext context) {
    final b = item.profile;
    final palette = context.palette;
    return AppCard(
      onTap: b.slug.isEmpty ? null : () => context.push(AppRoutes.brandProfile(b.slug)),
      child: Row(
        children: [
          AppNetworkImage(url: item.logoUrl, width: 52, height: 52, radius: AppRadius.md, placeholderIcon: AppIcons.brand),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(b.companyName, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                    if (item.isPro) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      StatusChip(label: b.planName, color: AppColors.primary),
                    ],
                  ],
                ),
                Text(
                  [if (b.industry.isNotEmpty) b.industry, if (b.location.isNotEmpty) b.location].join(' · '),
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
        ],
      ),
    );
  }
}

class BrandProfileScreen extends StatelessWidget {
  const BrandProfileScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<BrandPublicProfile>(() => sl<BrandsRepository>().bySlug(slug, myUserId: myId)),
        child: const _BrandProfileView(),
      ),
    );
  }
}

class _BrandProfileView extends StatelessWidget {
  const _BrandProfileView();

  Future<void> _follow(BuildContext context, BrandPublicProfile data) async {
    final cubit = context.read<LoadCubit<BrandPublicProfile>>();
    final following = await context.read<ActionCubit>().run('follow', () => sl<BrandsRepository>().toggleFollow(data.brand.id));
    if (following == null) return;
    HapticFeedback.lightImpact();
    cubit.replace(data.copyWith(isFollowing: following, followerCount: data.followerCount + (following ? 1 : -1)));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandPublicProfile>>();
    final actions = context.watch<ActionCubit>().state;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    final loaded = cubit.state.data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brand'),
        actions: [
          if (loaded != null)
            ShareIconButton(
              size: 44,
              message: () => ShareService.brand(
                slug: loaded.brand.slug,
                name: loaded.brand.companyName,
                industry: loaded.brand.industry,
                mine: loaded.brand.userId == myId,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView<BrandPublicProfile>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (data) {
          final b = data.brand;
          final palette = context.palette;
          return AppRefresh(
            onRefresh: cubit.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
              children: [
                Row(
                  children: [
                    AppNetworkImage(url: b.logoUrl, width: 76, height: 76, radius: 38, placeholderIcon: AppIcons.brand),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(b.companyName, style: context.text.headlineSmall)),
                              if (b.verificationStatus.name == 'verified') ...[
                                const SizedBox(width: AppSpacing.xxs),
                                const Icon(AppIcons.sealCheck, size: 20, color: AppColors.info),
                              ],
                            ],
                          ),
                          if (b.tagline.isNotEmpty) Text(b.tagline, style: context.text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Campaigns', value: '${data.campaignsPosted}', icon: AppIcons.campaigns)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Followers', value: Fmt.compact(data.followerCount), icon: AppIcons.users)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: StatCard(label: 'Rating', value: b.averageRating == 0 ? '—' : b.averageRating.toStringAsFixed(1), icon: AppIcons.star, accent: AppColors.warning)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                data.isFollowing
                    ? AppButton.secondary(label: 'Following', icon: AppIcons.check, isLoading: actions.isBusy, onPressed: actions.isBusy ? null : () => _follow(context, data))
                    : AppButton(label: 'Follow', icon: AppIcons.userPlus, isLoading: actions.isBusy, onPressed: actions.isBusy ? null : () => _follow(context, data)),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'About'),
                AppCard(
                  child: Column(
                    children: [
                      if (b.industry.isNotEmpty) KeyValueRow(label: 'Industry', value: b.industry),
                      if (b.location.isNotEmpty) KeyValueRow(label: 'Headquarters', value: b.location),
                      if (b.foundedYear != null) KeyValueRow(label: 'Founded', value: '${b.foundedYear}'),
                      if (b.companySize.isNotEmpty) KeyValueRow(label: 'Team size', value: b.companySize),
                    ],
                  ),
                ),
                if (b.about.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(b.about, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
                ],
                if (b.website.isNotEmpty || b.socials.values.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  for (final link in [if (b.website.isNotEmpty) b.website, ...b.socials.values.values]) LinkText(url: link),
                ],
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Open campaigns'),
                if (data.campaigns.isEmpty)
                  Text('No open campaigns right now.', style: context.text.bodyMedium)
                else
                  for (final c in data.campaigns) ...[
                    CampaignCard(campaign: c, onTap: () => context.push(AppRoutes.campaignDetail(c.id))),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(title: 'Reviews'),
                if (data.reviews.isEmpty)
                  Text('No reviews yet.', style: context.text.bodyMedium)
                else
                  for (final r in data.reviews) ...[
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(r.from?.name ?? 'Fanitt user', style: context.text.titleSmall)),
                              for (var i = 0; i < 5; i++) Icon(i < r.rating ? AppIcons.starFilled : AppIcons.star, size: 14, color: AppColors.warning),
                            ],
                          ),
                          if (r.comment.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(r.comment, style: context.text.bodyMedium)],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}