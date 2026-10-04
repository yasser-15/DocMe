import 'dart:async';
import '../api/api_client.dart';
import '../failure.dart';
import '../models/auth_session.dart';

/// Sign-up and sign-in for Django backend.
class AuthRepository {
  AuthRepository({
    ApiClient? api,
    SessionStore? store,
  })  : _api = api ?? ApiClient(),
        _store = store ?? InMemorySessionStore();

  final ApiClient _api;
  final SessionStore _store;

  final StreamController<AuthSession?> _changes =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _session;

  Stream<AuthSession?> get changes => _changes.stream;
  AuthSession? get current => _session;
  bool get isSignedIn => _session != null;

  Future<AuthSession?> restore() async {
    final stored = await _store.read();
    if (stored == null) return null;
    _session = stored;
    _changes.add(_session);
    return _session;
  }

  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/api/auth/login/',
      body: {
        'email': email,
        'password': password,
      },
      mapper: (data) => data,
    );

    return result.when(
      ok: (data) {
        final session = AuthSession(
          userId: data['user_id']?.toString() ?? '',
          email: data['email']?.toString() ?? email,
          token: data['token']?.toString() ?? data['access']?.toString() ?? '',
          issuedAt: DateTime.now(),
        );
        _store.write(session);
        _session = session;
        _changes.add(session);
        return Ok(session);
      },
      err: (failure) => Err(failure),
    );
  }

  Future<Result<AuthSession>> signUp({
    required String email,
    required String password,
  }) async {
    final result = await _api.post<Map<String, dynamic>>(
      '/api/auth/register/',
      body: {
        'email': email,
        'password': password,
      },
      mapper: (data) => data,
    );

    return result.when(
      ok: (data) {
        final session = AuthSession(
          userId: data['user_id']?.toString() ?? '',
          email: data['email']?.toString() ?? email,
          token: data['token']?.toString() ?? data['access']?.toString() ?? '',
          issuedAt: DateTime.now(),
        );
        _store.write(session);
        _session = session;
        _changes.add(session);
        return Ok(session);
      },
      err: (failure) => Err(failure),
    );
  }

  Future<void> signOut() async {
    await _store.clear();
    _session = null;
    _changes.add(null);
  }
}
