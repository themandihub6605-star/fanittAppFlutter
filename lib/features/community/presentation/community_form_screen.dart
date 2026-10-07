import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/models/common_models.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/image_upload_box.dart';
import '../../common/data/categories_repository.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';

/// Create a community, or edit one. The owner sees every setting;
/// moderators can change description, rules, images and category.
class CommunityFormScreen extends StatelessWidget {
  const CommunityFormScreen({super.key, this.community});

  final Community? community;

  @override
  Widget build(BuildContext context) => ActionScope(child: _FormView(community: community));
}

class _FormView extends StatefulWidget {
  const _FormView({this.community});

  final Community? community;

  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.community?.name ?? '');
  late final _description = TextEditingController(text: widget.community?.description ?? '');
  final _ruleDraft = TextEditingController();
  late List<String> _rules = [...?widget.community?.rules];
  late String? _categoryId = widget.community?.category?.id;
  late bool _isPrivate = widget.community?.isPrivate ?? false;
  late bool _onlyMods = widget.community?.onlyModeratorsPost ?? false;
  late bool _chatEnabled = widget.community?.chatEnabled ?? true;
  PickedMedia? _icon;
  PickedMedia? _cover;
  List<Category> _categories = const [];

  // ---- Paid community ----
  CommunityConfig? _config;
  late bool _isPaid = widget.community?.isPaid ?? false;
  late final Map<CommunityPlanKey, bool> _planOn = {
    for (final k in CommunityPlanKey.values)
      k: (widget.community?.plans.isNotEmpty ?? false) ? widget.community!.plans.any((p) => p.key == k) : k == CommunityPlanKey.monthly,
  };
  late final Map<CommunityPlanKey, TextEditingController> _planPrice = {
    for (final k in CommunityPlanKey.values)
      k: TextEditingController(
        text: () {
          final p = widget.community?.plans.where((p) => p.key == k).firstOrNull;
          return p == null ? '' : (p.price ~/ 100).toString();
        }(),
      ),
  };

  bool get _isEdit => widget.community != null;
  bool get _ownerFields => !_isEdit || widget.community!.isOwner;

  @override
  void initState() {
    super.initState();
    sl<CategoriesRepository>().getAll().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await sl<CommunityRepository>().config();
      if (mounted) setState(() => _config = config);
    } catch (_) {
      // Server still checks everything on save.
    }
  }

  /// Creating is blocked until the user picks a Fanitt plan (admin switch).
  bool get _blocked => !_isEdit && (_config?.blocked ?? false);

  /// Paid options shown to the owner when allowed.
  bool get _showPaid => _ownerFields && (_config?.paidEnabled ?? false) && ((_config?.canSell ?? false) || (widget.community?.isPaid ?? false));

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _ruleDraft.dispose();
    for (final c in _planPrice.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await sl<MediaPicker>().image();
    if (picked != null) setState(() => _cover = picked);
  }

  Future<void> _pickIcon() async {
    final picked = await sl<MediaPicker>().image();
    if (picked != null) setState(() => _icon = picked);
  }

  void _addRule() {
    final value = _ruleDraft.text.trim();
    if (value.isEmpty || _rules.length >= 10) return;
    setState(() => _rules = [..._rules, value.length > 300 ? value.substring(0, 300) : value]);
    _ruleDraft.clear();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_showPaid && _isPaid && !_planOn.values.any((on) => on)) {
      AppSnackbarLite.show(context, 'Turn on at least one plan — monthly, yearly or one-time.');
      return;
    }
    final repo = sl<CommunityRepository>();
    final sendPaid = _showPaid;
    final input = CommunityInput(
      isPaid: sendPaid ? _isPaid : null,
      plans: sendPaid
          ? {
        for (final k in CommunityPlanKey.values)
          k: (enabled: _isPaid && _planOn[k]!, price: (int.tryParse(_planPrice[k]!.text.trim()) ?? 0) * 100),
      }
          : null,
      name: _ownerFields ? _name.text.trim() : null,
      description: _description.text.trim(),
      categoryId: _categoryId ?? '',
      isPrivate: _ownerFields ? _isPrivate : null,
      onlyModeratorsPost: _ownerFields ? _onlyMods : null,
      chatEnabled: _ownerFields ? _chatEnabled : null,
      rules: _rules,
      icon: _icon,
      cover: _cover,
    );
    final saved = await context.read<ActionCubit>().run(
      'save',
          () => _isEdit ? repo.update(widget.community!.id, input) : repo.create(input),
    );
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  Widget _imageOrNetwork(PickedMedia? picked, String? url, {BoxFit fit = BoxFit.cover}) {
    if (picked != null) return Image.file(File(picked.path), fit: fit);
    if (url != null && url.isNotEmpty) return Image.network(url, fit: fit);
    return const SizedBox.shrink();
  }

  bool get _hasCover => _cover != null || (widget.community?.coverImageUrl ?? '').isNotEmpty;
  bool get _hasIcon => _icon != null || (widget.community?.iconUrl ?? '').isNotEmpty;

  /// Join button text exactly as members will see it.
  String get _joinLabel {
    if (_showPaid && _isPaid) {
      final prices = [
        for (final k in CommunityPlanKey.values)
          if (_planOn[k]!) int.tryParse(_planPrice[k]!.text.trim()) ?? 0,
      ].where((p) => p > 0).toList()
        ..sort();
      if (prices.isNotEmpty) return 'Join · from ₹${prices.first}';
    }
    return _isPrivate ? 'Request to join' : 'Join community';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final busy = context.watch<ActionCubit>().state.isBusy;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Community settings' : 'New community')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
          children: [
            // Cover — same shape and look as the community card on Home.
            ListenableBuilder(
              listenable: Listenable.merge([_name, _description, ..._planPrice.values]),
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.communityCover,
                picked: _cover,
                url: widget.community?.coverImageUrl,
                optional: true,
                enabled: !busy,
                onPick: _pickCover,
                onRemove: _cover == null ? null : () => setState(() => _cover = null),
                previewBuilder: (context, image) => CommunityCardPreview(
                  image: image,
                  icon: _hasIcon ? _imageOrNetwork(_icon, widget.community?.iconUrl) : null,
                  name: _ownerFields ? _name.text.trim() : widget.community!.name,
                  about: _description.text.trim(),
                  category: _categories.where((c) => c.id == _categoryId).firstOrNull?.label ?? widget.community?.category?.label ?? '',
                  isPrivate: _isPrivate,
                  members: widget.community?.memberCount ?? 1,
                  posts: widget.community?.discussionCount ?? 0,
                  joinLabel: _joinLabel,
                ),
              ),
            ),
            if (_hasCover) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Also used as the banner on your community page', style: context.text.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              _BannerPreview(
                cover: _imageOrNetwork(_cover, widget.community?.coverImageUrl),
                icon: _hasIcon ? _imageOrNetwork(_icon, widget.community?.iconUrl) : null,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            // Icon — rounded square, shown next to the name everywhere.
            ImageUploadBox(
              slot: ImageSlot.squareIcon,
              picked: _icon,
              url: widget.community?.iconUrl,
              optional: true,
              enabled: !busy,
              width: 84,
              onPick: _pickIcon,
            ),
            const SizedBox(height: AppSpacing.lg),

            if (_ownerFields) ...[
              AppTextField(
                label: 'Name',
                controller: _name,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter at least 3 characters' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppTextField(
              label: 'About',
              hint: 'What is this community about and who is it for?',
              controller: _description,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppDropdown<String>(
              label: 'Category',
              items: _categories.map((c) => c.id).toList(),
              value: _categoryId != null && _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
              labelOf: (id) => _categories.firstWhere((c) => c.id == id).label,
              onChanged: (id) => setState(() => _categoryId = id),
            ),

            if (_ownerFields) ...[
              const SizedBox(height: AppSpacing.lg),
              const FieldLabel('Who can join'),
              Row(
                children: [
                  Expanded(
                    child: _OptionCard(
                      icon: AppIcons.globe,
                      title: 'Public',
                      hint: 'Anyone can join and read',
                      selected: !_isPrivate,
                      onTap: () => setState(() => _isPrivate = false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _OptionCard(
                      icon: AppIcons.lock,
                      title: 'Private',
                      hint: 'You approve every member',
                      selected: _isPrivate,
                      onTap: () => setState(() => _isPrivate = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: _onlyMods,
                      onChanged: (v) => setState(() => _onlyMods = v),
                      activeColor: AppColors.primary,
                      title: Text('Only owner & moderators can post', style: context.text.titleSmall),
                      subtitle: Text('Members can still comment, like and vote', style: context.text.bodySmall),
                    ),
                    Divider(height: 1, color: palette.border),
                    SwitchListTile.adaptive(
                      value: _chatEnabled,
                      onChanged: (v) => setState(() => _chatEnabled = v),
                      activeColor: AppColors.primary,
                      title: Text('Group chat', style: context.text.titleSmall),
                      subtitle: Text('A live chat room for members', style: context.text.bodySmall),
                    ),
                  ],
                ),
              ),
            ],

            if (_showPaid) ...[
              const SizedBox(height: AppSpacing.lg),
              _PaidSection(
                isPaid: _isPaid,
                onPaidChanged: (v) => setState(() => _isPaid = v),
                planOn: _planOn,
                onPlanToggled: (k, v) => setState(() => _planOn[k] = v),
                prices: _planPrice,
                config: _config!,
                onPriceChanged: () => setState(() {}),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            FieldLabel('Rules (${_rules.length}/10)'),
            for (final (i, rule) in _rules.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
                  child: Row(
                    children: [
                      Text('${i + 1}', style: context.text.titleSmall?.copyWith(color: AppColors.primary)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(rule, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary))),
                      IconButton(
                        tooltip: 'Remove rule',
                        icon: Icon(AppIcons.trash, size: 18, color: palette.textSecondary),
                        onPressed: () => setState(() => _rules = [..._rules]..removeAt(i)),
                      ),
                    ],
                  ),
                ),
              ),
            if (_rules.length < 10)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ruleDraft,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _addRule(),
                      decoration: const InputDecoration(hintText: 'e.g. Be respectful — no spam'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filledTonal(onPressed: _addRule, icon: const Icon(AppIcons.plus)),
                ],
              ),

            const SizedBox(height: AppSpacing.xl),
            if (_blocked) ...[
              _PlanNeededCard(onSeePlans: () async {
                await context.push(AppRoutes.plans);
                _loadConfig();
              }),
              const SizedBox(height: AppSpacing.md),
            ],
            const InlineActionError(),
            AppButton(label: _isEdit ? 'Save changes' : 'Create community', isLoading: busy, onPressed: busy || _blocked ? null : _save),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.hint, required this.selected, required this.onTap});

  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        color: selected ? palette.primarySoft : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.primary : palette.textSecondary),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: context.text.titleSmall),
              Text(hint, style: context.text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny snackbar helper so this file doesn't depend on app_snackbar's API.
abstract final class AppSnackbarLite {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const _brand = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Shown when the admin requires a paid Fanitt plan to create communities.
class _PlanNeededCard extends StatelessWidget {
  const _PlanNeededCard({required this.onSeePlans});

  final VoidCallback onSeePlans;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          const Icon(AppIcons.crown, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fanitt plan needed', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Pick a monthly or yearly plan to create communities.', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSeePlans,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
            child: const Text('See plans'),
          ),
        ],
      ),
    );
  }
}

