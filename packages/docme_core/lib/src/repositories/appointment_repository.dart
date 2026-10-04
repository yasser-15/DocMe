import '../api/api_client.dart';
import '../failure.dart';
import '../models/auth_session.dart';

/// Appointment repository for Django backend.
class AppointmentRepository {
  AppointmentRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<Result<List<Map<String, dynamic>>>> list(
    AuthSession session, {
    bool upcoming = false,
  }) async {
    final result = await _api.get<Map<String, dynamic>>(
      '/api/appointments/',
      queryParams: upcoming ? {'upcoming': 'true'} : null,
      token: session.token,
      mapper: (data) => data,
    );

    return result.when(
      ok: (data) {
        final results = data['results'] as List<dynamic>? ?? [];
        final list = results.map((e) => e as Map<String, dynamic>).toList();
        return Ok(list);
      },
      err: (failure) => Err(failure),
    );
  }
}
