import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/models/common_models.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

/// Edits the signed-in user's creator, brand or agency profile. An
/// unverified profile can be submitted for admin review from here.
class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const Scaffold();
    final user = auth.user;
    final repo = sl<ProfileRepository>();

    final Widget form = switch (user.role) {
      UserRole.brand => BlocProvider(create: (_) => LoadCubit<BrandProfile>(repo.brand), child: _BrandForm(user: user)),
      UserRole.agency => BlocProvider(create: (_) => LoadCubit<AgencyProfile>(repo.agency), child: _AgencyForm(user: user)),
      _ => MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => LoadCubit<CreatorProfile>(repo.creator)),
            BlocProvider(create: (_) => LoadCubit<List<Category>>(sl<CategoriesRepository>().getAll)),
          ],
          child: _CreatorForm(user: user),
        ),
    };
    return ActionScope(child: Scaffold(appBar: AppBar(title: const Text('Edit profile')), body: form));
  }
}

/// Saves the profile, then refreshes the session so a status change
/// (pending review) is picked up by the router.
Future<void> _save(BuildContext context, Future<void> Function() task, {required bool submit}) async {
  final ok = await context.read<ActionCubit>().run(
        'save',
        () async {
          await task();
          if (submit) await sl<ProfileRepository>().completeOnboarding();
          return true;
        },
        success: submit ? 'Submitted for review' : 'Profile saved',
      );
  if (ok != null && context.mounted) {
    context.read<AuthBloc>().add(const AuthRefreshRequested());
    if (!submit) Navigator.of(context).maybePop();
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.user, this.isLogo = false});

  final AppUser user;
  final bool isLogo;

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<ActionCubit>().state;
    return Center(
      child: Stack(
        children: [
          UserAvatar(initials: user.initials, imageUrl: user.avatarUrl, size: 92),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: actions.isBusy
                    ? null
                    : () async {
                        final image = await sl<MediaPicker>().image();
                        if (image == null || !context.mounted) return;
                        final repo = sl<ProfileRepository>();
                        final ok = await context.read<ActionCubit>().run(
                              'avatar',
                              () => isLogo ? repo.uploadBrandLogo(image) : repo.uploadAvatar(image),
                              success: isLogo ? 'Logo updated' : 'Photo updated',
                            );
                        if (ok != null && context.mounted) context.read<AuthBloc>().add(const AuthRefreshRequested());
                      },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: actions.isBusyWith('avatar')
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.camera, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitNotice extends StatelessWidget {
  const _SubmitNotice({required this.status, this.reason});

  final VerificationStatus status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    if (status == VerificationStatus.verified) return const SizedBox.shrink();
    final rejected = status == VerificationStatus.rejected;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        color: (rejected ? AppColors.error : AppColors.info).withValues(alpha: 0.08),
        borderColor: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(rejected ? AppIcons.warning : AppIcons.info, size: 20, color: rejected ? AppColors.error : AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                rejected
                    ? 'Your profile wasn’t approved${reason == null || reason!.isEmpty ? '' : ': $reason'}. Update it and submit again.'
                    : 'Complete your profile and submit it for review. Verified profiles get full access to Fanitt.',
                style: context.text.bodyMedium?.copyWith(color: context.palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onSave, required this.canSubmit});

  final void Function({required bool submit}) onSave;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusyWith('save');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        if (canSubmit) ...[
          AppButton(label: 'Save & submit for review', isLoading: busy, onPressed: busy ? null : () => onSave(submit: true)),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(label: 'Save draft', onPressed: busy ? null : () => onSave(submit: false)),
        ] else
          AppButton(label: 'Save changes', isLoading: busy, onPressed: busy ? null : () => onSave(submit: false)),
      ],
    );
  }
}

const _gap = SizedBox(height: AppSpacing.lg);
const _padding = EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl);

// --- Creator -------------------------------------------------------------------

class _CreatorForm extends StatelessWidget {
  const _CreatorForm({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<CreatorProfile>>();
    return AsyncView<CreatorProfile>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (profile) => _CreatorFields(user: user, profile: profile),
    );
  }
}

class _CreatorFields extends StatefulWidget {
  const _CreatorFields({required this.user, required this.profile});

  final AppUser user;
  final CreatorProfile profile;

  @override
  State<_CreatorFields> createState() => _CreatorFieldsState();
}

