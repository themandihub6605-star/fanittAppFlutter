// File: lib/features/store/presentation/live/create_live_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  const CreateLiveScreen({super.key, this.communityId});

  /// Opened from a community: start with "Community members" picked for it.
  final String? communityId;

  @override
  Widget build(BuildContext context) {
    return ActionScope(
      child: BlocProvider(
        create: (_) => LoadCubit<List<Community>>(sl<CommunityRepository>().mine),
        child: _CreateLiveView(communityId: communityId),
      ),
    );
  }
}

class _CreateLiveView extends StatefulWidget {
  const _CreateLiveView({this.communityId});

  final String? communityId;

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
  void initState() {
    super.initState();
    final id = widget.communityId;
    if (id != null && id.isNotEmpty) {
      _audience = _Audience.community;
      _communityId = id;
    }
  }

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
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('New live', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 10, AppSpacing.gutter, 10),
          decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InlineActionError(),
              _PrimaryButton(
                label: _now ? 'Go live now' : 'Schedule live',
                icon: _now ? AppIcons.broadcast : AppIcons.calendar,
                busy: busy,
                onTap: busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xl),
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
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 18),

            _Section(
              title: 'Details',
              child: Column(
                children: [
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
                ],
              ),
            ),

            _Section(
              title: 'When',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _OptionTile(
                          icon: AppIcons.lightning,
                          title: 'Go live now',
                          subtitle: 'Start right away',
                          selected: _now,
                          accent: AppColors.error,
                          onTap: () => setState(() => _now = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionTile(
                          icon: AppIcons.calendar,
                          title: 'Schedule',
                          subtitle: 'Followers get told',
                          selected: !_now,
                          onTap: () => setState(() => _now = false),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: _now
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _PickRow(
                        icon: AppIcons.clock,
                        label: _when == null ? 'Pick date & time' : Fmt.weekdayDateTime(_when!),
                        highlight: _when == null,
                        onTap: busy ? null : _pickWhen,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _Section(
              title: 'Who can watch',
              child: Column(
                children: [
                  for (final a in _Audience.values) ...[
                    _OptionRow(
                      icon: switch (a) {
                        _Audience.public => AppIcons.globe,
                        _Audience.invite => AppIcons.link,
                        _Audience.community => AppIcons.users,
                      },
                      title: switch (a) {
                        _Audience.public => 'Everyone',
                        _Audience.invite => 'Invite code',
                        _Audience.community => 'My community',
                      },
                      subtitle: switch (a) {
                        _Audience.public => 'Anyone on Fanitt can find and watch',
                        _Audience.invite => 'You get a code — only people with it can join',
                        _Audience.community => 'Only members of a community you run',
                      },
                      selected: _audience == a,
                      onTap: () => setState(() => _audience = a),
                    ),
                    if (a != _Audience.values.last) const SizedBox(height: 8),
                  ],
                  if (_audience == _Audience.community) ...[
                    const SizedBox(height: AppSpacing.sm),
                    if (communities.isEmpty)
                      Text('You don’t run a community yet. Create one from Communities first.', style: context.text.bodySmall?.copyWith(color: AppColors.warning))
                    else
                      AppDropdown<String>(
                        label: 'Community',
                        items: communities.map((c) => c.id).toList(),
                        // Only a community from this list (avoids a dropdown error).
                        value: communities.any((c) => c.id == _communityId) ? _communityId : null,
                        labelOf: (id) => communities.firstWhere((c) => c.id == id).name,
                        onChanged: (id) => setState(() => _communityId = id),
                      ),
                  ],
                ],
              ),
            ),

            _Section(
              title: 'Ticket',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _OptionTile(
                          icon: AppIcons.gift,
                          title: 'Free',
                          subtitle: 'Anyone allowed joins',
                          selected: _free,
                          accent: AppColors.success,
                          onTap: () => setState(() => _free = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionTile(
                          icon: AppIcons.receipt,
                          title: 'Paid ticket',
                          subtitle: 'Viewers buy to join',
                          selected: !_free,
                          onTap: () => setState(() => _free = false),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: _free
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppTextField(
                        label: 'Ticket price (₹)',
                        controller: _price,
                        prefixIcon: AppIcons.rupee,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        validator: (v) {
                          if (_free) return null;
                          final paise = Fmt.rupeesToPaise(v ?? '');
                          if (paise == null || paise <= 0) return 'Enter a price, or make it free';
                          return null;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _Section(
              title: 'Extras',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _chat,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _chat = v),
                title: Text('Live chat', style: context.text.titleSmall),
                subtitle: Text('Viewers can send messages and hearts', style: context.text.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White rounded card with a small heading.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: palette.textPrimary)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04);
  }
}

/// Big square-ish choice tile (When / Ticket).
class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap, this.accent = AppColors.primary});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: context.isDark ? 0.18 : 0.08) : palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : palette.border, width: selected ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? accent : palette.surfaceMuted),
                  child: Icon(icon, size: 17, color: selected ? Colors.white : palette.textSecondary),
                ),
                const Spacer(),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Icon(AppIcons.checkCircle, size: 20, color: accent),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Full-width radio row (Who can watch).
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: context.isDark ? 0.18 : 0.07) : palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? AppColors.primary : palette.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.textPrimary)),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: palette.textSecondary)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 6 : 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.label, required this.highlight, required this.onTap});

  final IconData icon;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: AppColors.primary.withValues(alpha: context.isDark ? 0.14 : 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 19, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: highlight ? AppColors.primary : palette.textPrimary)),
              ),
              Text(highlight ? 'Choose' : 'Change', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient main button (red → orange), with a soft shine while idle.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.icon, required this.busy, required this.onTap});

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: const LinearGradient(colors: [Color(0xFFFF3B5C), AppColors.primary, Color(0xFFFF8A4C)]),
          boxShadow: [BoxShadow(color: AppColors.error.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
    if (busy) return button;
    return button.animate(onPlay: (c) => c.repeat()).shimmer(delay: 1800.ms, duration: 1200.ms, color: Colors.white.withValues(alpha: 0.35));
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