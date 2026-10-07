import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/enums/user_role.dart';
import '../../../core/models/common_models.dart';
import '../../../core/services/media_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_controls.dart';
import '../../../core/widgets/image_upload_box.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../common/data/categories_repository.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';
import 'widgets/profile_fields.dart';

// Required fields match the website's Edit Profile pages (marked with *):
//   Creator: photo, name, phone, headline, category, bio, city, response
//            time, languages, skills, Instagram.
//   Brand:   logo, your name, phone, brand name, tagline, industry, about,
//            headquarters, founded year, team size, what you offer, Instagram.
//   Agency:  your name, agency name, owner, mobile, city, state, GST, ID proof.
//   Fan:     name.

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
      UserRole.fan => _FanForm(user: user),
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

/// Runs the form check; shows one clear message if something's missing.
bool _check(BuildContext context, GlobalKey<FormState> key, {bool extraOk = true}) {
  final ok = (key.currentState?.validate() ?? false) && extraOk;
  if (!ok) {
    HapticFeedback.mediumImpact();
    AppSnackbar.error(context, 'Please fill all fields marked *');
  }
  return ok;
}

AppUser _currentUser(BuildContext context, AppUser fallback) {
  final auth = context.watch<AuthBloc>().state;
  return auth is AuthAuthenticated ? auth.user : fallback;
}

// --- shared validators ----------------------------------------------------------

String? Function(List<String>) _requiredTags(String what) => (values) => values.isEmpty ? 'Add at least one $what' : null;

final RegExp _instagramHandle = RegExp(r'^[A-Za-z0-9._]{1,30}$');

/// "@name", "name", "instagram.com/name" or a full link → the handle.
String _instagramHandleOf(String input) {
  var v = input.trim();
  v = v.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  if (v.toLowerCase().startsWith('instagram.com/')) v = v.substring('instagram.com/'.length);
  v = v.split(RegExp(r'[/?#]')).first;
  if (v.startsWith('@')) v = v.substring(1);
  return v;
}

String _instagramUrl(String input) {
  final handle = _instagramHandleOf(input);
  return handle.isEmpty ? '' : 'https://instagram.com/$handle';
}

String? _instagramRequired(String? v) {
  if ((v ?? '').trim().isEmpty) return 'Instagram profile is required';
  return _instagramHandle.hasMatch(_instagramHandleOf(v!)) ? null : 'Enter your Instagram username or profile link';
}

final RegExp _url = RegExp(r'^(https?://)?([\w-]+\.)+[a-zA-Z]{2,}([/?#].*)?$', caseSensitive: false);

String? _optionalUrl(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  return _url.hasMatch(t) ? null : 'Enter a valid link';
}

String _withScheme(String v) {
  final t = v.trim();
  if (t.isEmpty) return '';
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(t) ? t : 'https://$t';
}

// --- photo / logo -------------------------------------------------------------

/// Round slots for the brand logo and the fan photo.
const _logoSlot = ImageSlot(
  aspectRatio: 1,
  bestSize: '600 × 600 px',
  circle: true,
  label: 'Company logo *',
  tip: 'A square logo on a plain background, with no small text. It fills the circle on your brand card and profile.',
  shownOn: 'Preview — your logo across the app',
);