/// "Paid community" switch + monthly / yearly / one-time prices.
class _PaidSection extends StatelessWidget {
  const _PaidSection({
    required this.isPaid,
    required this.onPaidChanged,
    required this.planOn,
    required this.onPlanToggled,
    required this.prices,
    required this.config,
    required this.onPriceChanged,
  });

  final bool isPaid;
  final ValueChanged<bool> onPaidChanged;
  final Map<CommunityPlanKey, bool> planOn;
  final void Function(CommunityPlanKey, bool) onPlanToggled;
  final Map<CommunityPlanKey, TextEditingController> prices;
  final CommunityConfig config;
  final VoidCallback onPriceChanged;

  String _hint(CommunityPlanKey k) => switch (k) {
    CommunityPlanKey.monthly => 'Members pay every month',
    CommunityPlanKey.yearly => 'Members pay once a year',
    CommunityPlanKey.lifetime => 'Pay once, access forever',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final min = config.minPrice ~/ 100;
    final max = config.maxPrice ~/ 100;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        gradient: isPaid ? _brand : null,
        color: isPaid ? null : palette.border,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16.5)),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(AppIcons.crown, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Paid community', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text('Members pay to join — money goes to your wallet', style: context.text.bodySmall),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isPaid,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onPaidChanged(v);
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: !isPaid
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md, right: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final k in CommunityPlanKey.values) ...[
                      _PlanRow(
                        title: k.label,
                        hint: _hint(k),
                        on: planOn[k]!,
                        onToggle: (v) => onPlanToggled(k, v),
                        controller: prices[k]!,
                        suffix: k == CommunityPlanKey.lifetime ? 'once' : (k == CommunityPlanKey.monthly ? '/month' : '/year'),
                        min: min,
                        max: max,
                        feePercent: config.feePercent,
                        onChanged: onPriceChanged,
                      ),
                      if (k != CommunityPlanKey.lifetime) Divider(height: AppSpacing.lg, color: palette.border),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'People who are already members keep free access. Renewals are manual — members get a reminder before their plan ends.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.title,
    required this.hint,
    required this.on,
    required this.onToggle,
    required this.controller,
    required this.suffix,
    required this.min,
    required this.max,
    required this.feePercent,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool on;
  final ValueChanged<bool> onToggle;
  final TextEditingController controller;
  final String suffix;
  final int min;
  final int max;
  final double feePercent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final price = int.tryParse(controller.text.trim()) ?? 0;
    final youGet = (price * 100 * (100 - feePercent) / 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(hint, style: context.text.bodySmall),
                ],
              ),
            ),
            Switch.adaptive(value: on, activeColor: AppColors.primary, onChanged: onToggle),
          ],
        ),
        if (on) ...[
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              prefixText: '₹ ',
              suffixText: suffix,
              hintText: 'Price',
              isDense: true,
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim()) ?? 0;
              if (n < min || n > max) return 'Enter between ₹$min and ₹${Fmt.compact(max)}';
              return null;
            },
          ),
          if (price > 0 && feePercent > 0) ...[
            const SizedBox(height: 4),
            Text(
              'You get about ${Fmt.money(youGet)} after Fanitt’s ${feePercent.toStringAsFixed(feePercent % 1 == 0 ? 0 : 1)}% fee',
              style: context.text.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ],
    );
  }
}

