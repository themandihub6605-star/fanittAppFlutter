import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/bloc/paged_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/enums/user_role.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/paged_list_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

/// Browse creator stores. Fan home tab, and /app/stores for everyone else.
class StoreDiscoverScreen extends StatelessWidget {
  const StoreDiscoverScreen({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PagedCubit<StoreInfo>((page) => sl<StoreRepository>().stores(page: page))),
        BlocProvider(create: (_) => LoadCubit<List<LiveStream>>(sl<StoreRepository>().liveNow)),
      ],
      child: _DiscoverView(showBack: showBack),
    );
  }
}

class _DiscoverView extends StatefulWidget {
  const _DiscoverView({required this.showBack});

  final bool showBack;

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final text = _search.text.trim();
      context.read<PagedCubit<StoreInfo>>().updateQuery((page) => sl<StoreRepository>().stores(page: page, search: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.showBack,
        title: const Text('Fanitt Store'),
        actions: [
          IconButton(tooltip: 'Virtual Meets', onPressed: () => context.push(AppRoutes.meets), icon: const Icon(AppIcons.videoCamera)),
          IconButton(tooltip: 'My library', onPressed: () => context.push(AppRoutes.library), icon: const Icon(AppIcons.library)),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(hintText: 'Search creator stores', prefixIcon: Icon(AppIcons.search, size: 20)),
            ),
          ),
          const _OpenStoreButton(),
          const _BrowseProductsCard(),
          const _LiveNowRail(),
          Expanded(
            child: PagedListView<StoreInfo>(
              cubit: context.read<PagedCubit<StoreInfo>>(),
              spacing: AppSpacing.sm,
              empty: const MessageView(icon: AppIcons.store, title: 'No stores found', message: 'Try another name.'),
              itemBuilder: (context, s) => _StoreCard(store: s),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});

  final StoreInfo store;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.storePage(store.slug)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  StoreImage(url: store.bannerUrl),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, palette.surface]),
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Hero(tag: 'store-logo-${store.id}', child: StoreLogo(name: store.name, url: store.logoUrl, size: 56, borderColor: palette.surface)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                          if (store.tagline.isNotEmpty) Text(store.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    if (store.stats.orders > 0)
                      Text('${Fmt.compact(store.stats.orders)} sold', style: context.text.labelMedium?.copyWith(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }
}


/// "Live now" strip — only shown when someone is live.
class _LiveNowRail extends StatelessWidget {
  const _LiveNowRail();

  @override
  Widget build(BuildContext context) {
    final lives = context.watch<LoadCubit<List<LiveStream>>>().state.data ?? const <LiveStream>[];
    if (lives.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fade(begin: 1, end: 0.3, duration: 700.ms),
                const SizedBox(width: 6),
                Text('Live now', style: context.text.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 160,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              scrollDirection: Axis.horizontal,
              itemCount: lives.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => LiveCard(live: lives[i], width: 200),
            ),
          ),
        ],
      ),
    );
  }
}


/// Creators without a live store see a button to open (or finish) theirs.
/// Hidden for fans, brands and agencies, and once the store is live.
class _OpenStoreButton extends StatefulWidget {
  const _OpenStoreButton();

  @override
  State<_OpenStoreButton> createState() => _OpenStoreButtonState();
}

class _OpenStoreButtonState extends State<_OpenStoreButton> {
  Future<MyStore?>? _myStore;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>().state;
    if (auth is AuthAuthenticated && auth.user.role == UserRole.creator) _myStore = _load();
  }

  Future<MyStore?> _load() async {
    try {
      return await sl<StoreRepository>().myStore();
    } catch (_) {
      return null; // can't tell — don't show the button
    }
  }

  Future<void> _open() async {
    await context.push(AppRoutes.store);
    // They may have finished setup — check again when they come back.
    if (mounted) setState(() => _myStore = _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_myStore == null) return const SizedBox.shrink();
    return FutureBuilder<MyStore?>(
      future: _myStore,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || (data.store?.isActive ?? false)) return const SizedBox.shrink();
        final settingUp = data.store != null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.sm),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
              child: InkWell(
                onTap: _open,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                  child: Row(
                    children: [
                      const Icon(AppIcons.storeFilled, color: Colors.white, size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          settingUp ? 'Finish setting up your store' : 'Open your Fanitt Store',
                          style: context.text.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                      const Icon(AppIcons.chevronRight, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, curve: Curves.easeOutCubic);
      },
    );
  }
}

/// Shortcut to the marketplace of all products.
class _BrowseProductsCard extends StatelessWidget {
  const _BrowseProductsCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.sm),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.products),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(AppIcons.package, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Browse all products', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Courses, ebooks, templates from every store', style: context.text.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                Icon(AppIcons.chevronRight, color: palette.textTertiary),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}