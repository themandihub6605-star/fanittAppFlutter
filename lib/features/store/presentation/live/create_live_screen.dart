import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/image_upload_box.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../community/data/community_repository.dart';
import '../../data/store_repository.dart';
import 'my_lives_screen.dart';

enum _Audience { public, invite, community }

/// Set up a live: now or scheduled, free or ticketed, public/invite/community.
class CreateLiveScreen extends StatelessWidget {
  const CreateLiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<Community>>(sl<CommunityRepository>().mine),
        child: const _CreateLiveView(),
      ),
    );
  }
}

class _CreateLiveView extends StatefulWidget {
  const _CreateLiveView();

  @override
  State<_CreateLiveView> createState() => _CreateLiveViewState();
}

class _CreateLiveViewState extends State<_CreateLiveView> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  bool _free = true;
  bool _now = true;
  DateTime? _when;
  _Audience _audience = _Audience.public;
  String? _communityId;
  bool _chat = true;
  PickedMedia? _cover;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _when ?? now.add(const Duration(hours: 1)), firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))));
    if (time == null) return;
    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      if (mounted) AppSnackbar.error(context, 'Pick a time in the future');
      return;
    }
    setState(() => _when = picked);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_now && _when == null) {
      AppSnackbar.error(context, 'Pick when the live starts');
      return;
    }
    if (_audience == _Audience.community && _communityId == null) {
      AppSnackbar.error(context, 'Choose the community');
      return;
    }
    final repo = sl<StoreRepository>();
    final live = await context.read<ActionCubit>().run('create', () async {
      var created = await repo.createLive(
        title: _title.text.trim(),
        description: _description.text.trim(),
        price: _free ? 0 : (Fmt.rupeesToPaise(_price.text) ?? 0),
        isPrivate: _audience != _Audience.public,
        privateMode: switch (_audience) {
          _Audience.invite => 'invite',
          _Audience.community => 'community',
          _Audience.public => null,
        },
        communityId: _audience == _Audience.community ? _communityId : null,
        chatEnabled: _chat,
        scheduledAt: _now ? null : _when,
      );
      if (_cover != null) {
        try {
          created = await repo.uploadLiveCover(created.id, _cover!);
        } on ApiException {
          // The live works without a cover; the creator can retry later.
        }
      }
      return created;
    });
    if (live == null || !mounted) return;
    HapticFeedback.mediumImpact();
    if (_now) {
      await goLiveAsHost(context, live);
      if (mounted) context.pop();
    } else {
      AppSnackbar.success(context, live.inviteCode.isEmpty ? 'Live scheduled' : 'Live scheduled — copy the invite code from your lives list');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final palette = context.palette;
    final communities = (context.watch<LoadCubit<List<Community>>>().state.data ?? const <Community>[]).where((c) => c.canModerate).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New live')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.huge),
          children: [
            // Same shape and look as the live card on the home screen.
            ListenableBuilder(
              listenable: Listenable.merge([_title, _price]),
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.livePoster,
                picked: _cover,
                optional: true,
                enabled: !busy,
                onPick: () async {
                  final picked = await sl<MediaPicker>().image();
                  if (picked != null) setState(() => _cover = picked);
                },
                onRemove: () => setState(() => _cover = null),
                previewBuilder: (context, image) => _LivePosterPreview(
                  image: image,
                  title: _title.text.trim(),
                  isNow: _now,
                  when: _when,
                  priceLabel: _free ? 'FREE' : (Fmt.rupeesToPaise(_price.text) == null ? 'PAID' : Fmt.money(Fmt.rupeesToPaise(_price.text)!)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Title',
              hint: 'e.g. Sunday Q&A — ask me anything',
              controller: _title,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter at least 3 characters' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 5, maxLength: 2000, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('When'),
            ChoicePills<bool>(options: const [true, false], selected: {_now}, labelOf: (v) => v ? 'Go live now' : 'Schedule', onChanged: (v) => setState(() => _now = v)),
            if (!_now) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: busy ? null : _pickWhen,
                icon: const Icon(AppIcons.calendar, size: 18),
                label: Text(_when == null ? 'Pick date & time' : Fmt.weekdayDateTime(_when!)),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Who can watch'),
            ChoicePills<_Audience>(
              scrollable: true,
              options: _Audience.values,
              selected: {_audience},
              labelOf: (a) => switch (a) {
                _Audience.public => 'Everyone',
                _Audience.invite => 'Invite code',
                _Audience.community => 'My community',
              },
              onChanged: (a) => setState(() => _audience = a),
            ),
            if (_audience == _Audience.invite) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('You’ll get a code to share. Only people with it can join.', style: context.text.bodySmall),
            ],
            if (_audience == _Audience.community) ...[
              const SizedBox(height: AppSpacing.sm),
              if (communities.isEmpty)
                Text('You don’t run a community yet. Create one from Communities first.', style: context.text.bodySmall?.copyWith(color: AppColors.warning))
              else
                AppDropdown<String>(
                  label: 'Community',
                  items: communities.map((c) => c.id).toList(),
                  value: _communityId,
                  labelOf: (id) => communities.firstWhere((c) => c.id == id).name,
                  onChanged: (id) => setState(() => _communityId = id),
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: !_free,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => setState(() => _free = !v),
              title: Text('Paid ticket', style: context.text.titleSmall),
              subtitle: Text('Viewers buy a ticket to join', style: context.text.bodySmall),
            ),
            if (!_free)
              AppTextField(
                label: 'Ticket price (₹)',
                controller: _price,
                prefixIcon: AppIcons.rupee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                validator: (v) {
                  final paise = Fmt.rupeesToPaise(v ?? '');
                  if (paise == null || paise <= 0) return 'Enter a price, or make it free';
                  return null;
                },
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _chat,
              activeTrackColor: AppColors.primary,
              onChanged: (v) => setState(() => _chat = v),
              title: Text('Live chat', style: context.text.titleSmall),
              subtitle: Text('Viewers can send messages and hearts', style: context.text.bodySmall),
            ),
            const SizedBox(height: AppSpacing.md),
            const InlineActionError(),
            AppButton(
              label: _now ? 'Go live' : 'Schedule live',
              icon: _now ? AppIcons.broadcast : AppIcons.calendar,
              isLoading: busy,
              onPressed: busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mini copy of the home live card, drawn over the picked poster.
class _LivePosterPreview extends StatelessWidget {
  const _LivePosterPreview({required this.image, required this.title, required this.isNow, required this.when, required this.priceLabel});

  final Widget image;
  final String title;
  final bool isNow;
  final DateTime? when;
  final String priceLabel;

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000), Color(0xEB000000)],
              stops: [0, 0.32, 1],
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: isNow
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
            child: const Text('● LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
          )
              : Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text(when == null ? '—' : '${when!.day}', style: const TextStyle(color: Color(0xFF111111), fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
                Text(when == null ? 'DATE' : _months[when!.month - 1], style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
            child: Text(priceLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
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
                title.isEmpty ? 'Your live title shows here' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: title.isEmpty ? Colors.white70 : Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.22),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  UserAvatar(initials: user?.initials ?? '?', imageUrl: user?.avatarUrl, size: 24),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(isNow ? 'Watch now' : 'View', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
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