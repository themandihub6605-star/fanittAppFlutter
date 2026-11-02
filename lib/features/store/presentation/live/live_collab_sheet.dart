// File: lib/features/store/presentation/live/live_collab_sheet.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../creators/data/creators_repository.dart';
import '../../../profile/data/profile_models.dart';
import '../../data/store_repository.dart';

/// Host: "Go live together" — invite up to 2 creators to a live (before it
/// starts or while it's running). They get a push and accept from the live
/// page; while it's running they join on screen right away.
Future<void> showLiveCollabSheet(BuildContext context, {required String liveId, required String liveTitle, String myUserId = ''}) =>
    showAppSheet<void>(context, builder: (_) => _LiveCollabSheet(liveId: liveId, liveTitle: liveTitle, myUserId: myUserId));

class _LiveCollabSheet extends StatefulWidget {
  const _LiveCollabSheet({required this.liveId, required this.liveTitle, required this.myUserId});

  final String liveId;
  final String liveTitle;
  final String myUserId;

  @override
  State<_LiveCollabSheet> createState() => _LiveCollabSheetState();
}

class _LiveCollabSheetState extends State<_LiveCollabSheet> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<LiveCollaborator> _invited = const [];
  int _max = 2;
  bool _loading = true;

  List<CreatorProfile> _results = const [];
  bool _searching = false;
  String? _busyUserId;

  StoreRepository get _repo => sl<StoreRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _repo.liveCollaborators(widget.liveId);
      if (!mounted) return;
      setState(() {
        _invited = r.items;
        _max = r.max;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppSnackbar.error(context, e.displayMessage);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final page = await sl<CreatorsRepository>().list(search: q);
        if (!mounted || _search.text.trim() != q) return;
        setState(() {
          _results = page.items.where((c) => c.userId.isNotEmpty && c.userId != widget.myUserId).take(15).toList();
          _searching = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  int get _activeCount => _invited.where((c) => c.status == 'invited' || c.status == 'accepted').length;

  LiveCollaborator? _entryOf(String userId) => _invited.where((c) => c.userId == userId).firstOrNull;

  Future<void> _invite(CreatorProfile c) async {
    HapticFeedback.selectionClick();
    setState(() => _busyUserId = c.userId);
    try {
      final r = await _repo.inviteCollaborator(widget.liveId, c.userId);
      if (!mounted) return;
      setState(() {
        _invited = r.items;
        _max = r.max;
      });
      AppSnackbar.success(context, 'Invite sent to ${c.name}');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _remove(LiveCollaborator c) async {
    final ok = await confirmAction(
      context,
      title: c.status == 'accepted' ? 'Remove ${c.name}?' : 'Cancel invite to ${c.name}?',
      message: c.status == 'accepted' ? 'If they’re on screen, they’ll be taken off the live.' : 'They won’t be able to join as co-host.',
      confirmLabel: c.status == 'accepted' ? 'Remove' : 'Cancel invite',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyUserId = c.userId);
    try {
      final r = await _repo.removeCollaborator(widget.liveId, c.userId);
      if (mounted) setState(() {
        _invited = r.items;
        _max = r.max;
      });
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.displayMessage);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final full = _activeCount >= _max;
    final shown = _invited.where((c) => c.status != 'removed').toList();

    return SheetBody(
      title: 'Go live together',
      subtitle: 'Invite up to $_max creators to “${widget.liveTitle}”. Their followers get told you’re live together.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator.adaptive()))
          else if (shown.isNotEmpty) ...[
            Text('Invited', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final c in shown)
              _PersonRow(
                name: c.name,
                avatarUrl: c.avatarUrl,
                subtitle: c.statusLabel,
                subtitleColor: c.status == 'accepted' ? AppColors.success : (c.status == 'declined' ? palette.textTertiary : palette.textSecondary),
                trailing: c.status == 'declined'
                    ? null
                    : _busyUserId == c.userId
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(tooltip: 'Remove', icon: Icon(AppIcons.close, size: 18, color: palette.textSecondary), onPressed: () => _remove(c)),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: _search,
            onChanged: _onSearch,
            enabled: !full,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: full ? 'You’ve invited the most creators for this live' : 'Search creators by name',
              prefixIcon: Icon(AppIcons.search, size: 20, color: palette.textSecondary),
              filled: true,
              fillColor: palette.surfaceMuted,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          if (_searching)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator.adaptive()))
          else if (_search.text.trim().length >= 2 && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No creators found', textAlign: TextAlign.center, style: context.text.bodySmall),
            )
          else
            for (final c in _results)
              Builder(builder: (context) {
                final entry = _entryOf(c.userId);
                final already = entry != null && (entry.status == 'invited' || entry.status == 'accepted');
                return _PersonRow(
                  name: c.name,
                  avatarUrl: c.avatarUrl ?? '',
                  subtitle: c.category?.label ?? (c.title.isEmpty ? 'Creator' : c.title),
                  trailing: _busyUserId == c.userId
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : already
                      ? Text(entry.statusLabel, style: TextStyle(color: palette.textTertiary, fontWeight: FontWeight.w700, fontSize: 12.5))
                      : FilledButton(
                    onPressed: full ? null : () => _invite(c),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16), visualDensity: VisualDensity.compact),
                    child: const Text('Invite', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                );
              }),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.name, required this.avatarUrl, required this.subtitle, this.subtitleColor, this.trailing});

  final String name;
  final String avatarUrl;
  final String subtitle;
  final Color? subtitleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UserAvatar(initials: name.isEmpty ? '?' : name[0].toUpperCase(), imageUrl: avatarUrl.isEmpty ? null : avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: subtitleColor ?? palette.textSecondary)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}