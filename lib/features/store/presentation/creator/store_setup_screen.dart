import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/action_cubit.dart';
import '../../../../core/bloc/load_cubit.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/action_scope.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/image_upload_box.dart';
import '../../data/store_repository.dart';
import '../widgets/store_widgets.dart';

const _brand = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF4511E), Color(0xFFEC2A78)]);

/// Four-step store activation: Profile → Payout → KYC → Terms. Shown inside
/// StoreEntryScreen (which owns the `LoadCubit<MyStore>`) until the store is active.
/// When the admin requires a paid plan, creators without one see the plans
/// first.
class StoreSetupView extends StatefulWidget {
  const StoreSetupView({super.key, required this.data});

  final MyStore data;

  @override
  State<StoreSetupView> createState() => _StoreSetupViewState();
}

class _StoreSetupViewState extends State<StoreSetupView> {
  late int _step = widget.data.steps.nextStep > 3 ? 3 : widget.data.steps.nextStep;

  /// True while the creator is re-doing KYC after a rejection.
  bool _fixing = false;

  static const _titles = ['Store profile', 'Payout details', 'Verify your identity', 'Store terms'];
  static const _subtitles = [
    'How buyers will see your store',
    'Where your earnings are paid',
    'Required by law before payouts',
    'Read and accept to finish',
  ];
  static const _labels = ['Profile', 'Payout', 'KYC', 'Terms'];
  static const _icons = [AppIcons.store, AppIcons.bank, AppIcons.idCard, AppIcons.shieldCheck];

