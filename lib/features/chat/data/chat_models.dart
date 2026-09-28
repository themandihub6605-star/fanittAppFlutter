import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/utils/json.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.unreadCount,
    this.lastMessageAt,
    this.campaignId,
    this.applicationId,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: J.id(json),
        participants: J.list(json, 'participants', UserLite.fromJson),
        lastMessage: J.str(json, 'lastMessage'),
        lastMessageAt: J.date(json, 'lastMessageAt'),
        unreadCount: J.integer(json, 'unreadCount'),
        campaignId: J.refId(json, 'campaign'),
        applicationId: J.refId(json, 'application'),
      );

  final String id;
  final List<UserLite> participants;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? campaignId;
  final String? applicationId;

  UserLite? otherThan(String myUserId) {
    for (final p in participants) {
      if (p.id != myUserId) return p;
    }
    return participants.isEmpty ? null : participants.first;
  }

  Conversation copyWith({String? lastMessage, DateTime? lastMessageAt, int? unreadCount}) => Conversation(
        id: id,
        participants: participants,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        unreadCount: unreadCount ?? this.unreadCount,
        campaignId: campaignId,
        applicationId: applicationId,
      );

  @override
  List<Object?> get props => [id, lastMessage, lastMessageAt, unreadCount, participants];
}

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.isRead = false,
    this.isPending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: J.id(json),
        senderId: J.refId(json, 'sender') ?? '',
        text: J.str(json, 'text'),
        createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
        isRead: J.boolean(json, 'isRead'),
      );

  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool isRead;

  /// Sent from this device and not yet confirmed by the server.
  final bool isPending;

  ChatMessage copyWith({bool? isRead}) =>
      ChatMessage(id: id, senderId: senderId, text: text, createdAt: createdAt, isRead: isRead ?? this.isRead, isPending: isPending);

  @override
  List<Object?> get props => [id, isRead, isPending];
}
