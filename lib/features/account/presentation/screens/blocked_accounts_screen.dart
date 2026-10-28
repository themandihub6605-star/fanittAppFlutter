// File: lib/features/account/presentation/screens/blocked_accounts_screen.dart
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json.dart';
import '../../../../core/widgets/async_view.dart';
import '../../../../core/widgets/report_sheet.dart';
import '../../../../core/widgets/user_avatar.dart';

class _BlockedAccount {
  const _BlockedAccount({required this.userId, required this.name, this.avatarUrl, this.role, this.blockedAt});

  factory _BlockedAccount.fromJson(Map<String, dynamic> j) => _BlockedAccount(
    userId: J.str(j, 'userId'),
    name: J.str(j, 'name', 'Fanitt user'),
    avatarUrl: J.strOrNull(j, 'avatarUrl'),
    role: J.strOrNull(j, 'role'),
    blockedAt: J.date(j, 'blockedAt'),
  );

  final String userId;
  final String name;
  final String? avatarUrl;
  final String? role;
  final DateTime? blockedAt;
}

/// Account → Blocked accounts. Lists everyone you blocked, with Unblock.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BlockedAccountsScreen()));

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  List<_BlockedAccount>? _items;
  String? _error;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = (await sl<ApiClient>().get('/blocks', parser: (d) => J.listOf(d, _BlockedAccount.fromJson))).data;
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    }
  }

  Future<void> _unblock(_BlockedAccount a) async {
    setState(() => _busy.add(a.userId));
    final ok = await unblockUser(context, userId: a.userId, name: a.name);
    if (!mounted) return;
    setState(() {
      _busy.remove(a.userId);
      if (ok) _items = _items?.where((x) => x.userId != a.userId).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: _error != null && items == null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
          ? const LoadingView()
          : RefreshIndicator(
        onRefresh: _load,
        child: items.isEmpty
            ? const ScrollableMessage(
          child: MessageView(
            icon: AppIcons.users,
            title: 'No blocked accounts',
            message: 'When you block someone from their profile, a post or a chat, they show up here.',
          ),
        )
            : ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xxl),
          itemCount: items.length + 1,
          separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: AppSpacing.sm) : Divider(height: 1, color: palette.border.withValues(alpha: 0.7)),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Text(
                'They can’t message or follow you, and you don’t see each other’s posts. They aren’t told when you block or unblock them.',
                style: context.text.bodySmall?.copyWith(color: palette.textSecondary, height: 1.4),
              );
            }
            final a = items[i - 1];
            final busy = _busy.contains(a.userId);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  UserAvatar(initials: a.name.isEmpty ? '?' : a.name[0].toUpperCase(), imageUrl: a.avatarUrl, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        if (a.blockedAt != null)
                          Text('Blocked ${Fmt.relative(a.blockedAt!)}', style: context.text.bodySmall?.copyWith(color: palette.textTertiary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: busy ? null : () => _unblock(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}