import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../data/store_repository.dart';
import '../widgets/store_checkout.dart';

/// Buyer: choose call type and minutes, pay, then wait on the call screen.
Future<void> showRequestCallSheet(BuildContext context, {required StoreInfo store, required CallInfo info}) async {
  final request = await showAppSheet<_CallRequest>(context, builder: (_) => _RequestCallSheet(store: store, info: info));
  if (request == null || !context.mounted) return;

  CallSession? created;
  final order = await payForStoreItem(
    context,
    amount: request.amount,
    title: '${request.video ? 'Video' : 'Audio'} call with ${store.name} · ${request.minutes} min',
    start: (payWith) async {
      final result = await sl<StoreRepository>().requestCall(store.id, video: request.video, minutes: request.minutes, note: request.note, payWith: payWith);
      created = result.call;
      return result.checkout;
    },
  );
  final call = created;
  if (order == null || call == null || !context.mounted) return;
  await context.push(AppRoutes.storeCall(call.id));
}

class _CallRequest {
  const _CallRequest({required this.video, required this.minutes, required this.note, required this.amount});
  final bool video;
  final int minutes;
  final String note;
  final int amount;
}

class _RequestCallSheet extends StatefulWidget {
  const _RequestCallSheet({required this.store, required this.info});

  final StoreInfo store;
  final CallInfo info;

  @override
  State<_RequestCallSheet> createState() => _RequestCallSheetState();
}

class _RequestCallSheetState extends State<_RequestCallSheet> {
  static const _presets = [5, 10, 15, 30];
  late bool _video = !widget.info.audioEnabled && widget.info.videoEnabled;
  int _minutes = 10;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _rate => _video ? widget.info.videoRate : widget.info.audioRate;

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final amount = _rate * _minutes;
    final palette = context.palette;
    final presets = _presets.where((m) => m >= info.minMinutes && m <= info.maxMinutes).toList();
    return SheetBody(
      title: 'Call ${widget.store.name}',
      subtitle: 'You pay for the minutes up front. Unused minutes come back to your Fanitt wallet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.audioEnabled && info.videoEnabled) ...[
            ChoicePills<bool>(
              options: const [false, true],
              selected: {_video},
              labelOf: (v) => v ? 'Video · ${info.videoRate == 0 ? 'free' : '${Fmt.money(info.videoRate)}/min'}' : 'Audio · ${info.audioRate == 0 ? 'free' : '${Fmt.money(info.audioRate)}/min'}',
              onChanged: (v) => setState(() => _video = v),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const FieldLabel('How long?'),
          ChoicePills<int>(options: presets, selected: {_minutes}, labelOf: (m) => '$m min', onChanged: (m) => setState(() => _minutes = m)),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: _note, maxLength: 300, maxLines: 2, decoration: const InputDecoration(hintText: 'What do you want to talk about? (optional)')),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                Icon(_video ? AppIcons.videoCamera : AppIcons.phone, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('$_minutes min ${_video ? 'video' : 'audio'} call', style: context.text.titleSmall)),
                Text(amount == 0 ? 'Free' : Fmt.money(amount), style: context.text.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: amount == 0 ? 'Call now' : 'Continue to pay',
            icon: AppIcons.phone,
            onPressed: () => Navigator.of(context).pop(_CallRequest(video: _video, minutes: _minutes, note: _note.text.trim(), amount: amount)),
          ),
        ],
      ),
    );
  }
}