const _photoSlot = ImageSlot(
  aspectRatio: 1,
  bestSize: '600 × 600 px',
  circle: true,
  label: 'Profile photo',
  tip: 'A clear photo of your face with no text on it. It is shown in a circle.',
  shownOn: 'Preview — your photo across the app',
);

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.user, this.isLogo = false, this.imageUrl, this.onUploaded, this.errorText, this.creatorCard});

  final AppUser user;
  final bool isLogo;

  /// Shown instead of the account photo (brand logo).
  final String? imageUrl;
  final ValueChanged<String>? onUploaded;
  final String? errorText;

  /// Creators: draws the Home creator card over the photo.
  final Widget Function(Widget image)? creatorCard;

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<ActionCubit>().state;
    final url = isLogo ? imageUrl : (imageUrl ?? user.avatarUrl);
    final hasUrl = (url ?? '').isNotEmpty;

    Future<void> pick() async {
      final image = await sl<MediaPicker>().image();
      if (image == null || !context.mounted) return;
      final repo = sl<ProfileRepository>();
      final uploaded = await context.read<ActionCubit>().run(
        'avatar',
            () => isLogo ? repo.uploadBrandLogo(image) : repo.uploadAvatar(image),
        success: isLogo ? 'Logo updated' : 'Photo updated',
      );
      if (uploaded != null && context.mounted) {
        onUploaded?.call(uploaded);
        context.read<AuthBloc>().add(const AuthRefreshRequested());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (creatorCard != null)
          ImageUploadBox(
            slot: ImageSlot.creatorPhoto,
            url: url,
            enabled: !actions.isBusy,
            onPick: pick,
            errorText: errorText,
            previewBuilder: (context, image) => creatorCard!(image),
          )
        else
          ImageUploadBox(
            slot: isLogo ? _logoSlot : _photoSlot,
            url: url,
            width: 92,
            enabled: !actions.isBusy,
            onPick: pick,
            errorText: errorText,
          ),
        if (creatorCard != null && hasUrl) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UserAvatar(initials: user.initials, imageUrl: url, size: 40),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text('Also shown in a circle in chats, comments and lists', style: context.text.bodySmall)),
            ],
          ),
        ],
        if (actions.isBusyWith('avatar')) ...[
          const SizedBox(height: AppSpacing.sm),
          const LinearProgressIndicator(minHeight: 3, color: AppColors.primary),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

/// The Home creator card drawn over the photo — the upload preview.
class _CreatorCardPreview extends StatelessWidget {
  const _CreatorCardPreview({
    required this.image,
    required this.name,
    required this.subtitle,
    required this.followers,
    required this.available,
    required this.verified,
    required this.pro,
  });

  final Widget image;
  final String name;
  final String subtitle;
  final int followers;
  final bool available;
  final bool verified;
  final bool pro;

  static const _brandGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The upload box crops from the top, like the Home card.
        image,
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 132,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000), Color(0xF2000000)],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          top: 10,
          child: Row(
            children: [
              if (available)
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
              if (pro)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(6)),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name.isEmpty ? 'Your name' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: name.isEmpty ? Colors.white70 : Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const Icon(AppIcons.sealCheck, size: 14, color: Color(0xFF60A5FA)),
                  ],
                ],
              ),
              Text(subtitle.isEmpty ? 'Creator' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(AppIcons.users, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(Fmt.compact(followers), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 28,
                decoration: BoxDecoration(gradient: _brandGradient, borderRadius: BorderRadius.circular(999)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.plus, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Follow', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
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

/// "Fields marked * are required" line at the top of every form.
class _RequiredHint extends StatelessWidget {
  const _RequiredHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text.rich(
        TextSpan(
          text: 'Fields marked ',
          children: const [
            TextSpan(text: '*', style: TextStyle(color: Color(0xFFF4511E), fontWeight: FontWeight.w800)),
            TextSpan(text: ' are required'),
          ],
        ),
        style: context.text.bodySmall,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(title.toUpperCase(), style: context.text.labelSmall?.copyWith(color: context.palette.textSecondary, letterSpacing: 1)),
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

// --- Fan -------------------------------------------------------------------------

/// Fans only have a photo, name and phone.
class _FanForm extends StatefulWidget {
  const _FanForm({required this.user});

  final AppUser user;

  @override
  State<_FanForm> createState() => _FanFormState();
}

class _FanFormState extends State<_FanForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);
  late final PhoneValue _initialPhone = PhoneValue.parse(widget.user.phone);
  late final _phone = TextEditingController(text: _initialPhone.number);
  late CountryCode _country = _initialPhone.country;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser(context, widget.user);
    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const _RequiredHint(),
          UserAvatarPicker(user: user),
          _gap,
          AppTextField(
            label: 'Full name',
            isRequired: true,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter your name' : null,
          ),
          _gap,
          PhoneField(controller: _phone, country: _country, onCountryChanged: (c) => setState(() => _country = c), label: 'Phone (optional)'),
          _SaveBar(
            canSubmit: false,
            onSave: ({required submit}) {
              if (!_check(context, _formKey)) return;
              final phone = PhoneValue(_country, _phone.text.trim()).stored;
              _save(
                context,
                    () => sl<ProfileRepository>().updateAccount(name: _name.text.trim(), phone: phone.isEmpty ? null : phone),
                submit: false,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Fan photo — optional, so no "*".
class UserAvatarPicker extends StatelessWidget {
  const UserAvatarPicker({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) => _AvatarPicker(user: user);
}

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
  static const _responseTimes = ['Within 1 hour', 'Within a few hours', 'Within 24 hours', 'Within 2–3 days'];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.name);
  late final PhoneValue _initialPhone = PhoneValue.parse(widget.user.phone);
  late final _phone = TextEditingController(text: _initialPhone.number);
  late CountryCode _country = _initialPhone.country;
  late final _title = TextEditingController(text: widget.profile.title);
  late final _bio = TextEditingController(text: widget.profile.bio);
  late final _location = TextEditingController(text: widget.profile.location);
  late final _portfolio = TextEditingController(text: widget.profile.portfolioLink);
  late final _years = TextEditingController(text: widget.profile.yearsOfExperience?.toString() ?? '');
  late final _instagram = TextEditingController(text: _instagramHandleOf(widget.profile.socials.get('instagram')));
  late final _youtube = TextEditingController(text: widget.profile.socials.get('youtube'));
  late final _linkedin = TextEditingController(text: widget.profile.socials.get('linkedin'));
  late List<String> _skills = widget.profile.skills;
  late List<String> _languages = widget.profile.languages;
  late String? _categoryId = widget.profile.category?.id;
  late String _responseTime = widget.profile.responseTime;
  late bool _available = widget.profile.isAvailableForWork;
  bool _attempted = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _title, _bio, _location, _portfolio, _years, _instagram, _youtube, _linkedin]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onSave({required bool submit}) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is AuthAuthenticated ? auth.user : widget.user;
    final photoOk = (user.avatarUrl ?? '').isNotEmpty;
    final responseOk = _responseTime.trim().isNotEmpty;
    setState(() => _attempted = true);
    if (!_check(context, _formKey, extraOk: photoOk && responseOk)) return;

    final repo = sl<ProfileRepository>();
    final phone = PhoneValue(_country, _phone.text.trim()).stored;
    _save(context, () async {
      if (_name.text.trim() != widget.user.name || phone != (widget.user.phone ?? '')) {
        await repo.updateAccount(name: _name.text.trim(), phone: phone);
      }
      await repo.updateCreator({
        'title': _title.text.trim(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
        'portfolioLink': _withScheme(_portfolio.text),
        'skills': _skills,
        'languages': _languages,
        'responseTime': _responseTime.trim(),
        'isAvailableForWork': _available,
        if (_categoryId != null) 'category': _categoryId,
        if (int.tryParse(_years.text.trim()) != null) 'yearsOfExperience': int.parse(_years.text.trim()),
        'socials': {
          'instagram': _instagramUrl(_instagram.text),
          'youtube': _withScheme(_youtube.text),
          'linkedin': _withScheme(_linkedin.text),
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
    final user = _currentUser(context, widget.user);
    final photoMissing = _attempted && (user.avatarUrl ?? '').isEmpty;
    final responseOptions = {..._responseTimes, if (_responseTime.trim().isNotEmpty) _responseTime}.toList();

    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status, reason: widget.profile.rejectionReason),
          const _RequiredHint(),
          ListenableBuilder(
            listenable: Listenable.merge([_name, _title]),
            builder: (context, _) => _AvatarPicker(
              user: user,
              errorText: photoMissing ? 'Profile photo is required' : null,
              creatorCard: (image) => _CreatorCardPreview(
                image: image,
                name: _name.text.trim(),
                subtitle: categories.where((c) => c.id == _categoryId).firstOrNull?.label ?? _title.text.trim(),
                followers: widget.profile.followerCount,
                available: _available,
                verified: status == VerificationStatus.verified,
                pro: widget.profile.isProPlan,
              ),
            ),
          ),
          const _Section('About you'),
          AppTextField(label: 'Full name', isRequired: true, controller: _name, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Name')),
          _gap,
          PhoneField(controller: _phone, country: _country, onCountryChanged: (c) => setState(() => _country = c), label: 'Phone number', isRequired: true),
          _gap,
          AppTextField(
            label: 'Headline',
            isRequired: true,
            hint: 'e.g. Food & travel creator from Indore',
            controller: _title,
            maxLength: 80,
            validator: Validators.requiredText('Headline'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppDropdown<String>(
            label: 'Category',
            isRequired: true,
            items: categories.map((c) => c.id).toList(),
            value: _categoryId,
            labelOf: (id) => categories.firstWhere((c) => c.id == id).label,
            onChanged: (id) => setState(() => _categoryId = id),
            validator: (v) => v == null ? 'Choose a category' : null,
          ),
          _gap,
          AppTextField(
            label: 'Bio',
            isRequired: true,
            hint: 'Your content, audience and the brands you’ve worked with',
            controller: _bio,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v?.trim().length ?? 0) < 20 ? 'Write at least 20 characters' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          CityField(controller: _location, label: 'City', isRequired: true),
          _gap,
          AppTextField(
            label: 'Years of experience',
            controller: _years,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          ),
          const _Section('Work'),
          TagInput(
            label: 'Skills',
            isRequired: true,
            hint: 'e.g. Reels, Food photography',
            values: _skills,
            onChanged: (v) => setState(() => _skills = v),
            validator: _requiredTags('skill'),
          ),
          _gap,
          TagInput(
            label: 'Languages',
            isRequired: true,
            hint: 'e.g. Hindi',
            values: _languages,
            onChanged: (v) => setState(() => _languages = v),
            validator: _requiredTags('language'),
          ),
          _gap,
          const FieldLabel('Response time', isRequired: true),
          ChoicePills<String>(
            options: responseOptions,
            selected: {_responseTime},
            labelOf: (s) => s,
            onChanged: (s) => setState(() => _responseTime = s),
          ),
          if (_attempted && _responseTime.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Choose how quickly you reply', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
            ),
          const _Section('Social links'),
          AppTextField(
            label: 'Instagram',
            isRequired: true,
            hint: 'username or instagram.com/username',
            controller: _instagram,
            prefixIcon: AppIcons.instagram,
            keyboardType: TextInputType.url,
            validator: _instagramRequired,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'YouTube', hint: 'https://youtube.com/@…', controller: _youtube, prefixIcon: AppIcons.youtube, keyboardType: TextInputType.url, validator: _optionalUrl),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'LinkedIn', hint: 'https://linkedin.com/in/…', controller: _linkedin, prefixIcon: AppIcons.linkedin, keyboardType: TextInputType.url, validator: _optionalUrl),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Portfolio', hint: 'https://', controller: _portfolio, prefixIcon: AppIcons.link, keyboardType: TextInputType.url, validator: _optionalUrl),
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
  late final _yourName = TextEditingController(text: widget.user.name);
  late final PhoneValue _initialPhone = PhoneValue.parse(widget.user.phone);
  late final _phone = TextEditingController(text: _initialPhone.number);
  late CountryCode _country = _initialPhone.country;
  late final _company = TextEditingController(text: widget.profile.companyName);
  late final _tagline = TextEditingController(text: widget.profile.tagline);
  late final _industry = TextEditingController(text: widget.profile.industry);
  late final _about = TextEditingController(text: widget.profile.about);
  late final _location = TextEditingController(text: widget.profile.location);
  late final _website = TextEditingController(text: widget.profile.website);
  late final _founded = TextEditingController(text: widget.profile.foundedYear?.toString() ?? '');
  late final _audience = TextEditingController(text: widget.profile.targetAudience);
  late final _designation = TextEditingController(text: widget.profile.contactDesignation);
  late final _instagram = TextEditingController(text: _instagramHandleOf(widget.profile.socials.get('instagram')));
  late final _youtube = TextEditingController(text: widget.profile.socials.get('youtube'));
  late final _linkedin = TextEditingController(text: widget.profile.socials.get('linkedin'));
  late String _size = widget.profile.companySize;
  late List<String> _offers = widget.profile.whatWeOffer;
  late String? _logoUrl = widget.profile.logoUrl;
  bool _attempted = false;

  static const _sizes = ['1-10', '11-50', '51-200', '201-500', '500+'];

  @override
  void dispose() {
    for (final c in [_yourName, _phone, _company, _tagline, _industry, _about, _location, _website, _founded, _audience, _designation, _instagram, _youtube, _linkedin]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _foundedValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Founded year is required';
    final year = int.tryParse(t);
    if (year == null || year < 1800 || year > DateTime.now().year) return 'Enter a valid year';
    return null;
  }

  void _onSave({required bool submit}) {
    final logoOk = (_logoUrl ?? '').isNotEmpty;
    final sizeOk = _size.trim().isNotEmpty;
    setState(() => _attempted = true);
    if (!_check(context, _formKey, extraOk: logoOk && sizeOk)) return;

    final repo = sl<ProfileRepository>();
    final phone = PhoneValue(_country, _phone.text.trim()).stored;
    _save(context, () async {
      if (_yourName.text.trim() != widget.user.name || phone != (widget.user.phone ?? '')) {
        await repo.updateAccount(name: _yourName.text.trim(), phone: phone);
      }
      await repo.updateBrand({
        'companyName': _company.text.trim(),
        'tagline': _tagline.text.trim(),
        'industry': _industry.text.trim(),
        'about': _about.text.trim(),
        'location': _location.text.trim(),
        'website': _withScheme(_website.text),
        'targetAudience': _audience.text.trim(),
        'contactDesignation': _designation.text.trim(),
        'companySize': _size,
        'whatWeOffer': _offers,
        'foundedYear': int.parse(_founded.text.trim()),
        'socials': {
          'instagram': _instagramUrl(_instagram.text),
          'youtube': _withScheme(_youtube.text),
          'linkedin': _withScheme(_linkedin.text),
        },
        if (submit) 'submitForApproval': true,
      });
    }, submit: submit);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.profile.verificationStatus;
    final user = _currentUser(context, widget.user);
    final logoMissing = _attempted && (_logoUrl ?? '').isEmpty;
    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status, reason: widget.profile.rejectionReason),
          const _RequiredHint(),
          _AvatarPicker(
            user: user,
            isLogo: true,
            imageUrl: _logoUrl,
            onUploaded: (url) => setState(() => _logoUrl = url),
            errorText: logoMissing ? 'Company logo is required' : null,
          ),
          const _Section('You'),
          AppTextField(label: 'Your full name', isRequired: true, controller: _yourName, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Name')),
          _gap,
          PhoneField(controller: _phone, country: _country, onCountryChanged: (c) => setState(() => _country = c), label: 'Phone number', isRequired: true),
          _gap,
          AppTextField(label: 'Your designation', hint: 'e.g. Marketing manager', controller: _designation),
          const _Section('Brand'),
          AppTextField(label: 'Brand name', isRequired: true, controller: _company, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Brand name')),
          _gap,
          AppTextField(label: 'Tagline', isRequired: true, hint: 'One line about your brand', controller: _tagline, maxLength: 100, validator: Validators.requiredText('Tagline')),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(label: 'Industry', isRequired: true, hint: 'e.g. Food & beverage', controller: _industry, validator: Validators.requiredText('Industry')),
          _gap,
          AppTextField(
            label: 'About',
            isRequired: true,
            controller: _about,
            minLines: 3,
            maxLines: 8,
            maxLength: 1500,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) => (v?.trim().length ?? 0) < 20 ? 'Write at least 20 characters' : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          CityField(controller: _location, label: 'Headquarters', isRequired: true, hint: 'City where your brand is based'),
          _gap,
          AppTextField(
            label: 'Founded year',
            isRequired: true,
            hint: 'e.g. 2019',
            controller: _founded,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            validator: _foundedValidator,
          ),
          _gap,
          const FieldLabel('Team size', isRequired: true),
          ChoicePills<String>(options: _sizes, selected: {_size}, labelOf: (s) => s, onChanged: (s) => setState(() => _size = s)),
          if (_attempted && _size.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Choose your team size', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
            ),
          _gap,
          TagInput(
            label: 'What you offer creators',
            isRequired: true,
            hint: 'e.g. Free products',
            values: _offers,
            onChanged: (v) => setState(() => _offers = v),
            validator: _requiredTags('offer'),
          ),
          _gap,
          AppTextField(label: 'Target audience', controller: _audience, minLines: 2, maxLines: 4),
          const _Section('Online'),
          AppTextField(
            label: 'Instagram',
            isRequired: true,
            hint: 'username or instagram.com/username',
            controller: _instagram,
            prefixIcon: AppIcons.instagram,
            keyboardType: TextInputType.url,
            validator: _instagramRequired,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'Website', hint: 'https://', controller: _website, prefixIcon: AppIcons.globe, keyboardType: TextInputType.url, validator: _optionalUrl),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'YouTube', hint: 'https://youtube.com/@…', controller: _youtube, prefixIcon: AppIcons.youtube, keyboardType: TextInputType.url, validator: _optionalUrl),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(label: 'LinkedIn', hint: 'https://linkedin.com/company/…', controller: _linkedin, prefixIcon: AppIcons.linkedin, keyboardType: TextInputType.url, validator: _optionalUrl),
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
  static final RegExp _gstFormat = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  final _formKey = GlobalKey<FormState>();
  late final _yourName = TextEditingController(text: widget.user.name);
  late final _name = TextEditingController(text: widget.profile.agencyName);
  late final _owner = TextEditingController(text: widget.profile.ownerName);
  late final PhoneValue _initialPhone = PhoneValue.parse(widget.profile.mobile);
  late final _mobile = TextEditingController(text: _initialPhone.number);
  late CountryCode _country = _initialPhone.country;
  late final _city = TextEditingController(text: widget.profile.city);
  late final _state = TextEditingController(text: widget.profile.state);
  late final _gst = TextEditingController(text: widget.profile.gstNumber);
  late final _years = TextEditingController(text: widget.profile.yearsInBusiness?.toString() ?? '');
  late final _specialization = TextEditingController(text: widget.profile.specialization);
  late String _team = widget.profile.teamSize;
  late String? _documentUrl = widget.profile.documentUrl;
  bool _attempted = false;

  static const _teams = ['1-5', '6-20', '21-50', '50+'];

  @override
  void dispose() {
    for (final c in [_yourName, _name, _owner, _mobile, _city, _state, _gst, _years, _specialization]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _gstValidator(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return 'GST number is required';
    return _gstFormat.hasMatch(t) ? null : 'Enter a valid 15-character GST number';
  }

  void _onSave({required bool submit}) {
    final docOk = (_documentUrl ?? '').isNotEmpty;
    setState(() => _attempted = true);
    if (!_check(context, _formKey, extraOk: docOk)) return;

    final repo = sl<ProfileRepository>();
    _save(context, () async {
      if (_yourName.text.trim() != widget.user.name) await repo.updateAccount(name: _yourName.text.trim());
      await repo.updateAgency({
        'agencyName': _name.text.trim(),
        'ownerName': _owner.text.trim(),
        'mobile': PhoneValue(_country, _mobile.text.trim()).stored,
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
    final docMissing = _attempted && (_documentUrl ?? '').isEmpty;
    return Form(
      key: _formKey,
      child: ListView(
        padding: _padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _SubmitNotice(status: status, reason: widget.profile.rejectionReason),
          const _RequiredHint(),
          AppTextField(label: 'Your full name', isRequired: true, controller: _yourName, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Name')),
          _gap,
          AppTextField(label: 'Agency name', isRequired: true, controller: _name, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Agency name')),
          _gap,
          AppTextField(label: 'Owner name', isRequired: true, controller: _owner, textCapitalization: TextCapitalization.words, validator: Validators.requiredText('Owner name')),
          _gap,
          PhoneField(controller: _mobile, country: _country, onCountryChanged: (c) => setState(() => _country = c), label: 'Mobile number', isRequired: true),
          _gap,
          CityField(
            controller: _city,
            label: 'City',
            isRequired: true,
            onPicked: (s) {
              if (s.state.isNotEmpty) _state.text = s.state;
            },
          ),
          _gap,
          StateField(controller: _state, isRequired: true),
          _gap,
          AppTextField(
            label: 'GST number',
            isRequired: true,
            hint: 'e.g. 23ABCDE1234F1Z5',
            controller: _gst,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(15)],
            validator: _gstValidator,
          ),
          _gap,
          const FieldLabel('Team size'),
          ChoicePills<String>(options: _teams, selected: {_team}, labelOf: (s) => s, onChanged: (s) => setState(() => _team = s)),
          _gap,
          AppTextField(
            label: 'Years in business',
            controller: _years,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          ),
          _gap,
          AppTextField(label: 'Specialization', hint: 'e.g. Food & lifestyle creators', controller: _specialization),
          _gap,
          const FieldLabel('ID or address proof', isRequired: true),
          AppCard(
            onTap: actions.isBusy ? null : _uploadDocument,
            borderColor: docMissing ? AppColors.error : null,
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
          if (docMissing)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('ID / address proof is required', style: context.text.bodySmall?.copyWith(color: AppColors.error)),
            ),
          _SaveBar(onSave: _onSave, canSubmit: status == VerificationStatus.unverified || status == VerificationStatus.rejected),
        ],
      ),
    );
  }
}