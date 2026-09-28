import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/models/common_models.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../common/data/categories_repository.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';
import '../widgets/campaign_widgets.dart';
import 'campaign_editor_cubit.dart';

class CampaignEditorScreen extends StatelessWidget {
  const CampaignEditorScreen({super.key, this.draftId});

  final String? draftId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => CampaignEditorCubit(sl<CampaignRepository>(), draftId: draftId)),
        BlocProvider(create: (_) => LoadCubit<List<Category>>(sl<CategoriesRepository>().getAll)),
      ],
      child: const _EditorView(),
    );
  }
}

class _EditorView extends StatelessWidget {
  const _EditorView();

  static const _titles = {
    EditorStep.basics: 'Campaign basics',
    EditorStep.budget: 'Budget & products',
    EditorStep.brief: 'Brief & audience',
    EditorStep.media: 'Images & samples',
    EditorStep.review: 'Review & publish',
  };

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CampaignEditorCubit, CampaignEditorState>(
      listenWhen: (p, c) => p.tick != c.tick || p.published != c.published,
      listener: (context, state) {
        if (state.published) {
          AppSnackbar.success(context, 'Campaign published');
          Navigator.of(context).pop(true);
        } else if (state.errorMessage != null) {
          if ({'PROPOSAL_QUOTA_EXCEEDED', 'PRO_FEATURE_LOCKED'}.contains(state.errorCode) ||
              state.errorMessage!.toLowerCase().contains('upgrade')) {
            showUpgradePrompt(context, state.errorMessage!);
          } else {
            AppSnackbar.error(context, state.errorMessage!);
          }
        }
      },
      builder: (context, state) {
        final cubit = context.read<CampaignEditorCubit>();
        final stepIndex = state.step.index;
        return PopScope(
          canPop: stepIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.back();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(state.campaign == null ? 'New campaign' : 'Edit campaign'),
              leading: IconButton(
                tooltip: stepIndex == 0 ? 'Close' : 'Back',
                icon: Icon(stepIndex == 0 ? AppIcons.close : AppIcons.back),
                onPressed: () => stepIndex == 0 ? Navigator.of(context).maybePop() : cubit.back(),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(_titles[state.step]!, style: context.text.titleSmall)),
                          Text('Step ${stepIndex + 1} of 5', style: context.text.bodySmall),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: (stepIndex + 1) / 5),
                        duration: AppDurations.normal,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 4,
                            backgroundColor: context.palette.surfaceMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: state.isLoading
                ? const LoadingView()
                : AnimatedSwitcher(
              duration: AppDurations.normal,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(state.step),
                child: switch (state.step) {
                  EditorStep.basics => const _BasicsStep(),
                  EditorStep.budget => const _BudgetStep(),
                  EditorStep.brief => const _BriefStep(),
                  EditorStep.media => const _MediaStep(),
                  EditorStep.review => const _ReviewStep(),
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Scrollable step body with its primary button pinned at the bottom.
class _StepFrame extends StatelessWidget {
  const _StepFrame({required this.children, required this.buttonLabel, required this.onContinue, this.formKey});

  final List<Widget> children;
  final String buttonLabel;
  final VoidCallback onContinue;
  final GlobalKey<FormState>? formKey;

  @override
  Widget build(BuildContext context) {
    final saving = context.select<CampaignEditorCubit, bool>((c) => c.state.isSaving);
    final palette = context.palette;
    return Column(
      children: [
        Expanded(
          child: Form(
            key: formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xl),
              children: children,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.sm),
              child: AppButton(label: buttonLabel, isLoading: saving, onPressed: saving ? null : onContinue),
            ),
          ),
        ),
      ],
    );
  }
}

const _gap = SizedBox(height: AppSpacing.lg);

// --- Step 1 -------------------------------------------------------------------

class _BasicsStep extends StatefulWidget {
  const _BasicsStep();

  @override
  State<_BasicsStep> createState() => _BasicsStepState();
}

class _BasicsStepState extends State<_BasicsStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _location;
  late CampaignType _type;
  late LocationType _locationType;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final c = context.read<CampaignEditorCubit>().state.campaign;
    _title = TextEditingController(text: c?.title ?? '');
    _location = TextEditingController(text: c?.locationValue ?? '');
    _type = c?.type ?? CampaignType.paid;
    _locationType = c?.locationType ?? LocationType.panIndia;
    _categoryId = c?.category?.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  void _continue() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<CampaignEditorCubit>().saveBasics(
      title: _title.text.trim(),
      type: _type,
      locationType: _locationType,
      locationValue: _locationType == LocationType.panIndia ? '' : _location.text.trim(),
      categoryId: _categoryId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    return _StepFrame(
      formKey: _formKey,
      buttonLabel: 'Continue',
      onContinue: _continue,
      children: [
        AppTextField(
          label: 'Campaign name',
          hint: 'e.g. Diwali skincare launch',
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter at least 3 characters' : null,
        ),
        _gap,
        const FieldLabel('Campaign type'),
        _TypeSelector(value: _type, onChanged: (t) => setState(() => _type = t)),
        _gap,
        AppDropdown<String>(
          label: 'Category',
          hint: 'Choose a category',
          items: categories.map((c) => c.id).toList(),
          value: _categoryId,
          labelOf: (id) => categories.firstWhere((c) => c.id == id).label,
          onChanged: (id) => setState(() => _categoryId = id),
          validator: (v) => v == null ? 'Choose a category' : null,
        ),
        _gap,
        const FieldLabel('Where should creators be?'),
        ChoicePills<LocationType>(
          options: LocationType.values,
          selected: {_locationType},
          labelOf: (t) => t.label,
          onChanged: (t) => setState(() => _locationType = t),
        ),
        AnimatedSize(
          duration: AppDurations.normal,
          child: _locationType == LocationType.panIndia
              ? const SizedBox(width: double.infinity)
              : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: AppTextField(
              label: _locationType == LocationType.city ? 'City' : 'State',
              hint: _locationType == LocationType.city ? 'e.g. Indore' : 'e.g. Madhya Pradesh',
              controller: _location,
              prefixIcon: AppIcons.mapPin,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter a location' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final CampaignType value;
  final ValueChanged<CampaignType> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(CampaignType type, IconData icon, String description) {
      final selected = value == type;
      final palette = context.palette;
      return Expanded(
        child: AnimatedContainer(
          duration: AppDurations.normal,
          decoration: BoxDecoration(
            color: selected ? palette.primarySoft : palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? AppColors.primary : palette.border, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(type);
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: selected ? AppColors.primary : palette.textSecondary),
                  const SizedBox(height: AppSpacing.xs),
                  Text(type.label, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(description, style: context.text.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(CampaignType.paid, AppIcons.wallet, 'Pay creators through escrow'),
        const SizedBox(width: AppSpacing.sm),
        option(CampaignType.barter, AppIcons.gift, 'Send products instead of money'),
      ],
    );
  }
}

// --- Step 2 -------------------------------------------------------------------

class _BudgetStep extends StatefulWidget {
  const _BudgetStep();

  @override
  State<_BudgetStep> createState() => _BudgetStepState();
}

class _BudgetStepState extends State<_BudgetStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cost;
  late int _creators;
  late int _milestones;

  @override
  void initState() {
    super.initState();
    final c = context.read<CampaignEditorCubit>().state.campaign!;
    _cost = TextEditingController(text: c.costPerInfluencer > 0 ? Fmt.paiseToRupeesInput(c.costPerInfluencer) : '');
    _creators = c.maxInfluencers;
    _milestones = c.milestoneCount;
  }

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  void _continue(Campaign campaign) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!campaign.isPaid && campaign.products.isEmpty) {
      AppSnackbar.error(context, 'Add at least one product for a barter campaign');
      return;
    }
    context.read<CampaignEditorCubit>().saveBudget(
      costPerInfluencer: campaign.isPaid ? (Fmt.rupeesToPaise(_cost.text) ?? 0) : 0,
      maxInfluencers: _creators,
      milestoneCount: _milestones,
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.select<CampaignEditorCubit, Campaign>((c) => c.state.campaign!);
    final cost = Fmt.rupeesToPaise(_cost.text) ?? 0;

    return _StepFrame(
      formKey: _formKey,
      buttonLabel: 'Continue',
      onContinue: () => _continue(campaign),
      children: [
        if (campaign.isPaid) ...[
          AppTextField(
            label: 'Pay per creator',
            hint: 'e.g. 5000',
            controller: _cost,
            prefixIcon: AppIcons.rupee,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() {}),
            validator: (v) => (Fmt.rupeesToPaise(v ?? '') ?? 0) < 100 ? 'Enter at least ₹1' : null,
          ),
          _gap,
        ],
        CounterField(label: 'Creators needed', value: _creators, min: 1, max: 50, onChanged: (v) => setState(() => _creators = v)),
        if (campaign.isPaid) ...[
          const SizedBox(height: AppSpacing.sm),
          CounterField(label: 'Payment milestones', value: _milestones, min: 1, max: 4, onChanged: (v) => setState(() => _milestones = v)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each creator’s pay is split into $_milestones equal part${_milestones == 1 ? '' : 's'}. '
                'You fund one at a time into escrow and release it when you approve the work.',
            style: context.text.bodySmall,
          ),
          _gap,
          AppCard(
            color: context.palette.primarySoft,
            borderColor: Colors.transparent,
            child: KeyValueRow(label: 'Estimated total budget', value: Fmt.money(cost * _creators), emphasize: true),
          ),
        ],
        _gap,
        SectionHeader(
          title: campaign.isPaid ? 'Free products (optional)' : 'Products for creators',
          actionLabel: 'Add product',
          onAction: () => showAppSheet<void>(
            context,
            builder: (_) => BlocProvider.value(value: context.read<CampaignEditorCubit>(), child: const _ProductSheet()),
          ),
        ),
        if (campaign.products.isEmpty)
          Text(
            campaign.isPaid ? 'Add products you’ll send along with the payment.' : 'Add what each creator receives.',
            style: context.text.bodyMedium,
          )
        else
          for (final product in campaign.products)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    AppNetworkImage(url: product.imageUrl, width: 48, height: 48, radius: AppRadius.sm, placeholderIcon: AppIcons.gift),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name, style: context.text.titleSmall),
                          Text('Qty ${product.quantity} · ${Fmt.money(product.price)}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(AppIcons.trash, size: 20),
                      onPressed: () => context.read<CampaignEditorCubit>().removeProduct(product.id),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _ProductSheet extends StatefulWidget {
  const _ProductSheet();

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  int _quantity = 1;
  PickedMedia? _image;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<CampaignEditorCubit>().addProduct(
      name: _name.text.trim(),
      price: Fmt.rupeesToPaise(_price.text) ?? 0,
      quantity: _quantity,
      description: _description.text.trim(),
      image: _image,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.select<CampaignEditorCubit, bool>((c) => c.state.isSaving);
    final palette = context.palette;
    return SheetBody(
      title: 'Add product',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () async {
                final image = await sl<MediaPicker>().image();
                if (image != null) setState(() => _image = image);
              },
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: palette.border),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_image == null ? AppIcons.image : AppIcons.checkCircle, color: _image == null ? palette.textSecondary : AppColors.success),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(child: Text(_image?.name ?? 'Add a product photo (optional)', style: context.text.labelMedium, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Product name',
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter the product name' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Value per unit',
              hint: 'e.g. 999',
              controller: _price,
              prefixIcon: AppIcons.rupee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              validator: (v) => Fmt.rupeesToPaise(v ?? '') == null ? 'Enter the product value' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            CounterField(label: 'Quantity per creator', value: _quantity, min: 1, max: 20, onChanged: (v) => setState(() => _quantity = v)),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _description, minLines: 2, maxLines: 4),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Add product', isLoading: saving, onPressed: saving ? null : _save),
          ],
        ),
      ),
    );
  }
}

// --- Step 3 -------------------------------------------------------------------

class _BriefStep extends StatefulWidget {
  const _BriefStep();

  @override
  State<_BriefStep> createState() => _BriefStepState();
}

class _BriefStepState extends State<_BriefStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _requirement;
  late final TextEditingController _duration;
  late final TextEditingController _minFollowers;
  late Deliverables _deliverables;
  late Set<String> _gender;
  late RangeValues _age;
  late List<String> _categories;
  late List<String> _dos;
  late List<String> _donts;

  @override
  void initState() {
    super.initState();
    final c = context.read<CampaignEditorCubit>().state.campaign!;
    _description = TextEditingController(text: c.description);
    _requirement = TextEditingController(text: c.creatorRequirement);
    _duration = TextEditingController(text: c.durationLabel);
    _minFollowers = TextEditingController(text: c.minFollowers?.toString() ?? '');
    _deliverables = c.deliverables;
    _gender = c.genderTarget.toSet();
    _age = RangeValues(c.ageMin.toDouble(), c.ageMax.toDouble());
    _categories = c.influencerCategories;
    _dos = c.dos;
    _donts = c.donts;
  }

  @override
  void dispose() {
    _description.dispose();
    _requirement.dispose();
    _duration.dispose();
    _minFollowers.dispose();
    super.dispose();
  }

  void _continue() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final minFollowers = int.tryParse(_minFollowers.text.trim());
    context.read<CampaignEditorCubit>().saveBrief({
      'description': _description.text.trim(),
      'creatorRequirement': _requirement.text.trim(),
      'durationLabel': _duration.text.trim(),
      'deliverables': _deliverables.toJson(),
      'genderTarget': _gender.toList(),
      'ageRange': {'min': _age.start.round(), 'max': _age.end.round()},
      'influencerCategories': _categories,
      'dos': _dos,
      'donts': _donts,
      if (minFollowers != null) 'minFollowers': minFollowers,
    });
  }

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      formKey: _formKey,
      buttonLabel: 'Continue',
      onContinue: _continue,
      children: [
        AppTextField(
          label: 'Describe the campaign',
          hint: 'What you’re promoting, the message and what success looks like',
          controller: _description,
          minLines: 4,
          maxLines: 10,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) => (v?.trim().length ?? 0) < 10 ? 'Write at least 10 characters' : null,
        ),
        _gap,
        const FieldLabel('Deliverables per creator'),
        CounterField(label: 'Reels', value: _deliverables.reel, max: 20, onChanged: (v) => setState(() => _deliverables = Deliverables(reel: v, post: _deliverables.post, story: _deliverables.story))),
        const SizedBox(height: AppSpacing.xs),
        CounterField(label: 'Posts', value: _deliverables.post, max: 20, onChanged: (v) => setState(() => _deliverables = Deliverables(reel: _deliverables.reel, post: v, story: _deliverables.story))),
        const SizedBox(height: AppSpacing.xs),
        CounterField(label: 'Stories', value: _deliverables.story, max: 20, onChanged: (v) => setState(() => _deliverables = Deliverables(reel: _deliverables.reel, post: _deliverables.post, story: v))),
        _gap,
        AppTextField(
          label: 'Who you’re looking for (optional)',
          hint: 'e.g. Food creators in Indore with an engaged local audience',
          controller: _requirement,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        _gap,
        AppTextField(
          label: 'Minimum followers (optional)',
          hint: 'e.g. 5000',
          controller: _minFollowers,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _gap,
        AppTextField(label: 'Duration (optional)', hint: 'e.g. 2 weeks', controller: _duration, prefixIcon: AppIcons.clock),
        _gap,
        TagInput(label: 'Creator categories (optional)', hint: 'e.g. Food, Lifestyle', values: _categories, onChanged: (v) => setState(() => _categories = v)),
        _gap,
        const FieldLabel('Audience gender (optional)'),
        ChoicePills<String>(
          options: const ['female', 'male', 'other'],
          selected: _gender,
          labelOf: Fmt.titleCase,
          onChanged: (g) => setState(() => _gender.contains(g) ? _gender.remove(g) : _gender.add(g)),
        ),
        _gap,
        FieldLabel('Audience age', trailing: Text('${_age.start.round()}–${_age.end.round()}', style: context.text.labelMedium)),
        RangeSlider(
          values: _age,
          min: 13,
          max: 65,
          divisions: 52,
          onChanged: (v) => setState(() => _age = v),
        ),
        _gap,
        TagInput(label: 'Do’s (optional)', hint: 'e.g. Show the product in daylight', values: _dos, onChanged: (v) => setState(() => _dos = v)),
        _gap,
        TagInput(label: 'Don’ts (optional)', hint: 'e.g. Don’t mention competitors', values: _donts, onChanged: (v) => setState(() => _donts = v)),
      ],
    );
  }
}

// --- Step 4 -------------------------------------------------------------------

class _MediaStep extends StatefulWidget {
  const _MediaStep();

  @override
  State<_MediaStep> createState() => _MediaStepState();
}

class _MediaStepState extends State<_MediaStep> {
  static const _maxLinks = 10;
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _links;

  @override
  void initState() {
    super.initState();
    final existing = context.read<CampaignEditorCubit>().state.campaign!.sampleMedia;
    _links = [for (final url in existing) TextEditingController(text: url)];
    if (_links.isEmpty) _links.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _links) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _validateLink(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    final uri = Uri.tryParse(input);
    final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.contains('.');
    return ok ? null : 'Enter a full link starting with https://';
  }

  void _continue(Campaign campaign) {
    if (campaign.campaignImageUrl == null) {
      AppSnackbar.error(context, 'Add a cover image — it’s required to publish');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final links = _links.map((c) => c.text.trim()).where((l) => l.isNotEmpty).toSet().toList();
    context.read<CampaignEditorCubit>().saveSampleLinks(links);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CampaignEditorCubit>();
    final campaign = context.select<CampaignEditorCubit, Campaign>((c) => c.state.campaign!);
    final saving = context.select<CampaignEditorCubit, bool>((c) => c.state.isSaving);
    final palette = context.palette;

    return _StepFrame(
      formKey: _formKey,
      buttonLabel: 'Continue to review',
      onContinue: () => _continue(campaign),
      children: [
        const FieldLabel('Cover image (required)'),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: saving
              ? null
              : () async {
            final image = await sl<MediaPicker>().image();
            if (image != null) await cubit.uploadMedia(cover: image);
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppNetworkImage(url: campaign.campaignImageUrl, radius: AppRadius.lg),
                if (campaign.campaignImageUrl == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.upload, color: palette.textSecondary),
                        const SizedBox(height: AppSpacing.xs),
                        Text('Upload a cover image', style: context.text.labelMedium),
                      ],
                    ),
                  )
                else
                  Positioned(
                    right: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(AppIcons.camera, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('Change', style: context.text.labelSmall?.copyWith(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                if (saving) const ColoredBox(color: Color(0x33000000), child: LoadingView()),
              ],
            ),
          ),
        ),
        _gap,
        const FieldLabel('Reference links (optional)'),
        Text(
          'Paste links to posts or videos that show the look and feel you want — Instagram, YouTube, Drive and so on. Up to $_maxLinks.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (index, controller) in _links.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    validator: _validateLink,
                    decoration: InputDecoration(
                      hintText: 'https://instagram.com/p/…',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 14, right: 10),
                        child: Icon(AppIcons.link, size: 20),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ),
                if (_links.length > 1) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton(
                      tooltip: 'Remove link',
                      icon: Icon(AppIcons.trash, size: 20, color: palette.textSecondary),
                      onPressed: () => setState(() => _links.removeAt(index).dispose()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_links.length < _maxLinks)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _links.add(TextEditingController())),
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('Add another link'),
            ),
          ),
      ],
    );
  }
}

// --- Step 5 -------------------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CampaignEditorCubit>();
    final campaign = context.select<CampaignEditorCubit, Campaign>((c) => c.state.campaign!);
    return _StepFrame(
      buttonLabel: 'Publish campaign',
      onContinue: () {
        if (campaign.campaignImageUrl == null) {
          AppSnackbar.error(context, 'Add a cover image before publishing');
          cubit.goTo(EditorStep.media);
          return;
        }
        cubit.publish();
      },
      children: [
        CampaignHeader(campaign: campaign),
        const SizedBox(height: AppSpacing.md),
        CampaignBrief(campaign: campaign),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(AppIcons.info, size: 16, color: context.palette.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Publishing uses one campaign from your plan. You pay only when you hire a creator and fund a milestone.',
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}