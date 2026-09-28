import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'chat_models.dart';

class ChatRepository {
  const ChatRepository(this._api);

  final ApiClient _api;

  Future<List<Conversation>> conversations() async => (await _api.get(
        '/chat/conversations',
        parser: (d) => J.listOf(d, Conversation.fromJson),
      ))
          .data;

  /// Also marks the thread as read on the server.
  Future<List<ChatMessage>> messages(String conversationId) async => (await _api.get(
        '/chat/conversations/$conversationId/messages',
        parser: (d) => J.listOf(d, ChatMessage.fromJson),
      ))
          .data;

  Future<ChatMessage> send(String conversationId, String text) async => (await _api.post(
        '/chat/conversations/$conversationId/messages',
        data: {'text': text},
        parser: (d) => ChatMessage.fromJson(J.asMap(d)),
      ))
          .data;

  /// Brand only — opens (or reuses) the thread for a proposal.
  Future<Conversation> startForApplication(String applicationId) async => (await _api.post(
        '/chat/applications/$applicationId/start',
        parser: (d) => Conversation.fromJson(J.asMap(d)),
      ))
          .data;

  /// Null until the brand has started the conversation.
  Future<Conversation?> forApplication(String applicationId) async => (await _api.get(
        '/chat/applications/$applicationId',
        parser: (d) => d is Map<String, dynamic> ? Conversation.fromJson(d) : null,
      ))
          .data;
}
