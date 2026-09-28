import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/profile_repository.dart';

/// Lets a creator or brand join an agency with the agency's code.
Future<bool> showLinkAgencySheet(BuildContext context, {required bool asCreator}) async {
  final result = await showAppSheet<bool>(context, builder: (_) => SheetActionScope(child: _LinkAgencySheet(asCreator: asCreator)));
  return result ?? false;
}

class _LinkAgencySheet extends StatefulWidget {
  const _LinkAgencySheet({required this.asCreator});

  final bool asCreator;

  @override
  State<_LinkAgencySheet> createState() => _LinkAgencySheetState();
}

class _LinkAgencySheetState extends State<_LinkAgencySheet> {
  final _code = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<ActionCubit>().run('link', () async {
      await sl<ProfileRepository>().linkAgency(asCreator: widget.asCreator, referralCode: _code.text.trim().toUpperCase());
      return true;
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Join an agency',
      subtitle: 'Enter the code your agency shared with you. This can’t be changed later.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Agency code',
              controller: _code,
              prefixIcon: AppIcons.agency,
              textCapitalization: TextCapitalization.characters,
              hint: '8 characters, e.g. AGK7F3QX',
              inputFormatters: Validators.referralCodeFormatters,
              validator: Validators.referralCode,
            ),
            const SizedBox(height: AppSpacing.lg),
            const InlineActionError(),
            AppButton(label: 'Join agency', isLoading: busy, onPressed: busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}