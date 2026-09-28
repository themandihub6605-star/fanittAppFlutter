import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/services/media_picker.dart';
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
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/content_repository.dart';
import 'gifts_screen.dart';

class MySessionsScreen extends StatelessWidget {
  const MySessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<LiveSession>>(() async => (await sl<DashboardRepository>().creator(myId)).upcomingSessions),
        child: const _SessionsView(),
      ),
    );
  }
}

class _SessionsView extends StatelessWidget {
  const _SessionsView();

  Future<void> _create(BuildContext context) async {
    final created = await showAppSheet<bool>(context, builder: (_) => const SheetActionScope(child: _NewSessionSheet()));
    if ((created ?? false) && context.mounted) {
      AppSnackbar.success(context, 'Session scheduled');
      context.read<LoadCubit<List<LiveSession>>>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<LiveSession>>>();
    return Scaffold(
      appBar: AppBar(title: const Text('Live sessions')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _create(context), icon: const Icon(AppIcons.plus), label: const Text('Schedule')),
      body: AsyncView<List<LiveSession>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (sessions) => AppRefresh(
          onRefresh: cubit.refresh,
          child: sessions.isEmpty
              ? const ScrollableMessage(
                  child: MessageView(
                    icon: AppIcons.videoCamera,
                    title: 'No upcoming sessions',
                    message: 'Host free or paid live sessions and 1:1 calls with your audience over Zoom.',
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, 96),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _SessionCard(session: sessions[index]),
                ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final LiveSession session;

  Future<void> _start(BuildContext context) async {
    final repo = sl<ContentRepository>();
    final ok = await context.read<ActionCubit>().run('live-${session.id}', () async {
      await repo.goLive(session.id);
      if (session.startUrl == null) throw const ApiException('This session has no Zoom link. Cancel it and schedule again.');
      await LinkOpener.open(session.startUrl!);
      return true;
    });
    if (ok != null && context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
  }

  Future<void> _end(BuildContext context) async {
    final ok = await context.read<ActionCubit>().run('live-${session.id}', () async {
      await sl<ContentRepository>().endLive(session.id);
      return true;
    }, success: 'Session ended');
    if (ok != null && context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Cancel this session?',
      message: session.bookedCount > 0 ? '${session.bookedCount} people booked it. They’ll be notified.' : 'It will be removed from your profile.',
      confirmLabel: 'Cancel session',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await context.read<ActionCubit>().run('cancel-${session.id}', () async {
      await sl<ContentRepository>().cancelSession(session.id);
      return true;
    }, success: 'Session cancelled');
    if (ok != null && context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<ActionCubit>().state;
    final s = session;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.title, style: context.text.titleSmall)),
              if (s.isLive) const StatusChip(label: 'Live', color: AppColors.error, icon: AppIcons.broadcast) else StatusChip(label: s.type.label, color: context.palette.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.weekdayDateTime(s.scheduledAt)} · ${s.durationMinutes} min · ${s.type == SessionType.free ? 'Free' : Fmt.money(s.price)}',
            style: context.text.bodySmall,
          ),
          Row(
            children: [
              Expanded(child: Text('${s.bookedCount}/${s.maxParticipants} booked', style: context.text.bodySmall)),
              TextButton.icon(
                onPressed: () => showAppSheet<void>(context, builder: (_) => _TipsSheet(session: s)),
                icon: const Icon(AppIcons.gift, size: 16),
                label: const Text('Tips'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (s.isLive) ...[
                AppButton(label: 'Rejoin', icon: AppIcons.videoCamera, expand: false, height: 42, onPressed: s.startUrl == null ? null : () => LinkOpener.open(s.startUrl!)),
                AppButton.secondary(label: 'End session', expand: false, height: 42, isLoading: actions.isBusyWith('live-${s.id}'), onPressed: actions.isBusy ? null : () => _end(context)),
              ] else ...[
                AppButton(label: 'Go live', icon: AppIcons.broadcast, expand: false, height: 42, isLoading: actions.isBusyWith('live-${s.id}'), onPressed: actions.isBusy ? null : () => _start(context)),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  onPressed: actions.isBusy ? null : () => _cancel(context),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet();

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  SessionType _type = SessionType.free;
  DateTime? _when;
  int _duration = 60;
  int _seats = 50;
  String? _categoryId;
  List<Category> _categories = const [];
  PickedMedia? _cover;

  @override
  void initState() {
    super.initState();
    sl<CategoriesRepository>().getAll().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 180)), initialDate: _when ?? now.add(const Duration(days: 1)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))));
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final actions = context.read<ActionCubit>();
    if (_when == null || _when!.isBefore(DateTime.now())) {
      await actions.run<void>('create', () async => throw const ApiException('Pick a date and time in the future.'));
      return;
    }
    final repo = sl<ContentRepository>();
    final ok = await actions.run('create', () async {
      final coverUrl = _cover == null ? null : await repo.uploadSessionBanner(_cover!);
      return repo.createSession(
        title: _title.text.trim(),
        description: _description.text.trim(),
        categoryId: _categoryId!,
        type: _type,
        price: Fmt.rupeesToPaise(_price.text) ?? 0,
        scheduledAt: _when!,
        durationMinutes: _duration,
        maxParticipants: _type == SessionType.oneToOne ? 1 : _seats,
        coverImageUrl: coverUrl,
      );
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Schedule a session',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Title', controller: _title, textCapitalization: TextCapitalization.sentences, validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter a title' : null),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 4),
            const SizedBox(height: AppSpacing.md),
            AppDropdown<String>(
              label: 'Category',
              items: _categories.map((c) => c.id).toList(),
              value: _categoryId,
              labelOf: (id) => _categories.firstWhere((c) => c.id == id).label,
              onChanged: (id) => setState(() => _categoryId = id),
              validator: (v) => v == null ? 'Choose a category' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Type'),
            ChoicePills<SessionType>(options: SessionType.values, selected: {_type}, labelOf: (t) => t.label, onChanged: (t) => setState(() => _type = t)),
            if (_type != SessionType.free) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Price',
                controller: _price,
                prefixIcon: AppIcons.rupee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                validator: (v) => (Fmt.rupeesToPaise(v ?? '') ?? 0) < 100 ? 'Enter at least ₹1' : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Date & time'),
            AppCard(
              onTap: _pickDateTime,
              child: Row(
                children: [
                  Icon(AppIcons.calendar, size: 20, color: context.palette.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_when == null ? 'Choose when' : Fmt.weekdayDateTime(_when!), style: context.text.titleSmall)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Duration'),
            ChoicePills<int>(options: const [15, 30, 45, 60, 90, 120], selected: {_duration}, labelOf: (m) => '$m min', onChanged: (m) => setState(() => _duration = m)),
            if (_type != SessionType.oneToOne) ...[
              const SizedBox(height: AppSpacing.md),
              CounterField(label: 'Seats', value: _seats, min: 1, max: 1000, onChanged: (v) => setState(() => _seats = v)),
            ],
            const SizedBox(height: AppSpacing.md),
            AppCard(
              onTap: () async {
                final image = await sl<MediaPicker>().image();
                if (image != null) setState(() => _cover = image);
              },
              child: Row(
                children: [
                  Icon(_cover == null ? AppIcons.image : AppIcons.checkCircle, color: _cover == null ? context.palette.textSecondary : AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(_cover?.name ?? 'Add a cover image (optional)', style: context.text.titleSmall, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Schedule session', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _TipsSheet extends StatelessWidget {
  const _TipsSheet({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Tip>>(() => sl<ContentRepository>().sessionTips(session.id)),
      child: Builder(
        builder: (context) {
          final cubit = context.watch<LoadCubit<List<Tip>>>();
          return SheetBody(
            title: 'Tips for ${session.title}',
            child: SizedBox(
              height: 320,
              child: AsyncView<List<Tip>>(
                state: cubit.state,
                onRetry: cubit.load,
                builder: (tips) => tips.isEmpty
                    ? const MessageView(icon: AppIcons.gift, title: 'No tips yet', message: 'Fans can tip you while you’re live.')
                    : ListView.separated(
                        itemCount: tips.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (_, i) => TipTile(tip: tips[i]),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
