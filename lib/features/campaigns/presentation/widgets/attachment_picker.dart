import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/media_picker.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/form_controls.dart';

/// Pick up to five images or documents to attach to a submission.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({super.key, required this.files, required this.onChanged, this.label = 'Files (optional)', this.max = 5});

  final List<PickedMedia> files;
  final ValueChanged<List<PickedMedia>> onChanged;
  final String label;
  final int max;

  Future<void> _pick() async {
    final picked = await sl<MediaPicker>().attachments(limit: max - files.length);
    if (picked.isNotEmpty) onChanged([...files, ...picked].take(max).toList());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, trailing: Text('${files.length}/$max', style: context.text.bodySmall)),
        for (final file in files)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(AppIcons.file, size: 18, color: palette.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(AppIcons.close, size: 18, color: palette.textSecondary),
                  onPressed: () => onChanged(files.where((f) => f != file).toList()),
                ),
              ],
            ),
          ),
        if (files.length < max)
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(AppIcons.paperclip, size: 18),
            label: const Text('Attach files'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: palette.textPrimary,
              side: BorderSide(color: palette.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
      ],
    );
  }
}
