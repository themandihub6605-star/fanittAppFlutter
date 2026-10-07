import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/models/common_models.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../common/data/categories_repository.dart';
import '../../profile/data/profile_models.dart';
import '../data/creators_repository.dart';

const _gradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Find creators: search, niche filters and a 2-column photo grid.
class CreatorsScreen extends StatelessWidget {
  const CreatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<CreatorsRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PagedCubit<CreatorProfile>((page) => repo.list(page: page))),
        BlocProvider(create: (_) => LoadCubit<List<Category>>(sl<CategoriesRepository>().getAll)),
      ],
      child: const _CreatorsView(),
    );
  }
}

class _CreatorsView extends StatefulWidget {
  const _CreatorsView();

  @override
  State<_CreatorsView> createState() => _CreatorsViewState();
}

class _CreatorsViewState extends State<_CreatorsView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String? _categoryId;

  PagedCubit<CreatorProfile> get _cubit => context.read<PagedCubit<CreatorProfile>>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _cubit.loadMore();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    final repo = sl<CreatorsRepository>();
    final text = _search.text.trim();
    _cubit.updateQuery((page) => repo.list(page: page, search: text, categoryId: _categoryId));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    final state = context.watch<PagedCubit<CreatorProfile>>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('Creators')),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _reload);
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Search by name, skill, niche or city',
                prefixIcon: const Icon(AppIcons.search, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(AppIcons.close, size: 18),
                  onPressed: () {
                    _search.clear();
                    _reload();
                    setState(() {});
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
          ),
          // Niches
          if (categories.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.xs),
                children: [
                  for (final c in <Category?>[null, ...categories])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        label: Text(c?.label ?? 'All'),
                        selected: _categoryId == c?.id,
                        showCheckmark: false,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: _categoryId == c?.id ? Colors.white : palette.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _categoryId = c?.id);
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: state.isFirstLoad
                ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xl),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
              itemCount: 6,
              itemBuilder: (_, _) => DecoratedBox(
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(18)),
              ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: palette.surface.withValues(alpha: 0.6)),
            )
                : AppRefresh(
              onRefresh: () async => _reload(),
              child: state.items.isEmpty
                  ? const ScrollableMessage(child: MessageView(icon: AppIcons.creators, title: 'No creators found', message: 'Try a different search or niche.'))
                  : GridView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xl),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
                itemCount: state.items.length + (state.hasMore ? 2 : 0),
                itemBuilder: (context, i) {
                  if (i >= state.items.length) {
                    return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  return CreatorTile(creator: state.items[i])
                      .animate(delay: (30 * (i % 10)).ms)
                      .fadeIn(duration: 260.ms)
                      .scaleXY(begin: 0.96, curve: Curves.easeOutCubic);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Portrait creator card: full photo, badges, name, niche and numbers.
/// Tap opens the full profile.
class CreatorTile extends StatefulWidget {
  const CreatorTile({super.key, required this.creator});

  final CreatorProfile creator;

  @override
  State<CreatorTile> createState() => _CreatorTileState();
}

class _CreatorTileState extends State<CreatorTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.creator;
    final hasPhoto = c.avatarUrl != null && c.avatarUrl!.isNotEmpty;
    final verified = c.verificationStatus == VerificationStatus.verified;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: c.slug.isEmpty
          ? null
          : () {
        HapticFeedback.selectionClick();
        context.push(AppRoutes.creatorProfile(c.slug));
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'creator-photo-${c.slug}',
                child: hasPhoto
                    ? CachedNetworkImage(
                  imageUrl: c.avatarUrl!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  placeholder: (_, _) => const DecoratedBox(decoration: BoxDecoration(gradient: _gradient)),
                  errorWidget: (_, _, _) => const DecoratedBox(decoration: BoxDecoration(gradient: _gradient)),
                )
                    : DecoratedBox(
                  decoration: const BoxDecoration(gradient: _gradient),
                  child: Center(child: Text(c.initials, style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800))),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0xD9000000)], stops: [0, 0.45, 1]),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: Row(
                  children: [
                    if (c.isAvailableForWork)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            const Text('Available', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (c.isProPlan)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(6)),
                        child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
                        if (verified) ...[
                          const SizedBox(width: 4),
                          const Icon(AppIcons.sealCheck, size: 15, color: Color(0xFF60A5FA)),
                        ],
                      ],
                    ),
                    Text(
                      c.category?.label ?? (c.title.isEmpty ? 'Creator' : c.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(AppIcons.users, size: 12, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(Fmt.compact(c.followerCount), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        if (c.reviewCount > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(AppIcons.starFilled, size: 12, color: AppColors.sunrise),
                          const SizedBox(width: 3),
                          Text(c.averageRating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                        if (c.location.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(AppIcons.mapPin, size: 12, color: Colors.white70),
                          const SizedBox(width: 2),
                          Flexible(child: Text(c.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}