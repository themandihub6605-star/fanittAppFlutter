import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/link_opener.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';

class _Section {
  const _Section(this.title, this.body);

  final String title;
  final String body;
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String lastUpdated = 'January 2026';
  static const String contactEmail = AppConfig.supportEmail;
  static const String contactPhone = AppConfig.supportPhone;

  static const List<_Section> _sections = [
    _Section(
      'Information We Collect',
      'When you create an account on Fanitt, we collect information such as your name, email address, phone number, '
          'and role (Fan, Creator, Brand, or Agency). If you sign up as a Creator, Brand, or Agency, we may also collect '
          'additional details like your category, portfolio links, company information, and identity/address documents '
          'for verification purposes.',
    ),
    _Section(
      'How We Use Your Information',
      'We use the information you provide to create and manage your account, process bookings and payments, verify '
          'Creator/Brand/Agency accounts, send you notifications about your activity, and improve the Fanitt platform. '
          'We never sell your personal data to third parties.',
    ),
    _Section(
      'Payments & Escrow',
      'Payments made on Fanitt (for sessions, donations, or brand campaigns) are processed through our payment partner, '
          'Razorpay. Funds for brand campaigns are held in escrow until work is confirmed complete. We do not store your '
          'card or bank details directly — these are handled securely by our payment processor.',
    ),
    _Section(
      'Referral Program',
      'If you use a referral code at signup, we record which account referred you so that referral commissions can be '
          'calculated and paid out accurately. This relationship is stored against your account and is used only for '
          'commission tracking.',
    ),
    _Section(
      'Data Sharing',
      'We share your information only where necessary — with our payment processor to complete transactions, and with '
          'other users when required for the service to function (for example, a Brand and Creator can see each other\'s '
          'public profile and contact details once a campaign is confirmed).',
    ),
    _Section(
      'Your Rights',
      'You can update your profile information at any time from your account settings. If you wish to deactivate your '
          'account or request deletion of your data, you can do so from your account settings or by contacting us directly.',
    ),
    _Section(
      'Cookies & Sessions',
      'We use cookies and local storage to keep you signed in and remember your preferences. These are essential for the '
          'platform to function and are not used for third-party advertising.',
    ),
    _Section(
      'Changes to This Policy',
      'We may update this Privacy Policy from time to time. Significant changes will be communicated via a notification '
          'on the platform or by email.',
    ),
  ];

  Future<void> _email(BuildContext context) async {
    try {
      await LinkOpener.email(contactEmail);
    } on ApiException catch (error) {
      if (context.mounted) AppSnackbar.error(context, error.message);
    }
  }

  Future<void> _call(BuildContext context) async {
    try {
      await LinkOpener.open('tel:${contactPhone.replaceAll(' ', '')}');
    } on ApiException catch (error) {
      if (context.mounted) AppSnackbar.error(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
        children: [
          Text('Legal', style: context.text.labelMedium?.copyWith(color: AppColors.primary)),
          const SizedBox(height: AppSpacing.xxs),
          Text('Privacy Policy', style: context.text.headlineMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text('Last updated: $lastUpdated', style: context.text.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          for (final (index, section) in _sections.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: _SectionBlock(number: index + 1, section: section),
            ).animate(delay: (40 * index).ms).fadeIn(duration: 300.ms).slideY(begin: 0.04),
          _SectionBlock(
            number: _sections.length + 1,
            section: const _Section(
              'Contact Us',
              'If you have any questions about this Privacy Policy or how your data is handled, reach out to us.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(AppIcons.mail, color: palette.textSecondary),
                  title: Text(contactEmail, style: context.text.titleSmall),
                  trailing: Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                  onTap: () => _email(context),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: Icon(AppIcons.phone, color: palette.textSecondary),
                  title: Text(contactPhone, style: context.text.titleSmall),
                  trailing: Icon(AppIcons.chevronRight, size: 18, color: palette.textTertiary),
                  onTap: () => _call(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.number, required this.section});

  final int number;
  final _Section section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$number. ${section.title}', style: context.text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          section.body,
          style: context.text.bodyMedium?.copyWith(color: context.palette.textSecondary, height: 1.6),
        ),
      ],
    );
  }
}