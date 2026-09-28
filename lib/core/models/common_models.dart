import 'package:equatable/equatable.dart';

import '../enums/user_role.dart';
import '../utils/json.dart';

class Category extends Equatable {
  const Category({required this.id, required this.label, this.slug = ''});

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: J.id(json), label: J.str(json, 'label'), slug: J.str(json, 'slug'));

  /// Category fields arrive as an id or a populated object.
  static Category? fromRef(Map<String, dynamic> json, String key) {
    final populated = J.map(json, key);
    if (populated != null) return Category.fromJson(populated);
    final id = J.strOrNull(json, key);
    return id == null ? null : Category(id: id, label: '');
  }

  final String id;
  final String label;
  final String slug;

  @override
  List<Object?> get props => [id];
}

/// A minimal view of any user (chat participants, likes, reviewers).
class UserLite extends Equatable {
  const UserLite({required this.id, required this.name, this.avatarUrl, this.role});

  factory UserLite.fromJson(Map<String, dynamic> json) => UserLite(
        id: J.id(json),
        name: J.str(json, 'name', 'Fanitt user'),
        avatarUrl: J.strOrNull(json, 'avatarUrl'),
        role: json['role'] == null ? null : UserRole.fromValue(json['role'] as String?),
      );

  final String id;
  final String name;
  final String? avatarUrl;
  final UserRole? role;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  List<Object?> get props => [id, name, avatarUrl, role];
}

class Paged<T> {
  const Paged({required this.items, required this.page, required this.pages, required this.total});

  final List<T> items;
  final int page;
  final int pages;
  final int total;

  bool get hasMore => page < pages;
}

class Review extends Equatable {
  const Review({required this.id, required this.rating, required this.comment, required this.createdAt, this.from});

  factory Review.fromJson(Map<String, dynamic> json) {
    final from = J.map(json, 'fromUser');
    return Review(
      id: J.id(json),
      rating: J.integer(json, 'rating'),
      comment: J.str(json, 'comment'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      from: from == null ? null : UserLite.fromJson(from),
    );
  }

  final String id;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final UserLite? from;

  @override
  List<Object?> get props => [id];
}
