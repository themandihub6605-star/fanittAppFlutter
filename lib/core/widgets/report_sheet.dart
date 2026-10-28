// File: lib/core/widgets/report_sheet.dart
// Report + Block: the safety actions used on posts, comments, chats and profiles.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../di/injection.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../utils/json.dart';
import 'app_button.dart';
import 'app_sheet.dart';
import 'app_snackbar.dart';

/// What is being reported. [api] matches the backend's targetType.
enum ReportType {
  post('post', 'post'),
  story('story', 'story'),
  user('user', 'account'),
  community('community', 'community'),
  communityPost('community_post', 'post'),
  communityComment('community_comment', 'comment'),
  communityMessage('community_message', 'message'),
  message('message', 'message');

  const ReportType(this.api, this.noun);
  final String api;
  final String noun;
}

/// Reasons shown in the sheet (keys match the backend).
const _reasons = <(String, String)>[
  ('spam', 'Spam'),
  ('nudity', 'Nudity or sexual content'),
  ('hate', 'Hate or harassment'),
  ('violence', 'Violence or dangerous acts'),
  ('scam', 'Scam or fraud'),
  ('fake', 'Fake account or impersonation'),
  ('copyright', 'Copyright'),
  ('other', 'Something else'),
];

/// Things this user has reported. Screens hide them right away
/// (listen to [ReportedItems.instance] and check [has]).
class ReportedItems extends ValueNotifier<Set<String>> {
  ReportedItems._() : super(<String>{});
  static final ReportedItems instance = ReportedItems._();

  bool _loaded = false;
  bool _loading = false;
  String? _userId;

  static String _key(String type, String id) => '$type:$id';

  bool has(ReportType type, String id) => value.contains(_key(type.api, id));

  void _add(ReportType type, String id) => value = {...value, _key(type.api, id)};

  /// Loads the list once per account (safe to call often). Pass the signed-in
  /// user's id so switching accounts starts clean.
  Future<void> ensureLoaded({String? userId}) async {
    if (userId != null && userId != _userId) {
      _userId = userId;
      clear();
    }
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final rows = (await sl<ApiClient>().get('/reports/mine', parser: (d) => J.listOf(d, (m) => _key(J.str(m, 'targetType'), J.str(m, 'targetId'))))).data;
      value = {...value, ...rows};
      _loaded = true;
    } catch (_) {
      // Not logged in / offline — try again next time.
    } finally {
      _loading = false;
    }
  }

  /// Call on logout so the next account starts clean.
  void clear() {
    _loaded = false;
    value = <String>{};
  }
}

/// People this user blocked, and everyone hidden from them (blocked either
/// way). Screens listen to [BlockedUsers.instance] and hide their content.
class BlockedUsers extends ValueNotifier<Set<String>> {
  BlockedUsers._() : super(<String>{});
  static final BlockedUsers instance = BlockedUsers._();

  /// Only the ones I blocked (I can unblock these).
  final Set<String> _byMe = <String>{};
  bool _loaded = false;
  bool _loading = false;
  String? _userId;

  bool isHidden(String? userId) => userId != null && userId.isNotEmpty && value.contains(userId);
  bool blockedByMe(String? userId) => userId != null && _byMe.contains(userId);

  Future<void> ensureLoaded({String? userId}) async {
    if (userId != null && userId != _userId) {
      _userId = userId;
      clear();
    }
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final data = (await sl<ApiClient>().get('/blocks/ids', parser: (d) => J.asMap(d))).data;
      _byMe
        ..clear()
        ..addAll(J.strings(data, 'blocked'));
      value = {...J.strings(data, 'hidden'), ..._byMe};
      _loaded = true;
    } catch (_) {
      // Not logged in / offline — try again next time.
    } finally {
      _loading = false;
    }
  }

  void clear() {
    _loaded = false;
    _byMe.clear();
    value = <String>{};
  }

  void _set(String userId, bool blocked) {
    if (blocked) {
      _byMe.add(userId);
      value = {...value, userId};
    } else {
      _byMe.remove(userId);
      value = {...value}..remove(userId);
    }
  }
}

/// Asks first, then blocks. Returns true when blocked.
Future<bool> confirmBlock(BuildContext context, {required String userId, String? name}) async {
  final who = (name == null || name.trim().isEmpty) ? 'this account' : name.trim();
  final ok = await confirmAction(
    context,
    title: 'Block $who?',
    message: 'They won’t be able to message you, follow you or see your posts, and you won’t see theirs. They won’t be told you blocked them.',
    confirmLabel: 'Block',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await sl<ApiClient>().post('/blocks/$userId', parser: (_) => null);
    BlockedUsers.instance._set(userId, true);
    HapticFeedback.mediumImpact();
    if (context.mounted) AppSnackbar.success(context, '$who blocked');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppSnackbar.error(context, e.displayMessage);
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, 'Something went wrong. Please try again.');
  }
  return false;
}

