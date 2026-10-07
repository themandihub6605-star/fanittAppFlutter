import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/image_upload_box.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../data/content_repository.dart';
import '../../store/presentation/meet/meet_detail_screen.dart';
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
              message: 'Host free or paid live sessions and 1:1 calls with your audience — right inside the Fanitt app.',
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
    // Starts the meeting in-app (LiveKit) — no Zoom, no passcode.
    await openMeetRoom(context, session.id);
    if (context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
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

  Future<void> _edit(BuildContext context) async {
    final updated = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _EditSessionSheet(session: session)));
    if (updated == true && context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
  }

  Future<void> _postpone(BuildContext context) async {
    final moved = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _PostponeSheet(session: session)));
    if (moved == true && context.mounted) context.read<LoadCubit<List<LiveSession>>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<ActionCubit>().state;
    final s = session;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover — same card as on the home screen (tap to change)
          GestureDetector(
            onTap: s.isLive ? null : () => _edit(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: ImageSlot.meetPoster.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MeetPosterPreview(
                      image: s.coverImageUrl == null || s.coverImageUrl!.isEmpty
                          ? const DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3B1E5E), Color(0xFF1B1B3A)])),
                        child: Center(child: Icon(AppIcons.videoCamera, color: Colors.white24, size: 48)),
                      )
                          : AppNetworkImage(url: s.coverImageUrl!),
                      title: s.title,
                      when: s.scheduledAt,
                      durationMinutes: s.durationMinutes,
                      isLive: s.isLive,
                    ),
                    if (!s.isLive)
                      Positioned(
                        right: 10,
                        top: 44,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(AppIcons.camera, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Change', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
                AppButton(label: 'Rejoin', icon: AppIcons.videoCamera, expand: false, height: 42, onPressed: () => _start(context)),
                AppButton.secondary(label: 'End session', expand: false, height: 42, isLoading: actions.isBusyWith('live-${s.id}'), onPressed: actions.isBusy ? null : () => _end(context)),
              ] else ...[
                AppButton(label: 'Go live', icon: AppIcons.broadcast, expand: false, height: 42, isLoading: actions.isBusyWith('live-${s.id}'), onPressed: actions.isBusy ? null : () => _start(context)),
                AppButton.secondary(label: 'Postpone', icon: AppIcons.calendar, expand: false, height: 42, onPressed: actions.isBusy ? null : () => _postpone(context)),
                AppButton.secondary(label: 'Edit', icon: AppIcons.pencil, expand: false, height: 42, onPressed: actions.isBusy ? null : () => _edit(context)),
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
            // Poster — same shape and look as the home "Online sessions" card.
            ListenableBuilder(
              listenable: _title,
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.meetPoster,
                picked: _cover,
                optional: true,
                enabled: !busy,
                onPick: () async {
                  final image = await sl<MediaPicker>().image();
                  if (image != null) setState(() => _cover = image);
                },
                onRemove: () => setState(() => _cover = null),
                previewBuilder: (context, image) => MeetPosterPreview(
                  image: image,
                  title: _title.text.trim(),
                  when: _when,
                  durationMinutes: _duration,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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

/// Change a session's cover, title, description, length and seats.
class _EditSessionSheet extends StatefulWidget {
  const _EditSessionSheet({required this.session});

  final LiveSession session;

  @override
  State<_EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends State<_EditSessionSheet> {
  late final _title = TextEditingController(text: widget.session.title);
  late final _description = TextEditingController(text: widget.session.description);
  late final _duration = TextEditingController(text: '${widget.session.durationMinutes}');
  late final _seats = TextEditingController(text: '${widget.session.maxParticipants}');
  PickedMedia? _cover;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    final seats = int.tryParse(_seats.text.trim());
    if (_title.text.trim().length < 3) {
      AppSnackbar.error(context, 'Title needs at least 3 characters');
      return;
    }
    if (duration == null || duration < 5 || duration > 480) {
      AppSnackbar.error(context, 'Length must be 5–480 minutes');
      return;
    }
    if (seats == null || seats < 1) {
      AppSnackbar.error(context, 'Enter how many people can join');
      return;
    }
    final repo = sl<ContentRepository>();
    final ok = await context.read<ActionCubit>().run('save', () async {
      final coverUrl = _cover == null ? null : await repo.uploadSessionBanner(_cover!);
      await repo.updateSession(
        widget.session.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        durationMinutes: duration,
        maxParticipants: seats,
        coverImageUrl: coverUrl,
      );
      return true;
    }, success: 'Session updated');
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final current = widget.session.coverImageUrl;
    return SheetBody(
      title: 'Edit session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([_title, _duration]),
            builder: (context, _) => ImageUploadBox(
              slot: ImageSlot.meetPoster,
              picked: _cover,
              url: current,
              enabled: !busy,
              onPick: () async {
                final picked = await sl<MediaPicker>().image();
                if (picked != null) setState(() => _cover = picked);
              },
              previewBuilder: (context, image) => MeetPosterPreview(
                image: image,
                title: _title.text.trim(),
                when: widget.session.scheduledAt,
                durationMinutes: int.tryParse(_duration.text.trim()) ?? widget.session.durationMinutes,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(label: 'Title', controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Description', controller: _description, minLines: 2, maxLines: 5, maxLength: 1000, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppTextField(label: 'Length (min)', controller: _duration, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(label: 'Seats', controller: _seats, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Save changes', isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}

/// Move a session to a new date and time. People who booked get a notification.
class _PostponeSheet extends StatefulWidget {
  const _PostponeSheet({required this.session});

  final LiveSession session;

  @override
  State<_PostponeSheet> createState() => _PostponeSheetState();
}

class _PostponeSheetState extends State<_PostponeSheet> {
  DateTime? _when;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final start = widget.session.scheduledAt.isAfter(now) ? widget.session.scheduledAt : now;
    final date = await showDatePicker(context: context, initialDate: start.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 180)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(widget.session.scheduledAt));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      if (mounted) AppSnackbar.error(context, 'Pick a time at least 5 minutes from now');
      return;
    }
    setState(() => _when = picked);
  }

  Future<void> _save() async {
    if (_when == null) {
      AppSnackbar.error(context, 'Pick the new date and time');
      return;
    }
    final ok = await context.read<ActionCubit>().run('postpone', () async {
      await sl<ContentRepository>().updateSession(widget.session.id, scheduledAt: _when, rescheduleNote: _note.text.trim());
      return true;
    }, success: widget.session.bookedCount > 0 ? 'Moved — everyone who booked has been told' : 'Session moved');
    if (ok == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final palette = context.palette;
    return SheetBody(
      title: 'Postpone session',
      subtitle: 'Now: ${Fmt.weekdayDateTime(widget.session.scheduledAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: busy ? null : _pick,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _when == null ? palette.border : AppColors.primary, width: _when == null ? 1 : 1.5),
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.calendar, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _when == null ? 'Pick new date & time' : Fmt.weekdayDateTime(_when!),
                      style: context.text.titleSmall?.copyWith(color: _when == null ? palette.textSecondary : palette.textPrimary),
                    ),
                  ),
                  Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Message to attendees (optional)', hint: 'Sorry for the change — see you then!', controller: _note, maxLength: 300, minLines: 2, maxLines: 3),
          if (widget.session.bookedCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${widget.session.bookedCount} people booked this. They’ll get a notification with the new time.', style: context.text.bodySmall),
          ],
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Move session', icon: AppIcons.calendar, isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}

/// The home "Online sessions" card, drawn over a poster — used for the
/// upload preview and the session list so all three look the same.
class MeetPosterPreview extends StatelessWidget {
  const MeetPosterPreview({super.key, required this.image, required this.title, required this.when, required this.durationMinutes, this.isLive = false});

  final Widget image;
  final String title;
  final DateTime? when;
  final int durationMinutes;
  final bool isLive;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    final w = when?.toLocal();
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x00000000), Color(0xE6000000)],
              stops: [0, 0.35, 1],
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text(w == null ? 'SOON' : _months[w.month - 1], style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                Text(w == null ? '—' : '${w.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: isLive ? AppColors.error : Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.videoCamera, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(isLive ? 'LIVE' : 'Online session', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.isEmpty ? 'Your session title shows here' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: title.isEmpty ? Colors.white70 : Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.25),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You${w == null ? '' : ' · ${TimeOfDay.fromDateTime(w).format(context)}'} · $durationMinutes min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(isLive ? 'Rejoin' : 'Start meeting', style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}