/// The Home community card drawn over the cover — the upload preview.
class CommunityCardPreview extends StatelessWidget {
  const CommunityCardPreview({
    super.key,
    required this.image,
    required this.name,
    required this.about,
    required this.category,
    required this.isPrivate,
    required this.members,
    required this.posts,
    required this.joinLabel,
    this.icon,
  });

  final Widget image;
  final Widget? icon;
  final String name;
  final String about;
  final String category;
  final bool isPrivate;
  final int members;
  final int posts;
  final String joinLabel;

  static Widget _chip(String label, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 11, color: Colors.white), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3))),
      ],
    ),
  );

  static Widget _stat(IconData icon, String value, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: Colors.white70),
      const SizedBox(width: 4),
      Flexible(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            TextSpan(text: ' $label', style: const TextStyle(color: Colors.white70)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x4D000000), Color(0x00000000), Color(0x8C000000), Color(0xE0000000), Color(0xFA000000)],
              stops: [0, 0.22, 0.48, 0.74, 1],
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Row(
            children: [
              if (category.isNotEmpty) Flexible(child: _chip(category)) else const Spacer(),
              if (isPrivate) ...[const SizedBox(width: 6), _chip('Private', icon: AppIcons.lock)],
            ],
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: icon ?? const ColoredBox(color: Color(0xFFEDE9FE), child: Icon(AppIcons.users, size: 20, color: Color(0xFF6D5DFC))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Community name' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: name.isEmpty ? Colors.white70 : Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                about.isEmpty ? 'What your community is about shows here' : about,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _stat(AppIcons.users, Fmt.compact(members), 'members'),
                  const SizedBox(width: 12),
                  Flexible(child: _stat(AppIcons.messages, Fmt.compact(posts), 'posts')),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isPrivate ? AppIcons.lock : AppIcons.plus, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(child: Text(joinLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wide banner as shown at the top of the community page (3 : 1).
class _BannerPreview extends StatelessWidget {
  const _BannerPreview({required this.cover, this.icon});

  final Widget cover;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(aspectRatio: 3, child: SizedBox.expand(child: cover)),
          ),
          Positioned(
            left: AppSpacing.md,
            bottom: -26,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.background, width: 3),
                color: palette.surfaceMuted,
              ),
              clipBehavior: Clip.antiAlias,
              child: icon ?? Icon(AppIcons.users, color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}