class _CreatorFieldsState extends State<_CreatorFields> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);
  late final _title = TextEditingController(text: widget.profile.title);
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _location = TextEditingController(text: widget.profile.location);
  late final _portfolio = TextEditingController(text: widget.profile.portfolioLink);
  late final _years = TextEditingController(text: widget.profile.yearsOfExperience?.toString() ?? '');
  late final _instagram = TextEditingController(text: widget.profile.socials.get('instagram'));
  late final _youtube = TextEditingController(text: widget.profile.socials.get('youtube'));
  late final _linkedin = TextEditingController(text: widget.profile.socials.get('linkedin'));
  late List<String> _skills = widget.profile.skills;
  late List<String> _languages = widget.profile.languages;
  late String? _categoryId = widget.profile.category?.id;
  late bool _available = widget.profile.isAvailableForWork;

  @override
  void dispose() {
    for (final c in [_name, _title, _bio, _location, _portfolio, _years, _instagram, _youtube, _linkedin]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave({required bool submit}) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = sl<ProfileRepository>();
    _save(context, () async {
      if (_name.text.trim() != widget.user.name) await repo.updateAccount(name: _name.text.trim());
      await repo.updateCreator({
        'title': _title.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'portfolioLink': _portfolio.text.trim(),
        'skills': _skills,
        'languages': _languages,
        'isAvailableForWork': _available,
        if (_categoryId != null) 'category': _categoryId,
        if (int.tryParse(_years.text.trim()) != null) 'yearsOfExperience': int.parse(_years.text.trim()),
        'socials': {
          'instagram': _instagram.text.trim(),
          'youtube': _youtube.text.trim(),
          'linkedin': _linkedin.text.trim(),
        },
        if (submit) 'submitForApproval': true,
      });
    }, submit: submit);
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<LoadCubit<List<Category>>>().state.data ?? const <Category>[];
    final status = widget.profile.verificationStatus;
    final canSubmit = status == VerificationStatus.unverified || status == VerificationStatus.rejected;

    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status),
          _AvatarPicker(user: context.watch<AuthBloc>().state is AuthAuthenticated ? (context.watch<AuthBloc>().state as AuthAuthenticated).user : widget.user),
          _gap,
          AppTextField(label: 'Full name', controller: _name, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Name')),
          _gap,
          AppTextField(label: 'Headline', hint: 'e.g. Food & travel creator from Indore', controller: _title, maxLength: 80, validator: Validators.requiredText('Headline')),
          const SizedBox(height: AppSpacing.xs),
          AppDropdown<String>(
            label: 'Category',
            items: categories.map((c) => c.id).toList(),
            value: _categoryId,
            labelOf: (id) => categories.firstWhere((c) => c.id == id).label,
            onChanged: (id) => setState(() => _categoryId = id),
            validator: (v) => v == null ? 'Choose a category' : null,
          ),
          _gap,
          AppTextField(
            label: 'Bio',
            hint: 'Your content, audience and the brands you’ve worked with',
            controller: _bio,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v?.trim().length ?? 0) < 20 ? 'Write at least 20 characters' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'City', controller: _location, prefixIcon: AppIcons.mapPin, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('City')),
          _gap,
          AppTextField(
            label: 'Years of experience (optional)',
            controller: _years,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          ),
          _gap,
          TagInput(label: 'Skills', hint: 'e.g. Reels, Food photography', values: _skills, onChanged: (v) => setState(() => _skills = v)),
          _gap,
          TagInput(label: 'Languages', hint: 'e.g. Hindi', values: _languages, onChanged: (v) => setState(() => _languages = v)),
          _gap,
          const FieldLabel('Social links'),
          AppTextField(label: 'Instagram', hint: 'https://instagram.com/…', controller: _instagram, prefixIcon: AppIcons.instagram, keyboardType: TextInputType.url),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'YouTube', hint: 'https://youtube.com/…', controller: _youtube, prefixIcon: AppIcons.youtube, keyboardType: TextInputType.url),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'LinkedIn', hint: 'https://linkedin.com/in/…', controller: _linkedin, prefixIcon: AppIcons.linkedin, keyboardType: TextInputType.url),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Portfolio (optional)', hint: 'https://', controller: _portfolio, prefixIcon: AppIcons.link, keyboardType: TextInputType.url),
          _gap,
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _available,
            activeTrackColor: AppColors.primary,
            onChanged: (v) => setState(() => _available = v),
            title: Text('Available for work', style: context.text.titleSmall),
            subtitle: Text('Brands see that you’re taking new campaigns', style: context.text.bodySmall),
          ),
          _SaveBar(onSave: _onSave, canSubmit: canSubmit),
        ],
      ),
    );
  }
}

// --- Brand ---------------------------------------------------------------------

