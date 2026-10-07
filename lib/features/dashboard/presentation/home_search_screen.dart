import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/guards/profile_gate.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../brands/data/brands_repository.dart';
import '../../community/data/community_repository.dart';
import '../../creators/data/creators_repository.dart';
import '../../store/data/store_repository.dart';
import 'home_discover.dart';

enum _Kind {
  all('All'),
  creators('Creators'),
  brands('Brands'),
  communities('Communities'),
  stores('Stores');

  const _Kind(this.label);
  final String label;
}

class _Hit {
  const _Hit({required this.kind, required this.title, required this.subtitle, required this.imageUrl, required this.route, this.verified = false});

  final _Kind kind;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String route;
  final bool verified;
}

/// One search box for creators, brands, communities and stores.
class HomeSearchScreen extends StatefulWidget {
  const HomeSearchScreen({super.key, this.showFilters = false});

  final bool showFilters;

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  _Kind _kind = _Kind.all;
  bool _loading = false;
  List<_Hit> _hits = const [];
  int _requestId = 0;

  bool get _canSeeCreators {
    final auth = context.read<AuthBloc>().state;
    return !needsProfileCompletion(auth is AuthAuthenticated ? auth.user : null);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.showFilters) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _hits = const [];
        _loading = false;
      });
      return;
    }
    final id = ++_requestId;
    setState(() => _loading = true);

    bool want(_Kind k) => _kind == _Kind.all || _kind == k;
    Future<List<_Hit>> safe(Future<List<_Hit>> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      if (want(_Kind.creators) && _canSeeCreators)
        safe(() async => (await sl<CreatorsRepository>().list(search: q)).items.take(10).map((c) => _Hit(
          kind: _Kind.creators,
          title: c.name,
          subtitle: [c.category?.label ?? c.title, '${Fmt.compact(c.followerCount)} followers'].where((s) => s.isNotEmpty).join(' · '),
          imageUrl: c.avatarUrl,
          route: AppRoutes.creatorProfile(c.slug),
        )).toList()),
      if (want(_Kind.brands))
        safe(() async => (await sl<BrandsRepository>().list(search: q)).items.take(10).map((b) => _Hit(
          kind: _Kind.brands,
          title: b.profile.companyName,
          subtitle: b.profile.industry.isEmpty ? 'Brand' : b.profile.industry,
          imageUrl: b.logoUrl,
          route: AppRoutes.brandProfile(b.profile.slug),
        )).toList()),
      if (want(_Kind.communities))
        safe(() async => (await sl<CommunityRepository>().list(search: q)).items.take(10).map((c) => _Hit(
          kind: _Kind.communities,
          title: c.name,
          subtitle: '${Fmt.compact(c.memberCount)} members',
          imageUrl: c.iconUrl,
          route: AppRoutes.communityDetail(c.slug),
          verified: c.isVerified,
        )).toList()),
      if (want(_Kind.stores))
        safe(() async => (await sl<StoreRepository>().stores(search: q)).items.take(10).map((s) => _Hit(
          kind: _Kind.stores,
          title: s.name,
          subtitle: s.tagline.isEmpty ? 'Creator store' : s.tagline,
          imageUrl: s.logoUrl,
          route: AppRoutes.storePage(s.slug),
        )).toList()),
    ]);
    if (!mounted || id != _requestId) return; // a newer search started
    setState(() {
      _hits = results.expand((r) => r).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final q = _query.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.gutter),
          child: TextField(
            controller: _query,
            focusNode: _focus,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search Fanitt',
              prefixIcon: const Icon(AppIcons.search, size: 20),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                tooltip: 'Clear',
                icon: const Icon(AppIcons.close, size: 18),
                onPressed: () {
                  _query.clear();
                  _onChanged('');
                },
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(kHomeButtonRadius), borderSide: BorderSide(color: palette.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kHomeButtonRadius), borderSide: BorderSide(color: palette.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(kHomeButtonRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filters
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.xs),
              itemCount: _Kind.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, i) {
                final k = _Kind.values[i];
                if (k == _Kind.creators && !_canSeeCreators) return const SizedBox.shrink();
                final selected = _kind == k;
                return ChoiceChip(
                  label: Text(k.label),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(color: selected ? Colors.white : palette.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kHomeButtonRadius)),
                  onSelected: (_) {
                    setState(() => _kind = k);
                    _search();
                  },
                );
              },
            ),
          ),
          Expanded(child: _results(context, q)),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, String q) {
    final palette = context.palette;
    if (q.length < 2) {
      return _Empty(icon: AppIcons.search, title: 'Search Fanitt', message: 'Find creators, brands, communities and creator stores.');
    }
    if (_loading && _hits.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.xs),
        itemCount: 6,
        itemBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(kHomeButtonRadius))),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 160, height: 12, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(width: 100, height: 10, decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ],
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6)),
        ),
      );
    }
    if (_hits.isEmpty) {
      return _Empty(icon: AppIcons.search, title: 'No results for “$q”', message: 'Try a different name or another filter.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
      itemCount: _hits.length,
      separatorBuilder: (_, _) => Divider(height: 1, indent: 60, color: palette.border),
      itemBuilder: (context, i) {
        final h = _hits[i];
        return InkWell(
          borderRadius: BorderRadius.circular(kHomeButtonRadius),
          onTap: () => context.push(h.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(h.kind == _Kind.creators ? 24 : kHomeButtonRadius),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: h.imageUrl == null || h.imageUrl!.isEmpty
                        ? ColoredBox(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      child: Center(child: Text(h.title.isEmpty ? '?' : h.title[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18))),
                    )
                        : CachedNetworkImage(imageUrl: h.imageUrl!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600))),
                          if (h.verified) ...[
                            const SizedBox(width: 4),
                            const Icon(AppIcons.sealCheck, size: 14, color: AppColors.info),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                  child: Text(h.kind.label.substring(0, h.kind.label.length - 1), style: context.text.labelSmall?.copyWith(fontSize: 11)),
                ),
              ],
            ),
          ),
        ).animate(delay: (25 * i.clamp(0, 10)).ms).fadeIn(duration: 200.ms);
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, size: 32, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(fontSize: 14)),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}