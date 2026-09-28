import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../common/data/categories_repository.dart';
import '../../profile/data/profile_models.dart';
import '../data/creators_repository.dart';

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
  Timer? _debounce;
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    final repo = sl<CreatorsRepository>();
    final text = _search.text.trim();
    context.read<PagedCubit<CreatorProfile>>().updateQuery((page) => repo.list(page: page, search: text, categoryId: _categoryId));
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Creators')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), _reload);
              },
              decoration: const InputDecoration(
                hintText: 'Search by skill, niche or bio',
                prefixIcon: Icon(AppIcons.search, size: 20),
              ),
            ),
          ),
          if (categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ChoicePills<String?>(
                scrollable: true,
                options: [null, ...categories.map((c) => c.id)],
                selected: {_categoryId},
                labelOf: (id) => id == null ? 'All' : categories.firstWhere((c) => c.id == id).label,
                onChanged: (id) {
                  setState(() => _categoryId = id);
                  _reload();
                },
              ),
            ),
          Expanded(
            child: PagedListView<CreatorProfile>(
              cubit: context.read<PagedCubit<CreatorProfile>>(),
              empty: const MessageView(icon: AppIcons.creators, title: 'No creators found', message: 'Try a different search or category.'),
              itemBuilder: (context, creator) => CreatorTile(creator: creator),
            ),
          ),
        ],
      ),
    );
  }
}

class CreatorTile extends StatelessWidget {
  const CreatorTile({super.key, required this.creator});

  final CreatorProfile creator;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      onTap: creator.slug.isEmpty ? null : () => context.push(AppRoutes.creatorProfile(creator.slug)),
      child: Row(
        children: [
          UserAvatar(initials: creator.initials, imageUrl: creator.avatarUrl, size: 56),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(creator.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                    if (creator.isProPlan) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      StatusChip(label: creator.planName, color: AppColors.primary),
                    ],
                  ],
                ),
                if (creator.title.isNotEmpty)
                  Text(creator.title, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(AppIcons.users, size: 14, color: palette.textTertiary),
                    const SizedBox(width: 4),
                    Text(Fmt.compact(creator.followerCount), style: context.text.bodySmall),
                    if (creator.reviewCount > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(AppIcons.star, size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text('${creator.averageRating.toStringAsFixed(1)} (${creator.reviewCount})', style: context.text.bodySmall),
                    ],
                    if (creator.location.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(AppIcons.mapPin, size: 14, color: palette.textTertiary),
                      const SizedBox(width: 4),
                      Flexible(child: Text(creator.location, style: context.text.bodySmall, overflow: TextOverflow.ellipsis)),
                    ],
                  ],
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