class _BrandForm extends StatelessWidget {
  const _BrandForm({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<BrandProfile>>();
    return AsyncView<BrandProfile>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (profile) => _BrandFields(user: user, profile: profile),
    );
  }
}

class _BrandFields extends StatefulWidget {
  const _BrandFields({required this.user, required this.profile});

  final AppUser user;
  final BrandProfile profile;

  @override
  State<_BrandFields> createState() => _BrandFieldsState();
}

class _BrandFieldsState extends State<_BrandFields> {
  final _formKey = GlobalKey<FormState>();
  late final _company = TextEditingController(text: widget.profile.companyName);
  late final _tagline = TextEditingController(text: widget.profile.tagline);
  late final _industry = TextEditingController(text: widget.profile.industry);
  late final _about = TextEditingController(text: widget.profile.about);
  late final _location = TextEditingController(text: widget.profile.location);
  late final _website = TextEditingController(text: widget.profile.website);
  late final _founded = TextEditingController(text: widget.profile.foundedYear?.toString() ?? '');
  late final _audience = TextEditingController(text: widget.profile.targetAudience);
  late final _designation = TextEditingController(text: widget.profile.contactDesignation);
  late final _instagram = TextEditingController(text: widget.profile.socials.get('instagram'));
  late String _size = widget.profile.companySize;
  late List<String> _offers = widget.profile.whatWeOffer;

  static const _sizes = ['1-10', '11-50', '51-200', '201-500', '500+'];

  @override
  void dispose() {
    for (final c in [_company, _tagline, _industry, _about, _location, _website, _founded, _audience, _designation, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave({required bool submit}) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _save(context, () async {
      await sl<ProfileRepository>().updateBrand({
        'companyName': _company.text.trim(),
        'tagline': _tagline.text.trim(),
        'industry': _industry.text.trim(),
        'about': _about.text.trim(),
        'location': _location.text.trim(),
        'website': _website.text.trim(),
        'targetAudience': _audience.text.trim(),
        'contactDesignation': _designation.text.trim(),
        'companySize': _size,
        'whatWeOffer': _offers,
        if (int.tryParse(_founded.text.trim()) != null) 'foundedYear': int.parse(_founded.text.trim()),
        'socials': {'instagram': _instagram.text.trim()},
        if (submit) 'submitForApproval': true,
      });
    }, submit: submit);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.profile.verificationStatus;
    final auth = context.watch<AuthBloc>().state;
    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status),
          _AvatarPicker(user: auth is AuthAuthenticated ? auth.user : widget.user, isLogo: true),
          _gap,
          AppTextField(label: 'Brand name', controller: _company, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Brand name')),
          _gap,
          AppTextField(label: 'Tagline', hint: 'One line about your brand', controller: _tagline, maxLength: 100),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Industry', hint: 'e.g. Food & beverage', controller: _industry, validator: Validators.requiredText('Industry')),
          _gap,
          AppTextField(
            label: 'About',
            controller: _about,
            minLines: 3,
            maxLines: 8,
            maxLength: 1500,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v?.trim().length ?? 0) < 20 ? 'Write at least 20 characters' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Headquarters', controller: _location, prefixIcon: AppIcons.mapPin, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Location')),
          _gap,
          AppTextField(label: 'Website (optional)', hint: 'https://', controller: _website, prefixIcon: AppIcons.globe, keyboardType: TextInputType.url),
          _gap,
          AppTextField(label: 'Instagram (optional)', hint: 'https://instagram.com/…', controller: _instagram, prefixIcon: AppIcons.instagram, keyboardType: TextInputType.url),
          _gap,
          AppTextField(
            label: 'Founded (optional)',
            hint: 'e.g. 2019',
            controller: _founded,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          ),
          _gap,
          const FieldLabel('Team size'),
          ChoicePills<String>(options: _sizes, selected: {_size}, labelOf: (s) => s, onChanged: (s) => setState(() => _size = s)),
          _gap,
          AppTextField(label: 'Target audience (optional)', controller: _audience, minLines: 2, maxLines: 4),
          _gap,
          AppTextField(label: 'Your designation (optional)', hint: 'e.g. Marketing manager', controller: _designation),
          _gap,
          TagInput(label: 'What you offer creators (optional)', hint: 'e.g. Free products', values: _offers, onChanged: (v) => setState(() => _offers = v)),
          _SaveBar(onSave: _onSave, canSubmit: status == VerificationStatus.unverified || status == VerificationStatus.rejected),
        ],
      ),
    );
  }
}

// --- Agency --------------------------------------------------------------------

