import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../common/data/categories_repository.dart';
import '../data/community_repository.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<CommunityRepository>();
    return ActionScope(
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PagedCubit<Community>((page) => repo.list(page: page))),
          BlocProvider(create: (_) => LoadCubit<List<Community>>(repo.mine)),
        ],
        child: const _CommunitiesView(),
      ),
    );
  }
}

class _CommunitiesView extends StatelessWidget {
  const _CommunitiesView();

  Future<void> _create(BuildContext context) async {
    final created = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _CreateSheet()));
    if ((created ?? false) && context.mounted) {
      AppSnackbar.success(context, 'Community created');
      context.read<LoadCubit<List<Community>>>().refresh();
      context.read<PagedCubit<Community>>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communities'),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: palette.textSecondary,
            labelStyle: context.text.labelLarge,
            indicatorColor: AppColors.primary,
            dividerColor: palette.border,
            tabs: const [Tab(text: 'Discover'), Tab(text: 'Joined')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(AppIcons.plus), label: const Text('Create')),
        body: TabBarView(
          children: [
            PagedListView<Community>(
              cubit: context.read<PagedCubit<Community>>(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 96),
              empty: const MessageView(icon: AppIcons.users, title: 'No communities yet', message: 'Start one around your niche.'),
              itemBuilder: (context, c) => _CommunityCard(community: c),
            ),
            const _JoinedTab(),
          ],
        ),
      ),
    );
  }
}

class _JoinedTab extends StatelessWidget {
  const _JoinedTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Community>>>();
    return AsyncView<List<Community>>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (items) => AppRefresh(
        onRefresh: cubit.refresh,
        child: items.isEmpty
            ? const ScrollableMessage(child: MessageView(icon: AppIcons.users, title: 'You haven’t joined any community'))
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) => _CommunityCard(community: items[i], joined: true),
              ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.community, this.joined});

  final Community community;
  final bool? joined;

  Future<void> _toggle(BuildContext context) async {
    final result = await context.read<ActionCubit>().run('join-${community.id}', () => sl<CommunityRepository>().toggleJoin(community.id));
    if (result == null || !context.mounted) return;
    AppSnackbar.success(context, result ? 'Joined ${community.name}' : 'Left ${community.name}');
    context.read<LoadCubit<List<Community>>>().refresh();
    context.read<PagedCubit<Community>>().updateItem(
          (c) => c.id == community.id,
          (c) => c.withMembers(c.memberCount + (result ? 1 : -1)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mine = context.watch<LoadCubit<List<Community>>>().state.data ?? const <Community>[];
    final isMember = joined ?? mine.any((c) => c.id == community.id);
    final actions = context.watch<ActionCubit>().state;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: palette.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text(
              community.name.isEmpty ? '#' : community.name.substring(0, 1).toUpperCase(),
              style: context.text.titleLarge?.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(community.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                    if (community.isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(AppIcons.sealCheck, size: 16, color: AppColors.info),
                    ],
                  ],
                ),
                if (community.description.isNotEmpty)
                  Text(community.description, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    Text('${Fmt.compact(community.memberCount)} members', style: context.text.labelSmall),
                    if (community.category != null && community.category!.label.isNotEmpty)
                      StatusChip(label: community.category!.label, color: palette.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          isMember
              ? AppButton.secondary(
                  label: 'Leave',
                  expand: false,
                  height: 38,
                  isLoading: actions.isBusyWith('join-${community.id}'),
                  onPressed: actions.isBusy ? null : () => _toggle(context),
                )
              : AppButton(
                  label: 'Join',
                  expand: false,
                  height: 38,
                  isLoading: actions.isBusyWith('join-${community.id}'),
                  onPressed: actions.isBusy ? null : () => _toggle(context),
                ),
        ],
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<Category> _categories = const [];
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    sl<CategoriesRepository>().getAll().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<ActionCubit>().run(
          'create',
          () => sl<CommunityRepository>().create(name: _name.text.trim(), description: _description.text.trim(), categoryId: _categoryId),
        );
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Create a community',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Name',
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter at least 3 characters' : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 4, maxLength: 500),
            const SizedBox(height: AppSpacing.xs),
            AppDropdown<String>(
              label: 'Category (optional)',
              items: _categories.map((c) => c.id).toList(),
              value: _categoryId,
              labelOf: (id) => _categories.firstWhere((c) => c.id == id).label,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Create community', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
