import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';

/// Members, and for moderators: join requests and banned users.
class CommunityMembersScreen extends StatelessWidget {
  const CommunityMembersScreen({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (MembershipStatus.active, 'Members'),
      if (community.canModerate) (MembershipStatus.pending, 'Requests${community.pendingRequestCount > 0 ? ' (${community.pendingRequestCount})' : ''}'),
      if (community.canModerate) (MembershipStatus.banned, 'Banned'),
    ];
    final palette = context.palette;

    return DefaultTabController(
      length: tabs.length,
      initialIndex: community.canModerate && community.pendingRequestCount > 0 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Members'),
          bottom: tabs.length == 1
              ? null
              : TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: palette.textSecondary,
            labelStyle: context.text.labelLarge,
            indicatorColor: AppColors.primary,
            dividerColor: palette.border,
            tabs: [for (final t in tabs) Tab(text: t.$2)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) _MemberList(community: community, status: t.$1)]),
      ),
    );
  }
}

class _MemberList extends StatefulWidget {
  const _MemberList({required this.community, required this.status});

  final Community community;
  final MembershipStatus status;

  @override
  State<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<_MemberList> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  Timer? _debounce;
  late final PagedCubit<CommunityMember> _cubit = PagedCubit<CommunityMember>(
        (page) => sl<CommunityRepository>().members(widget.community.id, status: widget.status, page: page),
  );
  String? _busyId;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    _cubit.close();
    super.dispose();
  }

  void _reload() {
    final text = _search.text.trim();
    _cubit.updateQuery((page) => sl<CommunityRepository>().members(widget.community.id, status: widget.status, search: text, page: page));
  }

  Future<void> _act(CommunityMember member, MemberAction action) async {
    if (action == MemberAction.ban || action == MemberAction.remove) {
      final ok = await confirmAction(
        context,
        title: action == MemberAction.ban ? 'Ban ${member.user.name}?' : 'Remove ${member.user.name}?',
        message: action == MemberAction.ban ? 'They are removed and can’t join again.' : 'They can join again later.',
        confirmLabel: action == MemberAction.ban ? 'Ban' : 'Remove',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _busyId = member.user.id);
    try {
      await sl<CommunityRepository>().manageMember(widget.community.id, member.user.id, action);
      if (!mounted) return;
      if (action == MemberAction.makeModerator || action == MemberAction.removeModerator) {
        _cubit.updateItem(
              (m) => m.user.id == member.user.id,
              (m) => m.copyWith(role: action == MemberAction.makeModerator ? CommunityRole.moderator : CommunityRole.member),
        );
      } else {
        _cubit.removeItem((m) => m.user.id == member.user.id);
      }
      AppSnackbar.success(context, switch (action) {
        MemberAction.approve => '${member.user.name} is now a member',
        MemberAction.reject => 'Request declined',
        MemberAction.makeModerator => '${member.user.name} is now a moderator',
        MemberAction.removeModerator => 'Moderator removed',
        MemberAction.remove => 'Removed from the community',
        MemberAction.ban => '${member.user.name} is banned',
        MemberAction.unban => 'Unbanned',
      });
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _menu(CommunityMember member) {
    final c = widget.community;
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetBody(
        title: member.user.name,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.isOwner)
              member.role == CommunityRole.moderator
                  ? ListTile(
                leading: const Icon(AppIcons.shieldCheck),
                title: const Text('Remove moderator'),
                onTap: () { Navigator.pop(ctx); _act(member, MemberAction.removeModerator); },
              )
                  : ListTile(
                leading: const Icon(AppIcons.shieldCheck),
                title: const Text('Make moderator'),
                onTap: () { Navigator.pop(ctx); _act(member, MemberAction.makeModerator); },
              ),
            ListTile(
              leading: const Icon(AppIcons.signOut),
              title: const Text('Remove from community'),
              onTap: () { Navigator.pop(ctx); _act(member, MemberAction.remove); },
            ),
            ListTile(
              leading: const Icon(AppIcons.xCircle, color: AppColors.error),
              title: const Text('Ban', style: TextStyle(color: AppColors.error)),
              onTap: () { Navigator.pop(ctx); _act(member, MemberAction.ban); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final c = widget.community;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.xs),
          child: TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _reload);
            },
            decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Icon(AppIcons.search, size: 20)),
          ),
        ),
        Expanded(
          child: PagedListView<CommunityMember>(
            cubit: _cubit,
            empty: MessageView(
              icon: AppIcons.users,
              title: switch (widget.status) {
                MembershipStatus.pending => 'No pending requests',
                MembershipStatus.banned => 'Nobody is banned',
                _ => 'No members found',
              },
            ),
            itemBuilder: (context, m) {
              final canAct = m.user.id != myId && m.role != CommunityRole.owner && c.canModerate && (c.isOwner || m.role == CommunityRole.member);
              final busy = _busyId == m.user.id;
              return Row(
                children: [
                  UserAvatar(initials: m.user.initials, imageUrl: m.user.avatarUrl, size: 42),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.user.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                        if (m.user.role != null) Text(m.user.role!.label, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  RoleChip(role: m.role),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (widget.status == MembershipStatus.pending) ...[
                    IconButton(
                      tooltip: 'Approve',
                      onPressed: () => _act(m, MemberAction.approve),
                      icon: const Icon(AppIcons.checkCircle, color: AppColors.success),
                    ),
                    IconButton(
                      tooltip: 'Decline',
                      onPressed: () => _act(m, MemberAction.reject),
                      icon: const Icon(AppIcons.xCircle, color: AppColors.error),
                    ),
                  ] else if (widget.status == MembershipStatus.banned)
                    TextButton(onPressed: () => _act(m, MemberAction.unban), child: const Text('Unban'))
                  else if (canAct)
                      IconButton(tooltip: 'Manage', onPressed: () => _menu(m), icon: const Icon(AppIcons.dotsThree)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}