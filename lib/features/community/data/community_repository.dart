import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

class Community extends Equatable {
  const Community({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.memberCount,
    required this.createdBy,
    required this.isVerified,
    required this.isFeatured,
    this.category,
    this.coverImageUrl,
  });

  factory Community.fromJson(Map<String, dynamic> json) => Community(
        id: J.id(json),
        name: J.str(json, 'name'),
        slug: J.str(json, 'slug'),
        description: J.str(json, 'description'),
        memberCount: J.integer(json, 'memberCount'),
        createdBy: J.refId(json, 'createdBy') ?? '',
        isVerified: J.boolean(json, 'isVerified'),
        isFeatured: J.boolean(json, 'isFeatured'),
        category: Category.fromRef(json, 'category'),
        coverImageUrl: J.strOrNull(json, 'coverImageUrl'),
      );

  final String id;
  final String name;
  final String slug;
  final String description;
  final int memberCount;
  final String createdBy;
  final bool isVerified;
  final bool isFeatured;
  final Category? category;
  final String? coverImageUrl;

  Community withMembers(int count) => Community(
        id: id,
        name: name,
        slug: slug,
        description: description,
        memberCount: count,
        createdBy: createdBy,
        isVerified: isVerified,
        isFeatured: isFeatured,
        category: category,
        coverImageUrl: coverImageUrl,
      );

  @override
  List<Object?> get props => [id, memberCount];
}

class CommunityRepository {
  const CommunityRepository(this._api);

  final ApiClient _api;

  Future<Paged<Community>> list({String? search, int page = 1}) async => (await _api.get(
        '/communities',
        query: {'page': page, 'limit': 20, if (search != null && search.isNotEmpty) 'search': search},
        parser: (d) {
          final m = J.asMap(d);
          return Paged(
            items: J.list(m, 'communities', Community.fromJson),
            page: J.integer(m, 'page', 1),
            pages: J.integer(m, 'pages', 1),
            total: J.integer(m, 'total'),
          );
        },
      ))
          .data;

  Future<List<Community>> mine() async =>
      (await _api.get('/communities/me', parser: (d) => J.listOf(d, Community.fromJson))).data;

  Future<Community> create({required String name, String description = '', String? categoryId}) async => (await _api.post(
        '/communities',
        data: {'name': name, 'description': description, if (categoryId != null) 'category': categoryId},
        parser: (d) => Community.fromJson(J.asMap(d)),
      ))
          .data;

  Future<bool> toggleJoin(String id) async =>
      (await _api.post('/communities/$id/join', parser: (d) => J.boolean(J.asMap(d), 'joined'))).data;
}
