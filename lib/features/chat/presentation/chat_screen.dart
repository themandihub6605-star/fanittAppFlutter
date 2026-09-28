import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import 'chat_cubit.dart';

/// Header info passed when opening a chat, so it renders instantly.
class ChatArgs {
  const ChatArgs({required this.title, this.avatarUrl});

  final String title;
  final String? avatarUrl;
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.conversationId, this.args});

  final String conversationId;
  final ChatArgs? args;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    return BlocProvider(
      create: (_) => ChatCubit(
        conversationId: conversationId,
        myUserId: myId,
        repository: sl<ChatRepository>(),
        socket: sl<SocketService>(),
      ),
      child: _ChatView(args: args ?? const ChatArgs(title: 'Chat'), myUserId: myId),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView({required this.args, required this.myUserId});

  final ChatArgs args;
  final String myUserId;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    setState(() {});
    context.read<ChatCubit>().send(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final initials = widget.args.title.isEmpty ? '?' : widget.args.title.substring(0, 1).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(initials: initials, imageUrl: widget.args.avatarUrl, size: 36),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.args.title, style: context.text.titleMedium, overflow: TextOverflow.ellipsis),
                  BlocSelector<ChatCubit, ChatState, bool>(
                    selector: (s) => s.otherIsTyping,
                    builder: (context, typing) => AnimatedSwitcher(
                      duration: AppDurations.fast,
                      child: typing
                          ? Text('typing…', key: const ValueKey('typing'), style: context.text.bodySmall?.copyWith(color: AppColors.primary))
                          : const SizedBox.shrink(key: ValueKey('idle')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: BlocConsumer<ChatCubit, ChatState>(
        listenWhen: (p, c) => p.tick != c.tick,
        listener: (context, state) {
          if (state.sendError != null) AppSnackbar.error(context, state.sendError!);
        },
        builder: (context, state) {
          if (state.isLoading) return const LoadingView();
          if (state.errorMessage != null && state.messages.isEmpty) {
            return ErrorView(message: state.errorMessage!, onRetry: context.read<ChatCubit>().load);
          }
          final reversed = state.messages.reversed.toList();
          return Column(
            children: [
              Expanded(
                child: reversed.isEmpty
                    ? const MessageView(icon: AppIcons.messages, title: 'Say hello', message: 'Messages you send appear here.')
                    : ListView.builder(
                        reverse: true,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
                        itemCount: reversed.length,
                        itemBuilder: (context, index) {
                          final message = reversed[index];
                          final older = index + 1 < reversed.length ? reversed[index + 1] : null;
                          final showDay = older == null || !_sameDay(older.createdAt, message.createdAt);
                          return Column(
                            children: [
                              if (showDay) _DayLabel(date: message.createdAt),
                              _Bubble(message: message, mine: message.senderId == widget.myUserId),
                            ],
                          );
                        },
                      ),
              ),
              _Composer(
                controller: _input,
                onChanged: (text) {
                  setState(() {});
                  context.read<ChatCubit>().onTextChanged(text);
                },
                onSend: _send,
                palette: palette,
              ),
            ],
          );
        },
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(isToday ? 'Today' : Fmt.date(date), style: context.text.labelSmall),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : palette.surface,
        border: mine ? null : Border.all(color: palette.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.lg),
          topRight: const Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(mine ? AppRadius.lg : 4),
          bottomRight: Radius.circular(mine ? 4 : AppRadius.lg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            message.text,
            style: context.text.bodyLarge?.copyWith(fontSize: 15, color: mine ? Colors.white : palette.textPrimary),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.time(message.createdAt),
                style: context.text.labelSmall?.copyWith(fontSize: 10.5, color: mine ? Colors.white70 : palette.textTertiary),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(
                  message.isPending ? AppIcons.clock : (message.isRead ? AppIcons.checks : AppIcons.check),
                  size: 13,
                  color: Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: message.isPending ? bubble.animate().fadeIn(duration: 180.ms).slideY(begin: 0.2) : bubble,
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onChanged, required this.onSend, required this.palette});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(color: palette.surface, border: Border(top: BorderSide(color: palette.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Write a message',
                    counterText: '',
                    filled: true,
                    fillColor: palette.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.xl), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AnimatedScale(
                scale: canSend ? 1 : 0.85,
                duration: AppDurations.fast,
                child: IconButton.filled(
                  tooltip: 'Send',
                  onPressed: canSend ? onSend : null,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: palette.surfaceMuted,
                    fixedSize: const Size(46, 46),
                  ),
                  icon: Icon(AppIcons.send, color: canSend ? Colors.white : palette.textTertiary, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
