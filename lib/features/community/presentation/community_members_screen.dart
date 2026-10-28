// File: lib/features/community/presentation/community_members_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/paged_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';


/// Members, and for moderators: join requests and banned users.
/// The owner can also hand the community to someone else.
class CommunityMembersScreen extends StatelessWidget {
  const CommunityMembersScreen({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    final tabs = [
      (MembershipStatus.active, 'Members'),
      if (c.canModerate) (MembershipStatus.pending, c.pendingRequestCount > 0 ? 'Requests · ${c.pendingRequestCount}' : 'Requests'),
      if (c.canModerate) (MembershipStatus.banned, 'Banned'),
    ];
    final palette = context.palette;

    return DefaultTabController(
      length: tabs.length,
      initialIndex: c.canModerate && c.pendingRequestCount > 0 ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Members', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, fontSize: 18)),
              Text(
                '${c.name} · ${Fmt.compact(c.memberCount)} ${c.memberCount == 1 ? 'member' : 'members'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: palette.textSecondary),
              ),
            ],
          ),
          bottom: tabs.length == 1
              ? null
              : PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 2, AppSpacing.gutter, 12),
              child: Container(
                height: 42,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: BorderRadius.circular(99)),
                child: TabBar(
                  dividerHeight: 0,
                  indicatorSize: TabBarIndicatorSize.tab,
                  splashBorderRadius: BorderRadius.circular(99),
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFFFF8A4C)]),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: palette.textSecondary,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: [for (final t in tabs) Tab(height: 34, text: t.$2)],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) _MemberList(community: c, status: t.$1)]),
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
    HapticFeedback.selectionClick();
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

  Future<void> _makeOwner(CommunityMember member) async {
    final c = widget.community;
    final ok = await confirmAction(
      context,
      title: 'Make ${member.user.name} the owner?',
      message: 'They get full control of ${c.name}${c.isPaid ? ' and its future earnings' : ''}. You stay on as a moderator. This can only be undone by the new owner.',
      confirmLabel: 'Make owner',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = member.user.id);
    try {
      await sl<CommunityRepository>().transferOwnership(c.id, member.user.id);
      if (!mounted) return;
      AppSnackbar.success(context, '${member.user.name} now owns ${c.name}');
      // My role changed — go back so the community reloads.
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _menu(CommunityMember member) {
    final c = widget.community;
    final palette = context.palette;
    Widget item(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: (color ?? palette.textPrimary).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 18, color: color ?? palette.textPrimary),
      ),
      title: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color ?? palette.textPrimary)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
      onTap: onTap,
    );

    showAppSheet<void>(
      context,
      builder: (ctx) => SheetBody(
        title: member.user.name,
        subtitle: member.role.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.isOwner)
              member.role == CommunityRole.moderator
                  ? item(AppIcons.shieldCheck, 'Remove moderator', 'Back to a regular member', () {
                Navigator.pop(ctx);
                _act(member, MemberAction.removeModerator);
              })
                  : item(AppIcons.shieldCheck, 'Make moderator', 'Can approve, remove and pin posts', () {
                Navigator.pop(ctx);
                _act(member, MemberAction.makeModerator);
              }),
            if (c.isOwner)
              item(AppIcons.crown, 'Make owner', 'Hand over the community', () {
                Navigator.pop(ctx);
                _makeOwner(member);
              }),
            item(AppIcons.signOut, 'Remove from community', 'They can join again later', () {
              Navigator.pop(ctx);
              _act(member, MemberAction.remove);
            }),
            item(AppIcons.xCircle, 'Ban', 'Removed and can’t join again', () {
              Navigator.pop(ctx);
              _act(member, MemberAction.ban);
            }, color: AppColors.error),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = context.palette;
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : null;
    final c = widget.community;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.sm),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(99), border: Border.all(color: palette.border)),
            child: Row(
              children: [
                Icon(AppIcons.search, size: 18, color: palette.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) {
                      setState(() {});
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), _reload);
                    },
                    style: TextStyle(fontSize: 14, color: palette.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Search by name',
                      hintStyle: TextStyle(fontSize: 14, color: palette.textSecondary),
                    ),
                  ),
                ),
                if (_search.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _search.clear();
                      setState(() {});
                      _reload();
                    },
                    child: Icon(AppIcons.xCircle, size: 18, color: palette.textSecondary),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PagedListView<CommunityMember>(
            cubit: _cubit,
            spacing: 0,
            empty: MessageView(
              icon: switch (widget.status) {
                MembershipStatus.pending => AppIcons.userPlus,
                MembershipStatus.banned => AppIcons.shieldCheck,
                _ => AppIcons.users,
              },
              title: switch (widget.status) {
                MembershipStatus.pending => 'No pending requests',
                MembershipStatus.banned => 'Nobody is banned',
                _ => 'No members found',
              },
              message: switch (widget.status) {
                MembershipStatus.pending => 'New join requests show up here.',
                MembershipStatus.banned => 'People you ban show up here.',
                _ => 'Try another name.',
              },
            ),
            itemBuilder: (context, m) {
              final canAct = m.user.id != myId && m.role != CommunityRole.owner && c.canModerate && (c.isOwner || m.role == CommunityRole.member);
              return _MemberTile(
                member: m,
                status: widget.status,
                busy: _busyId == m.user.id,
                isMe: m.user.id == myId,
                canAct: canAct,
                onApprove: () => _act(m, MemberAction.approve),
                onReject: () => _act(m, MemberAction.reject),
                onUnban: () => _act(m, MemberAction.unban),
                onMenu: () => _menu(m),
              ).animate().fadeIn(duration: 220.ms).slideX(begin: 0.03);
            },
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.status,
    required this.busy,
    required this.isMe,
    required this.canAct,
    required this.onApprove,
    required this.onReject,
    required this.onUnban,
    required this.onMenu,
  });

  final CommunityMember member;
  final MembershipStatus status;
  final bool busy;
  final bool isMe;
  final bool canAct;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onUnban;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = member;
    final joined = m.joinedAt == null ? null : Fmt.relative(m.joinedAt!.toLocal());
    final sub = switch (status) {
      MembershipStatus.pending => joined == null ? 'Wants to join' : 'Asked $joined',
      MembershipStatus.banned => 'Banned',
      _ => [if (m.user.role != null) m.user.role!.label, if (joined != null) 'Joined $joined'].join(' · '),
    };

    Widget trailing;
    if (busy) {
      trailing = const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (status == MembershipStatus.pending) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(label: 'Decline', filled: false, onTap: onReject),
          const SizedBox(width: 6),
          _PillButton(label: 'Approve', filled: true, onTap: onApprove),
        ],
      );
    } else if (status == MembershipStatus.banned) {
      trailing = _PillButton(label: 'Unban', filled: false, onTap: onUnban);
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.role != CommunityRole.member) RoleChip(role: m.role),
          if (canAct)
            IconButton(
              tooltip: 'Manage',
              onPressed: onMenu,
              icon: Icon(AppIcons.dotsThree, color: palette.textSecondary),
            ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.border)),
      child: Row(
        children: [
          UserAvatar(initials: m.user.initials, imageUrl: m.user.avatarUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(m.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.textPrimary))),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Text('(you)', style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                    ],
                  ],
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          trailing,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.filled, required this.onTap});

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bg = filled ? AppColors.primary : Colors.transparent;
    final fg = filled ? Colors.white : palette.textPrimary;
    return Material(
      color: bg,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: palette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
        ),
      ),
    );
  }
}