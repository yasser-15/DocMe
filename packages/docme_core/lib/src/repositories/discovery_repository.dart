import '../api/api_client.dart';
import '../failure.dart';
import '../models/auth_session.dart';

/// Discovery repository for Django backend.
class DiscoveryRepository {
  DiscoveryRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<Result<List<Map<String, dynamic>>>> search(
    AuthSession session, {
    String? query,
    String? category,
  }) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/api/providers/',
      queryParams: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (category != null && category.isNotEmpty) 'category': category,
      },
      token: session.token,
      mapper: (data) => data,
    );

    return result.when(
      ok: (data) {
        final results = data['results'] as List<dynamic>? ?? data['providers'] as List<dynamic>? ?? [];
        final list = results.map((e) => e as Map<String, dynamic>).toList();
        return Ok(list);
      },
      err: (failure) => Err(failure),
    );
  }
}
