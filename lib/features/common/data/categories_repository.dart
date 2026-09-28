import '../../../core/models/common_models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';

/// Categories rarely change, so they're cached for the app session.
class CategoriesRepository {
  CategoriesRepository(this._api);

  final ApiClient _api;
  List<Category>? _cache;

  Future<List<Category>> getAll() async {
    if (_cache != null) return _cache!;
    final response = await _api.get('/categories', parser: (data) => J.listOf(data, Category.fromJson));
    return _cache = response.data;
  }
}
