import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/action_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/action_scope.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/review_repository.dart';

/// Rates the other side of a completed campaign. Returns true when sent.
Future<bool> showReviewSheet(
  BuildContext context, {
  required String toUserId,
  required String campaignId,
  required String name,
}) async {
  final sent = await showAppSheet<bool>(
    context,
    builder: (_) => SheetActionScope(child: _ReviewSheet(toUserId: toUserId, campaignId: campaignId, name: name)),
  );
  return sent ?? false;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.toUserId, required this.campaignId, required this.name});

  final String toUserId;
  final String campaignId;
  final String name;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();
  int _rating = 0;

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await context.read<ActionCubit>().run('review', () async {
      await sl<ReviewRepository>().reviewCampaign(
        toUserId: widget.toUserId,
        campaignId: widget.campaignId,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      return true;
    });
    if (ok != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<ActionCubit>().state.isBusy;
    return SheetBody(
      title: 'Review ${widget.name}',
      subtitle: 'Your review appears on their public profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  iconSize: 36,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _rating = i);
                  },
                  icon: AnimatedScale(
                    scale: i <= _rating ? 1.1 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(i <= _rating ? AppIcons.starFilled : AppIcons.star, color: AppColors.warning),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 22,
            child: Text(_labels[_rating], textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            label: 'Comment (optional)',
            hint: 'How was it working together?',
            controller: _comment,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.md),
          const InlineActionError(),
          AppButton(label: 'Submit review', isLoading: busy, onPressed: busy || _rating == 0 ? null : _submit),
        ],
      ),
    );
  }
}