  void _saved(MyStore updated) {
    context.read<LoadCubit<MyStore>>().replace(updated);
    HapticFeedback.lightImpact();
    final next = updated.steps.nextStep;
    setState(() {
      // KYC re-sent → back to the "under review" screen.
      if (updated.store?.kycStatus == KycStatus.pending) _fixing = false;
      if (next <= 3) _step = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final store = data.store;

    // Admin switched on "paid plan required" and this creator has none.
    if (data.needsPlan) return const _PlanGate();

    // All four steps done → waiting for (or rejected by) the admin.
    if (!_fixing && store != null && data.steps.complete && store.status != StoreStatus.active) {
      return _ReviewState(
        store: store,
        onFixKyc: () => setState(() {
          _fixing = true;
          _step = 2;
        }),
      );
    }

    final steps = [data.steps.profile, data.steps.payout, data.steps.kyc, data.steps.terms];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.huge),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _Hero(feePercent: data.storeFeePercent, planName: data.subscriptionRequired && data.hasSubscription ? data.planName : '')
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.06, curve: Curves.easeOutCubic),
        if (store == null) ...[
          const SizedBox(height: AppSpacing.lg),
          const _Perks(),
        ],
        const SizedBox(height: AppSpacing.xl),
        _StepBar(
          current: _step,
          done: steps,
          icons: _icons,
          labels: _labels,
          onTap: (i) {
            // Can jump back to finished steps, or forward to the next open one.
            if (steps[i] || i <= data.steps.nextStep) setState(() => _step = i);
          },
        ).animate().fadeIn(delay: 120.ms, duration: 350.ms),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim), child: child),
          ),
          child: _StepCard(
            key: ValueKey(_step),
            index: _step,
            title: _titles[_step],
            subtitle: _subtitles[_step],
            icon: _icons[_step],
            child: ActionScope(
              child: switch (_step) {
                0 => _ProfileStep(store: store, onSaved: _saved),
                1 => _PayoutStep(store: store, onSaved: _saved),
                2 => _KycStep(store: store, onSaved: _saved),
                _ => _TermsStep(data: data, onSaved: _saved),
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- hero ----------

class _Hero extends StatelessWidget {
  const _Hero({required this.feePercent, this.planName = ''});

  final double feePercent;
  final String planName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: const BoxDecoration(gradient: _brand),
        child: Stack(
          children: [
            // Soft floating shapes
            Positioned(right: -30, top: -30, child: _Blob(size: 140, opacity: 0.16)),
            Positioned(right: 60, bottom: -40, child: _Blob(size: 100, opacity: 0.10)),
            Positioned(
              right: 18,
              top: 22,
              child: const Icon(AppIcons.storeFilled, size: 64, color: Colors.white24)
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .moveY(begin: 0, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(planName.isEmpty ? AppIcons.sparkle : AppIcons.crown, size: 12, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          planName.isEmpty ? 'FANITT STORE' : '${planName.toUpperCase()} PLAN',
                          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.only(right: 70),
                    child: Text(
                      'Open your Fanitt Store',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sell digital products, go live, take calls and get tips — all in one place.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _HeroFact(icon: AppIcons.lightning, text: 'Setup in 4 steps'),
                      const SizedBox(width: 8),
                      _HeroFact(icon: AppIcons.rupee, text: 'You keep ${_pct(100 - feePercent)}%'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: opacity)));
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------- what you get ----------

class _Perks extends StatelessWidget {
  const _Perks();

  static const _items = [
    (AppIcons.package, 'Digital products', 'Courses, ebooks, templates', Color(0xFFF4511E)),
    (AppIcons.broadcast, 'Go live', 'Public or private streams', Color(0xFFEC2A78)),
    (AppIcons.phone, '1:1 calls', 'Paid chat, audio & video', Color(0xFF6D5DFC)),
    (AppIcons.gift, 'FanBox tips', 'Fans support you directly', Color(0xFF10B981)),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What you can do', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            for (final (i, item) in _items.indexed)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: item.$4.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                      child: Icon(item.$1, size: 18, color: item.$4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
                          Text(item.$3, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate(delay: (80 * i + 150).ms).fadeIn(duration: 320.ms).scaleXY(begin: 0.94, curve: Curves.easeOutBack),
          ],
        ),
      ],
    );
  }
}

// ---------- paid plan needed ----------

/// Shown when the admin requires a paid plan and the creator has none.
class _PlanGate extends StatelessWidget {
  const _PlanGate();

  Future<void> _openPlans(BuildContext context) async {
    HapticFeedback.selectionClick();
    await context.push(AppRoutes.plans);
    // Back from the plans screen — check again.
    if (context.mounted) await context.read<LoadCubit<MyStore>>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const benefits = [
      'Your own store page with your brand',
      'Sell unlimited digital products',
      'Go live, take paid calls & get FanBox tips',
      'Earnings straight to your Fanitt wallet',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.huge),
      children: [
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _brand,
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))],
            ),
            child: const Icon(AppIcons.crown, size: 46, color: Colors.white),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1, end: 1.05, duration: 1400.ms, curve: Curves.easeInOut),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Unlock your Fanitt Store', textAlign: TextAlign.center, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Opening a store needs a Fanitt plan — monthly or yearly. Pick one and come right back to set up your store.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
          child: Column(
            children: [
              for (final (i, b) in benefits.indexed)
                Padding(
                  padding: EdgeInsets.only(bottom: i == benefits.length - 1 ? 0 : 12),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brand),
                        child: const Icon(AppIcons.check, size: 13, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(b, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ).animate(delay: (90 * i + 200).ms).fadeIn(duration: 300.ms).slideX(begin: 0.08),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: 'See plans', icon: AppIcons.crown, onPressed: () => _openPlans(context)),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.read<LoadCubit<MyStore>>().refresh(),
          child: const Text('I’ve already subscribed — check again'),
        ),
      ],
    );
  }
}

// ---------- progress ----------

class _StepBar extends StatelessWidget {
  const _StepBar({required this.current, required this.done, required this.icons, required this.labels, required this.onTap});