class _AgencyForm extends StatelessWidget {
  const _AgencyForm({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<AgencyProfile>>();
    return AsyncView<AgencyProfile>(
      state: cubit.state,
      onRetry: cubit.load,
      builder: (profile) => _AgencyFields(user: user, profile: profile),
    );
  }
}

class _AgencyFields extends StatefulWidget {
  const _AgencyFields({required this.user, required this.profile});

  final AppUser user;
  final AgencyProfile profile;

  @override
  State<_AgencyFields> createState() => _AgencyFieldsState();
}

class _AgencyFieldsState extends State<_AgencyFields> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.agencyName);
  late final _owner = TextEditingController(text: widget.profile.ownerName);
  late final _mobile = TextEditingController(text: widget.profile.mobile);
  late final _city = TextEditingController(text: widget.profile.city);
  late final _state = TextEditingController(text: widget.profile.state);
  late final _gst = TextEditingController(text: widget.profile.gstNumber);
  late final _years = TextEditingController(text: widget.profile.yearsInBusiness?.toString() ?? '');
  late final _specialization = TextEditingController(text: widget.profile.specialization);
  late String _team = widget.profile.teamSize;
  late String? _documentUrl = widget.profile.documentUrl;

  static const _teams = ['1-5', '6-20', '21-50', '50+'];

  @override
  void dispose() {
    for (final c in [_name, _owner, _mobile, _city, _state, _gst, _years, _specialization]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave({required bool submit}) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (submit && _documentUrl == null) {
      context.read<ActionCubit>().run<void>(
        'save',
        () async => throw const ApiException('Upload your ID or business proof before submitting.'),
      );
      return;
    }
    _save(context, () async {
      await sl<ProfileRepository>().updateAgency({
        'agencyName': _name.text.trim(),
        'ownerName': _owner.text.trim(),
        'mobile': Validators.normalizeMobile(_mobile.text),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'gstNumber': _gst.text.trim().toUpperCase(),
        'teamSize': _team,
        'specialization': _specialization.text.trim(),
        if (int.tryParse(_years.text.trim()) != null) 'yearsInBusiness': int.parse(_years.text.trim()),
        if (submit) 'submitForApproval': true,
      });
    }, submit: submit);
  }

  Future<void> _uploadDocument() async {
    final image = await sl<MediaPicker>().image();
    if (image == null || !mounted) return;
    final url = await context.read<ActionCubit>().run('doc', () => sl<ProfileRepository>().uploadAgencyDocument(image), success: 'Document uploaded');
    if (url != null && mounted) setState(() => _documentUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.profile.verificationStatus;
    final actions = context.watch<ActionCubit>().state;
    final palette = context.palette;
    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status, reason: widget.profile.rejectionReason),
          AppTextField(label: 'Agency name', controller: _name, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Agency name')),
          _gap,
          AppTextField(label: 'Owner name', controller: _owner, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Owner name')),
          _gap,
          AppTextField(
            label: 'Mobile number',
            controller: _mobile,
            prefixIcon: AppIcons.phone,
            keyboardType: TextInputType.phone,
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter a mobile number' : Validators.optionalMobile(v),
          ),
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('City'))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: AppTextField(label: 'State', controller: _state, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('State'))),
            ],
          ),
          _gap,
          AppTextField(label: 'GST number (optional)', controller: _gst, textCapitalization: TextCapitalization.characters),
          _gap,
          const FieldLabel('Team size'),
          ChoicePills<String>(options: _teams, selected: {_team}, labelOf: (s) => s, onChanged: (s) => setState(() => _team = s)),
          _gap,
          AppTextField(
            label: 'Years in business (optional)',
            controller: _years,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          ),
          _gap,
          AppTextField(label: 'Specialization (optional)', hint: 'e.g. Food & lifestyle creators', controller: _specialization),
          _gap,
          const FieldLabel('ID or business proof'),
          AppCard(
            onTap: actions.isBusy ? null : _uploadDocument,
            child: Row(
              children: [
                Icon(_documentUrl == null ? AppIcons.upload : AppIcons.checkCircle, color: _documentUrl == null ? palette.textSecondary : AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _documentUrl == null ? 'Upload a photo of your ID or GST certificate' : 'Document uploaded — tap to replace',
                    style: context.text.titleSmall,
                  ),
                ),
                if (actions.isBusyWith('doc')) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          _SaveBar(onSave: _onSave, canSubmit: status == VerificationStatus.unverified || status == VerificationStatus.rejected),
        ],
      ),
    );
  }
}