/// Unblocks straight away (no question). Returns true when done.
Future<bool> unblockUser(BuildContext context, {required String userId, String? name}) async {
  try {
    await sl<ApiClient>().delete('/blocks/$userId', parser: (_) => null);
    BlockedUsers.instance._set(userId, false);
    if (context.mounted) AppSnackbar.success(context, '${(name == null || name.isEmpty) ? 'Account' : name} unblocked');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppSnackbar.error(context, e.displayMessage);
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, 'Something went wrong. Please try again.');
  }
  return false;
}

/// ⋮ menu for someone else's content: Report, and Block / Unblock the person
/// when [userId] is given. Returns 'reported', 'blocked', 'unblocked' or null.
Future<String?> showContentActions(BuildContext context, {required ReportType type, required String id, String? name, String? userId}) async {
  HapticFeedback.selectionClick();
  final canBlock = userId != null && userId.isNotEmpty;
  final isBlocked = canBlock && BlockedUsers.instance.blockedByMe(userId);
  final who = (name == null || name.trim().isEmpty) ? 'account' : name.trim();
  final choice = await showAppSheet<String>(
    context,
    builder: (ctx) => SafeArea(
      child: Padding(
        // The theme already draws the drag handle on top.
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const Icon(AppIcons.warning, color: AppColors.error),
              title: Text('Report ${type.noun}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
              subtitle: Text(name == null ? 'Tell us what’s wrong' : 'Tell us what’s wrong with ${name.trim()}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(ctx).pop('report'),
            ),
            if (canBlock)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: Icon(isBlocked ? PhosphorIconsRegular.userCircleCheck : PhosphorIconsRegular.prohibit, color: AppColors.error),
                title: Text(isBlocked ? 'Unblock $who' : 'Block $who', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                subtitle: Text(isBlocked ? 'See each other’s posts and messages again' : 'They can’t message or follow you, and you won’t see their posts'),
                onTap: () => Navigator.of(ctx).pop(isBlocked ? 'unblock' : 'block'),
              ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return null;
  switch (choice) {
    case 'report':
      return await showReportSheet(context, type: type, id: id) ? 'reported' : null;
    case 'block':
      return await confirmBlock(context, userId: userId!, name: name) ? 'blocked' : null;
    case 'unblock':
      return await unblockUser(context, userId: userId!, name: name) ? 'unblocked' : null;
  }
  return null;
}

/// Opens the report form. Returns true when the report was sent.
Future<bool> showReportSheet(BuildContext context, {required ReportType type, required String id}) async {
  final sent = await showAppSheet<bool>(context, builder: (_) => _ReportSheet(type: type, id: id));
  return sent ?? false;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.type, required this.id});

  final ReportType type;
  final String id;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _canSend => _reason != null && !(_reason == 'other' && _details.text.trim().isEmpty);

  Future<void> _send() async {
    if (!_canSend || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await sl<ApiClient>().post(
        '/reports',
        data: {'targetType': widget.type.api, 'targetId': widget.id, 'reason': _reason, 'details': _details.text.trim()},
        parser: (d) => J.boolean(J.asMap(d), 'alreadyReported'),
      );
      ReportedItems.instance._add(widget.type, widget.id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
      AppSnackbar.success(context, res.data ? 'You already reported this. We’re on it.' : 'Thanks for reporting. We’ll review it within 24 hours.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SheetBody(
      title: 'Report ${widget.type.noun}',
      subtitle: 'Your report is private. The person won’t know it was you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label) in _reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _reason == key ? AppColors.primary.withValues(alpha: 0.08) : palette.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: _reason == key ? AppColors.primary : palette.border, width: _reason == key ? 1.4 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _sending
                      ? null
                      : () {
                    HapticFeedback.selectionClick();
                    setState(() => _reason = key);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(child: Text(label, style: TextStyle(fontSize: 14.5, fontWeight: _reason == key ? FontWeight.w700 : FontWeight.w500, color: palette.textPrimary))),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _reason == key ? AppColors.primary : palette.border, width: _reason == key ? 6 : 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _details,
            enabled: !_sending,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _reason == 'other' ? 'Tell us what’s wrong (required)' : 'Add details (optional)',
              filled: true,
              fillColor: palette.surfaceMuted,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Submit report', onPressed: _canSend ? _send : null, isLoading: _sending),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'If someone is in immediate danger, contact local emergency services.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(color: palette.textTertiary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a profile when the two accounts are blocked.
class BlockedProfileNotice extends StatelessWidget {
  const BlockedProfileNotice({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final mine = BlockedUsers.instance.blockedByMe(userId);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surfaceMuted),
              child: Icon(PhosphorIconsRegular.prohibit, size: 32, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              mine ? 'You blocked $name' : 'This account isn’t available',
              textAlign: TextAlign.center,
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              mine ? 'You won’t see their posts and they can’t message or follow you.' : 'You can’t see this profile right now.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            if (mine) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton.secondary(label: 'Unblock', expand: false, onPressed: () => unblockUser(context, userId: userId, name: name)),
            ],
          ],
        ),
      ),
    );
  }
}