  final int current;
  final List<bool> done;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final finished = done.where((d) => d).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: palette.border)),
      child: Column(
        children: [
          Row(
            children: [
              Text('Setup progress', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('$finished of 4 done', style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: finished / 4),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Stack(
                children: [
                  Container(height: 6, color: palette.surfaceMuted),
                  FractionallySizedBox(widthFactor: v.clamp(0, 1).toDouble(), child: Container(height: 6, decoration: const BoxDecoration(gradient: _brand))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: i == current && !done[i] ? _brand : null,
                            color: done[i] ? AppColors.success : (i == current ? null : palette.surfaceMuted),
                            boxShadow: i == current ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
                          ),
                          child: Icon(done[i] ? AppIcons.check : icons[i], size: 18, color: done[i] || i == current ? Colors.white : palette.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          style: context.text.labelSmall?.copyWith(
                            fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                            color: i == current ? palette.textPrimary : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// White card around each step's form.
class _StepCard extends StatelessWidget {
  const _StepCard({super.key, required this.index, required this.title, required this.subtitle, required this.icon, required this.child});

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: context.isDark ? null : const [BoxShadow(color: Color(0x0A101828), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: palette.primarySoft, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STEP ${index + 1} OF 4', style: context.text.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ---------- step 1: profile ----------

class _ProfileStep extends StatefulWidget {
  const _ProfileStep({required this.store, required this.onSaved});

  final StoreInfo? store;
  final ValueChanged<MyStore> onSaved;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.store?.name ?? '');
  late final _tagline = TextEditingController(text: widget.store?.tagline ?? '');
  late final _about = TextEditingController(text: widget.store?.about ?? '');

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = sl<StoreRepository>();
    final creating = widget.store == null;
    final result = await context.read<ActionCubit>().run(
      'profile',
          () => creating
          ? repo.createStore(name: _name.text.trim(), tagline: _tagline.text.trim(), about: _about.text.trim())
          : repo.updateStore(name: _name.text.trim(), tagline: _tagline.text.trim(), about: _about.text.trim()),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onSaved(result);
    } else if (creating) {
      // e.g. a plan became required meanwhile — reload to show the right screen.
      context.read<LoadCubit<MyStore>>().refresh();
    }
  }

  Future<void> _pickImage({required bool banner}) async {
    final image = await sl<MediaPicker>().image();
    if (image == null || !mounted) return;
    final result = await context.read<ActionCubit>().run('image', () => sl<StoreRepository>().uploadStoreImage(image, banner: banner));
    if (result != null && mounted) {
      widget.onSaved(result);
      AppSnackbar.success(context, banner ? 'Banner updated' : 'Logo updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final store = widget.store;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store != null) ...[
            // Banner — same shape and look as the store card on Home.
            ListenableBuilder(
              listenable: Listenable.merge([_name, _tagline]),
              builder: (context, _) => ImageUploadBox(
                slot: ImageSlot.storeBanner,
                url: store.bannerUrl,
                optional: true,
                enabled: !busy,
                onPick: () => _pickImage(banner: true),
                previewBuilder: (context, image) => StorefrontPreview(
                  banner: image,
                  name: _name.text.trim(),
                  tagline: _tagline.text.trim(),
                  logoUrl: store.logoUrl,
                  sold: store.stats.orders,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Logo — round, shown on the store card, store page and products.
            ImageUploadBox(
              slot: ImageSlot.logo,
              url: store.logoUrl,
              enabled: !busy,
              width: 84,
              onPick: () => _pickImage(banner: false),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppTextField(
            label: 'Store name *',
            hint: 'e.g. Riya’s Design Studio',
            controller: _name,
            maxLength: 60,
            prefixIcon: AppIcons.store,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter at least 2 characters' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Tagline',
            hint: 'One line about what you sell',
            controller: _tagline,
            maxLength: 120,
            prefixIcon: AppIcons.sparkle,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'About',
            hint: 'Tell buyers who you are and what they get',
            controller: _about,
            minLines: 3,
            maxLines: 6,
            maxLength: 1500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(
            label: store == null ? 'Create my store' : 'Save & continue',
            icon: store == null ? AppIcons.storeFilled : AppIcons.arrowRightSimple,
            isLoading: busy,
            onPressed: busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ---------- step 2: payout ----------

class _PayoutStep extends StatefulWidget {
  const _PayoutStep({required this.store, required this.onSaved});

  final StoreInfo? store;
  final ValueChanged<MyStore> onSaved;

  @override
  State<_PayoutStep> createState() => _PayoutStepState();
}

class _PayoutStepState extends State<_PayoutStep> {
  final _formKey = GlobalKey<FormState>();
  late bool _upi = widget.store?.payout?.isUpi ?? true;
  late final _upiId = TextEditingController(text: widget.store?.payout?.upiId ?? '');
  late final _holder = TextEditingController(text: widget.store?.payout?.accountHolderName ?? '');
  final _account = TextEditingController();
  final _accountAgain = TextEditingController();
  late final _ifsc = TextEditingController(text: widget.store?.payout?.ifsc ?? '');
  late final _bank = TextEditingController(text: widget.store?.payout?.bankName ?? '');

  @override
  void dispose() {
    for (final c in [_upiId, _holder, _account, _accountAgain, _ifsc, _bank]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = sl<StoreRepository>();
    final result = await context.read<ActionCubit>().run(
      'payout',
          () => _upi
          ? repo.savePayoutUpi(_upiId.text.trim())
          : repo.savePayoutBank(
        accountHolderName: _holder.text.trim(),
        accountNumber: _account.text.trim(),
        ifsc: _ifsc.text.trim().toUpperCase(),
        bankName: _bank.text.trim(),
      ),
    );
    if (result != null && mounted) widget.onSaved(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final saved = widget.store?.payout;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Where your earnings are paid when you withdraw.', style: context.text.bodyMedium),
          if (saved != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Row(
                children: [
                  const Icon(AppIcons.checkCircle, color: AppColors.success, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      saved.isUpi ? 'Saved UPI: ${saved.upiId}' : 'Saved bank: ${saved.accountNumberMasked} · ${saved.ifsc}',
                      style: context.text.bodySmall?.copyWith(color: context.palette.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ChoicePills<bool>(options: const [true, false], selected: {_upi}, labelOf: (v) => v ? 'UPI' : 'Bank account', onChanged: (v) => setState(() => _upi = v)),
          const SizedBox(height: AppSpacing.md),
          if (_upi)
            AppTextField(
              label: 'UPI ID',
              hint: 'name@okaxis',
              controller: _upiId,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: AppIcons.at,
              validator: (v) => RegExp(r'^[\w.\-]{2,256}@[a-zA-Z]{2,64}$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid UPI ID',
            )
          else ...[
            AppTextField(
              label: 'Account holder name',
              controller: _holder,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter the name on the account' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Account number',
              controller: _account,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
              validator: (v) => RegExp(r'^\d{9,18}$').hasMatch(v?.trim() ?? '') ? null : 'Account number must be 9–18 digits',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Re-enter account number',
              controller: _accountAgain,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(18)],
              validator: (v) => v?.trim() == _account.text.trim() ? null : 'Account numbers don’t match',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'IFSC',
              hint: 'HDFC0001234',
              controller: _ifsc,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(11)],
              validator: (v) => RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(v?.trim().toUpperCase() ?? '') ? null : 'Enter a valid IFSC',
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Bank name (optional)', controller: _bank, textCapitalization: TextCapitalization.words),
          ],
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Save & continue', isLoading: busy, onPressed: busy ? null : _save),
        ],
      ),
    );
  }
}

// ---------- step 3: KYC ----------

const _idTypes = {'aadhaar': 'Aadhaar', 'passport': 'Passport', 'driving_licence': 'Driving licence', 'voter_id': 'Voter ID'};

class _KycStep extends StatefulWidget {
  const _KycStep({required this.store, required this.onSaved});

  final StoreInfo? store;
  final ValueChanged<MyStore> onSaved;

  @override
  State<_KycStep> createState() => _KycStepState();
}

class _KycStepState extends State<_KycStep> {
  final _formKey = GlobalKey<FormState>();
  final _pan = TextEditingController();
  final _panName = TextEditingController();
  String _idType = 'aadhaar';
  PickedMedia? _panDoc;
  PickedMedia? _idDoc;

  @override
  void dispose() {
    _pan.dispose();
    _panName.dispose();
    super.dispose();
  }

  Future<PickedMedia?> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    final file = result?.files.single;
    if (file?.path == null) return null;
    if (await File(file!.path!).length() > 8 * 1024 * 1024) {
      if (mounted) AppSnackbar.error(context, 'Each document can be up to 8 MB');
      return null;
    }
    return PickedMedia(path: file.path!, name: file.name);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_panDoc == null || _idDoc == null) {
      AppSnackbar.error(context, 'Add a photo of your PAN card and your ID proof');
      return;
    }
    final result = await context.read<ActionCubit>().run(
      'kyc',
          () => sl<StoreRepository>().submitKyc(
        panNumber: _pan.text.trim().toUpperCase(),
        panName: _panName.text.trim(),
        idType: _idType,
        panDocument: _panDoc!,
        idDocument: _idDoc!,
      ),
    );
    if (result != null && mounted) widget.onSaved(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final store = widget.store;
    if (store != null && store.kycStatus == KycStatus.pending) {
      return const _InfoBox(icon: AppIcons.hourglass, color: AppColors.warning, title: 'KYC submitted', message: 'We’re checking your documents. This usually takes less than a day.');
    }
    if (store != null && store.kycStatus == KycStatus.verified) {
      return const _InfoBox(icon: AppIcons.sealCheck, color: AppColors.success, title: 'KYC verified', message: 'Your identity is confirmed.');
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store?.kycStatus == KycStatus.rejected) ...[
            _InfoBox(icon: AppIcons.warning, color: AppColors.error, title: 'Please submit again', message: store!.kycRejectionReason.isEmpty ? 'Your documents could not be verified.' : store.kycRejectionReason),
            const SizedBox(height: AppSpacing.md),
          ],
          Text('Required by law before you can receive payments. Your documents are stored privately and only our review team can see them.', style: context.text.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'PAN number',
            hint: 'ABCDE1234F',
            controller: _pan,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(10)],
            validator: (v) => RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(v?.trim().toUpperCase() ?? '') ? null : 'Enter a valid PAN',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Name as on PAN',
            controller: _panName,
            textCapitalization: TextCapitalization.characters,
            validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter the name exactly as on your PAN' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppDropdown<String>(label: 'ID proof', items: _idTypes.keys.toList(), value: _idType, labelOf: (k) => _idTypes[k]!, onChanged: (v) => setState(() => _idType = v ?? 'aadhaar')),
          const SizedBox(height: AppSpacing.md),
          _DocPicker(label: 'PAN card photo', file: _panDoc, onPick: busy ? null : () async {
            final f = await _pickDocument();
            if (f != null) setState(() => _panDoc = f);
          }),
          const SizedBox(height: AppSpacing.sm),
          _DocPicker(label: '${_idTypes[_idType]} photo', file: _idDoc, onPick: busy ? null : () async {
            final f = await _pickDocument();
            if (f != null) setState(() => _idDoc = f);
          }),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Submit for verification', isLoading: busy, onPressed: busy ? null : _submit),
        ],
      ),
    );
  }
}

class _DocPicker extends StatelessWidget {
  const _DocPicker({required this.label, required this.file, required this.onPick});

  final String label;
  final PickedMedia? file;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final picked = file != null;
    final isImage = picked && !file!.name.toLowerCase().endsWith('.pdf');
    return Material(
      color: picked ? palette.primarySoft : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: isImage
                      ? Image.file(File(file!.path), fit: BoxFit.cover)
                      : ColoredBox(color: palette.surface, child: Icon(picked ? AppIcons.fileText : AppIcons.upload, color: palette.textSecondary)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: context.text.titleSmall),
                    Text(picked ? file!.name : 'Photo or PDF, up to 8 MB', style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(picked ? AppIcons.checkCircle : AppIcons.plus, color: picked ? AppColors.success : AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- step 4: terms ----------

class _TermsStep extends StatefulWidget {
  const _TermsStep({required this.data, required this.onSaved});

  final MyStore data;
  final ValueChanged<MyStore> onSaved;

  @override
  State<_TermsStep> createState() => _TermsStepState();
}

class _TermsStepState extends State<_TermsStep> {
  bool _agree = false;

  Future<void> _accept() async {
    final result = await context.read<ActionCubit>().run('terms', () => sl<StoreRepository>().acceptTerms(widget.data.termsVersion));
    if (result != null && mounted) widget.onSaved(result);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 280),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: SingleChildScrollView(child: Text(widget.data.termsText, style: context.text.bodyMedium?.copyWith(color: palette.textPrimary, height: 1.5))),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Version ${widget.data.termsVersion}', style: context.text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: _agree,
          onChanged: busy ? null : (v) => setState(() => _agree = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
          title: Text('I have read and agree to the Fanitt Store terms', style: context.text.bodyMedium?.copyWith(color: palette.textPrimary)),
        ),
        const SizedBox(height: AppSpacing.sm),
        const InlineActionError(),
        AppButton(label: 'Agree & finish', isLoading: busy, onPressed: !_agree || busy ? null : _accept),
      ],
    );
  }
}

// ---------- review state ----------

class _ReviewState extends StatelessWidget {
  const _ReviewState({required this.store, required this.onFixKyc});

  final StoreInfo store;
  final VoidCallback onFixKyc;

  @override
  Widget build(BuildContext context) {
    final rejected = store.status == StoreStatus.rejected || store.kycStatus == KycStatus.rejected;
    final suspended = store.status == StoreStatus.suspended;
    final color = rejected || suspended ? AppColors.error : AppColors.warning;
    final icon = suspended ? AppIcons.lock : (rejected ? AppIcons.warning : AppIcons.hourglass);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
            child: Icon(icon, size: 44, color: color),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1, end: 1.06, duration: 1200.ms, curve: Curves.easeInOut),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          suspended ? 'Store suspended' : (rejected ? 'KYC needs another look' : 'Your store is under review'),
          textAlign: TextAlign.center,
          style: context.text.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          suspended
              ? (store.statusReason.isEmpty ? 'Contact support to know more.' : store.statusReason)
              : rejected
              ? (store.kycRejectionReason.isEmpty ? store.statusReason : store.kycRejectionReason)
              : 'We’re checking your KYC. You’ll get a notification as soon as your store is live — usually within a day.',
          textAlign: TextAlign.center,
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        if (rejected && !suspended) AppButton(label: 'Update KYC', icon: AppIcons.idCard, onPressed: onFixKyc),
      ].animate(interval: 60.ms).fadeIn(duration: 300.ms).slideY(begin: 0.06),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.color, required this.title, required this.message});

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall?.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(message, style: context.text.bodySmall?.copyWith(color: context.palette.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Home store card (full-bleed banner, logo, name, tagline) — used for
/// the banner upload preview and the "My store" header so all look the same.
class StorefrontPreview extends StatelessWidget {
  const StorefrontPreview({
    super.key,
    required this.banner,
    required this.name,
    required this.tagline,
    required this.logoUrl,
    this.sold = 0,
    this.topRight,
    this.logoHeroTag,
  });

  /// The banner picture (or a placeholder).
  final Widget banner;
  final String name;
  final String tagline;
  final String logoUrl;
  final int sold;

  /// Optional badge in the top-right corner (e.g. "Live").
  final Widget? topRight;
  final Object? logoHeroTag;

  /// Brand gradient shown when there is no banner yet.
  static Widget placeholder() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF8A5B), Color(0xFFF4511E), Color(0xFFEC2A78)]),
    ),
    child: Center(child: Icon(AppIcons.storeFilled, color: Colors.white24, size: 56)),
  );

  @override
  Widget build(BuildContext context) {
    final shownName = name.isEmpty ? 'Your store name' : name;
    final logo = StoreLogo(name: shownName, url: logoUrl, size: 54, borderColor: Colors.white);
    return Stack(
      fit: StackFit.expand,
      children: [
        banner,
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
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.storeFilled, size: 12, color: AppColors.primary),
                SizedBox(width: 4),
                Text('SHOP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ],
            ),
          ),
        ),
        if (topRight != null) Positioned(right: 10, top: 10, child: topRight!),
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              logoHeroTag == null ? logo : Hero(tag: logoHeroTag!, child: logo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shownName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: name.isEmpty ? Colors.white70 : Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline.isEmpty ? 'Courses, guides & templates' : tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sold > 0 ? AppIcons.package : AppIcons.sparkle, size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            sold > 0 ? '${Fmt.compact(sold)} sold' : 'NEW STORE',
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF4511E), Color(0xFFEC2A78)])),
                child: const Icon(AppIcons.arrowUpRight, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}