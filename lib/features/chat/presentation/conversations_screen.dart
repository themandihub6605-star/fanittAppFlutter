import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_cubit.dart';
import '../../../core/di/injection.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoadCubit<List<Conversation>>(sl<ChatRepository>().conversations),
      child: const _ConversationsView(),
    );
  }
}

class _ConversationsView extends StatelessWidget {
  const _ConversationsView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<LoadCubit<List<Conversation>>>();
    final auth = context.watch<AuthBloc>().state;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: AsyncView<List<Conversation>>(
        state: cubit.state,
        onRetry: cubit.load,
        builder: (conversations) => AppRefresh(
          onRefresh: cubit.refresh,
          child: conversations.isEmpty
              ? const ScrollableMessage(
                  child: MessageView(
                    icon: AppIcons.messages,
                    title: 'No conversations yet',
                    message: 'Chats with brands and creators start from a campaign proposal.',
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const Divider(indent: 84),
                  itemBuilder: (context, index) => _ConversationTile(conversation: conversations[index], myId: myId),
                ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.myId});

  final Conversation conversation;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final other = conversation.otherThan(myId);
    final unread = conversation.unreadCount > 0;

    return InkWell(
      onTap: () async {
        await context.push(
          AppRoutes.chat(conversation.id),
          extra: ChatArgs(title: other?.name ?? 'Chat', avatarUrl: other?.avatarUrl),
        );
        if (context.mounted) context.read<LoadCubit<List<Conversation>>>().refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.sm),
        child: Row(
          children: [
            UserAvatar(initials: other?.initials ?? '?', imageUrl: other?.avatarUrl, size: 52),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          other?.name ?? 'Conversation',
                          style: context.text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          Fmt.chatTimestamp(conversation.lastMessageAt!),
                          style: context.text.bodySmall?.copyWith(color: unread ? AppColors.primary : palette.textTertiary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage.isEmpty ? 'No messages yet' : conversation.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(color: unread ? palette.textPrimary : palette.textSecondary),
                        ),
                      ),
                      if (unread)
                        Container(
                          margin: const EdgeInsets.only(left: AppSpacing.xs),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: context.text.labelSmall?.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
