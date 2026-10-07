import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.from,
    this.relatedModel,
    this.relatedId,
    this.imageUrl,
    this.link,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final from = J.map(json, 'fromUser');
    return AppNotification(
      id: J.id(json),
      type: J.str(json, 'type', 'general'),
      title: J.str(json, 'title'),
      message: J.str(json, 'message'),
      isRead: J.boolean(json, 'isRead'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      from: from == null ? null : UserLite.fromJson(from),
      relatedModel: J.strOrNull(json, 'relatedModel'),
      relatedId: J.refId(json, 'relatedId'),
      imageUrl: J.strOrNull(json, 'imageUrl'),
      link: J.strOrNull(json, 'link'),
    );
  }

  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final UserLite? from;
  final String? relatedModel;
  final String? relatedId;

  /// Admin broadcasts: optional picture and tap-through link.
  final String? imageUrl;
  final String? link;

  AppNotification markRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    isRead: true,
    createdAt: createdAt,
    from: from,
    relatedModel: relatedModel,
    relatedId: relatedId,
    imageUrl: imageUrl,
    link: link,
  );

  @override
  List<Object?> get props => [id, isRead];
}

class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});

  final List<AppNotification> items;
  final int unreadCount;
}

class NotificationRepository {
  const NotificationRepository(this._api);

  final ApiClient _api;

  Future<NotificationFeed> feed() async => (await _api.get('/notifications/me', parser: (d) {
    final m = J.asMap(d);
    return NotificationFeed(
      items: J.list(m, 'notifications', AppNotification.fromJson),
      unreadCount: J.integer(m, 'unreadCount'),
    );
  }))
      .data;

  Future<void> markRead(String id) async {
    await _api.patch('/notifications/$id/read', parser: (_) => null);
  }

  Future<void> markAllRead() async {
    await _api.patch('/notifications/read-all', parser: (_) => null);
  }
}