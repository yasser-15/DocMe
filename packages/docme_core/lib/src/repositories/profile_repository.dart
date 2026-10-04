import '../api/api_client.dart';
import '../failure.dart';
import '../models/auth_session.dart';

/// Profile repository for Django backend.
class ProfileRepository {
  ProfileRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<Result<Map<String, dynamic>>> load(AuthSession session) async {
    return _api.get<Map<String, dynamic>>(
      '/api/profile/',
      token: session.token,
      mapper: (data) => data,
    );
  }
}
