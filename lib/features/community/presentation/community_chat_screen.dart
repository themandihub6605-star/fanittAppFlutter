import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/community_repository.dart';
import 'widgets/community_widgets.dart';

/// Live group chat for community members.
class CommunityChatScreen extends StatefulWidget {
  const CommunityChatScreen({super.key, required this.community});

  final Community community;

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<CommunityChatMessage> _messages = []; // oldest → newest
  final SocketService _socket = sl<SocketService>();
  StreamSubscription<SocketEvent>? _events;
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _sending = false;
  String? _error;
  String? _typingName;

  String get _communityId => widget.community.id;
  CommunityRepository get _repo => sl<CommunityRepository>();

  String? get _myId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _socket.joinCommunity(_communityId);
    _events = _socket.events.listen(_onEvent);
    _scroll.addListener(() {
      // List is reversed: the top of the conversation is maxScrollExtent.
      if (_hasMore && !_loadingOlder && _scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _loadOlder();
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _typingTimer?.cancel();
    _socket.leaveCommunity(_communityId);
    _repo.markChatRead(_communityId).catchError((_) {});
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _repo.chat(_communityId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(res.messages);
        _hasMore = res.hasMore;
      });
      _repo.markChatRead(_communityId).catchError((_) {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.displayMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final res = await _repo.chat(_communityId, before: _messages.first.createdAt);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, res.messages);
        _hasMore = res.hasMore;
      });
    } on ApiException {
      // Keep what we have; scrolling up again retries.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _add(CommunityChatMessage message) {
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() => _messages.add(message));
  }

  void _onEvent(SocketEvent event) {
    if (event.data['communityId']?.toString() != _communityId || !mounted) return;
    switch (event.name) {
      case 'community_message':
        final raw = event.data['message'];
        if (raw is Map) {
          final message = CommunityChatMessage.fromJson(Map<String, dynamic>.from(raw));
          _add(message);
          if (message.sender.id != _myId) {
            setState(() => _typingName = null);
            _repo.markChatRead(_communityId).catchError((_) {});
          }
        }
      case 'community_message_removed':
        final id = event.data['messageId']?.toString();
        setState(() {
          final i = _messages.indexWhere((m) => m.id == id);
          if (i >= 0) _messages[i] = _messages[i].removed();
        });
      case 'community_typing':
        final userId = event.data['userId']?.toString();
        if (userId == null || userId == _myId) return;
        final match = _messages.where((m) => m.sender.id == userId);
        setState(() => _typingName = match.isEmpty ? 'Someone' : match.last.sender.name);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _typingName = null);
        });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    HapticFeedback.selectionClick();
    try {
      final ack = await _socket.emitWithAck('community_send', {'communityId': _communityId, 'text': text});
      final raw = ack?['message'];
      if (ack?['success'] == true && raw is Map) {
        _add(CommunityChatMessage.fromJson(Map<String, dynamic>.from(raw)));
      } else {
        _add(await _repo.sendChat(_communityId, text));
      }
    } on ApiException catch (error) {
      _input.text = text;
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onTyping(String _) {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _socket.communityTyping(_communityId);
    }
  }

  Future<void> _delete(CommunityChatMessage message) async {
    final ok = await confirmAction(context, title: 'Delete message?', message: 'It will be removed for everyone.', confirmLabel: 'Delete', destructive: true);
    if (!ok) return;
    try {
      await _repo.deleteChat(_communityId, message.id);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == message.id);
        if (i >= 0) _messages[i] = _messages[i].removed();
      });
    } on ApiException catch (error) {
      if (mounted) AppSnackbar.error(context, error.displayMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final myId = _myId;
    final reversed = _messages.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CommunityIcon(name: widget.community.name, url: widget.community.iconUrl, size: 34),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.community.name, style: context.text.titleSmall, overflow: TextOverflow.ellipsis),
                  Text(
                    _typingName != null ? '$_typingName is typing…' : '${Fmt.compact(widget.community.memberCount)} members',
                    style: context.text.bodySmall?.copyWith(color: _typingName != null ? AppColors.primary : null),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null && _messages.isEmpty
                ? ErrorView(message: _error!, onRetry: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            })
                : _messages.isEmpty
                ? const MessageView(icon: AppIcons.messages, title: 'No messages yet', message: 'Say hello to the community!')
                : ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              itemCount: reversed.length + (_loadingOlder ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == reversed.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  );
                }
                final m = reversed[i];
                final older = i + 1 < reversed.length ? reversed[i + 1] : null;
                final grouped = older != null && older.sender.id == m.sender.id;
                final mine = m.sender.id == myId;
                final canDelete = !m.isRemoved && (mine || widget.community.canModerate);
                return _Bubble(
                  message: m,
                  mine: mine,
                  grouped: grouped,
                  onLongPress: canDelete ? () => _delete(m) : null,
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: _onTyping,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message the community…', counterText: ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.send, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.grouped, this.onLongPress});

  final CommunityChatMessage message;
  final bool mine;
  final bool grouped;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final m = message;
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: m.isRemoved ? Colors.transparent : (mine ? AppColors.primary : palette.surfaceMuted),
          border: m.isRemoved ? Border.all(color: palette.border) : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && !grouped && !m.isRemoved)
              Text(m.sender.name, style: context.text.labelSmall?.copyWith(color: AppColors.primary)),
            Text(
              m.isRemoved ? 'Message removed' : m.text,
              style: context.text.bodyMedium?.copyWith(
                color: m.isRemoved ? palette.textTertiary : (mine ? Colors.white : palette.textPrimary),
                fontStyle: m.isRemoved ? FontStyle.italic : null,
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                Fmt.time(m.createdAt),
                style: TextStyle(fontSize: 10, color: mine && !m.isRemoved ? Colors.white70 : palette.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : AppSpacing.sm),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            grouped ? const SizedBox(width: 30) : UserAvatar(initials: m.sender.initials, imageUrl: m.sender.avatarUrl, size: 30),
            const SizedBox(width: AppSpacing.xs),
          ],
          bubble,
        ],
      ),
    );
  }
}