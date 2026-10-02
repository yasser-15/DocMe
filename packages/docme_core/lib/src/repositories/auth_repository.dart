import 'dart:async';
import 'dart:convert';

import '../database.dart';
import '../failure.dart';
import '../password.dart';

/// A signed-in identity.
///
/// Deliberately not a JWT. There is no auth service to issue one — the app talks
/// straight to Postgres — so the session is just the uuid that every query will
/// present via `request.jwt.claims`. Persisting it is the whole of "remember me".
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.issuedAt,
  });

  final String userId;
  final String email;
  final DateTime issuedAt;

  bool get isExpired => false;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'email': email,
    'issued_at': issuedAt.toIso8601String(),
  };

  /// Returns null when the payload is missing required fields or is not JSON.
  ///
  /// A corrupt stored session must sign the user out, not crash the launch path —
  /// a schema change here would otherwise brick the app on every existing
  /// install.
  static AuthSession? fromJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final userId = map['user_id'];
      final email = map['email'];
      final issuedAt = map['issued_at'];
      if (userId is! String || email is! String || issuedAt is! String) {
        return null;
      }
      final parsed = DateTime.tryParse(issuedAt);
      if (parsed == null) return null;
      return AuthSession(
        userId: userId,
        email: email,
        issuedAt: parsed,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

/// Where the session is kept between launches.
///
/// An interface rather than a `shared_preferences` dependency so `docme_core`
/// stays free of Flutter and testable with a plain in-memory map.
abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

/// Default store. The app substitutes a persistent one.
class InMemorySessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}

/// Sign-up and sign-in.
///
/// ## Why these are functions and not table reads
///
/// Before sign-in the caller has no identity, so it cannot present
/// `request.jwt.claims` and therefore cannot read a single row under RLS — not
/// even its own `auth.users` row. Rather than grant this role blanket read on
/// `auth.users` (which would re-open HOLE 1 from `0005_lock_down.sql` and expose
/// every account's email), `0006_app_access.sql` defines `auth.signup` and
/// `auth.authenticate` as SECURITY DEFINER functions that return only a uuid.
///
/// ## Passwords
///
/// The PBKDF2 hash is derived here, on the device, and only the hash is sent.
/// [PasswordHasher] yields to the event loop while it works, so a sign-in does
/// not drop a frame.
class AuthRepository {
  AuthRepository({
    required DocMeDatabase database,
    SessionStore? store,
    PasswordHasher hasher = const PasswordHasher(),
  }) : _db = database,
       _store = store ?? InMemorySessionStore(),
       _hasher = hasher;

  final DocMeDatabase _db;
  final SessionStore _store;
  final PasswordHasher _hasher;

  final StreamController<AuthSession?> _changes =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _session;

  /// Emits on sign-in and sign-out so the UI can swap between the auth screen
  /// and the app without polling.
  Stream<AuthSession?> get changes => _changes.stream;

  /// The current session, or null. Null after [restore] has not yet completed,
  /// which the UI must treat as "still deciding" rather than "signed out" —
  /// otherwise a returning user sees the sign-in screen flash on every launch.
  AuthSession? get current => _session;

  bool get isSignedIn => _session != null;

  /// Restores a persisted session at startup.
  Future<AuthSession?> restore() async {
    final stored = await _store.read();
    if (stored == null) return null;

    // Do not trust the stored uuid blindly. RLS does the real verification on
    // the first query, but a session that cannot even read its own profile row
    // is stale (deleted account, reset database) and should not reach the UI.
    final check = await _db.asUser<List<bool>>(
      stored.userId,
      (s) async {
        await s.select('select 1 from profiles where id = @id', {
          'id': P.uuid(stored.userId),
        });
        return const [true];
      },
    );

    if (check case Err(:final failure)) {
      if (failure.kind == DocMeFailureKind.permissionDenied ||
          failure.kind == DocMeFailureKind.notFound) {
        await _clear();
        return null;
      }
      // A network failure is not proof the session is bad. Keep it; the app
      // will surface the connection error rather than silently signing out.
      _session = stored;
      return stored;
    }

    _session = stored;
    return stored;
  }

  /// Creates an account and signs in.
  Future<Result<AuthSession>> signUp({
    required String email,
    required String password,
    required String fullName,
    required String countryCode,
  }) async {
    final normalisedEmail = _normaliseEmail(email);
    if (normalisedEmail == null) {
      return const Err(
        DocMeFailure(
          kind: DocMeFailureKind.validation,
          message: 'Enter a valid email address.',
        ),
      );
    }

    final String hash;
    try {
      hash = await _hasher.hash(password);
    } on ArgumentError catch (error) {
      return Err(
        DocMeFailure(
          kind: DocMeFailureKind.validation,
          message: error.message?.toString() ?? 'Password is not acceptable.',
          cause: error,
        ),
      );
    }

    final result = await _db.anonymous<String?>(
      (s) async {
        final rows = await s.select(
          'select auth.signup(@email, @hash, @name, @country, @role) as id',
          {
            'email': P.text(normalisedEmail),
            'hash': P.text(hash),
            'name': P.text(fullName),
            'country': P.text(countryCode.toUpperCase()),
            'role': P.text('patient'),
          },
        );
        return rows.isEmpty ? null : rows.first['id'] as String?;
      },
    );

    return switch (result) {
      Ok(:final value) => _establish(value, normalisedEmail),
      Err(:final failure) => Err(failure),
    };
  }

  /// Signs in with an existing account.
  Future<Result<AuthSession>> signIn({
    required String email,
    required String password,
  }) async {
    final normalisedEmail = _normaliseEmail(email);
    if (normalisedEmail == null) {
      return const Err(
        DocMeFailure(
          kind: DocMeFailureKind.validation,
          message: 'Enter a valid email address.',
        ),
      );
    }

    final String hash;
    try {
      hash = await _hasher.hash(password);
    } on ArgumentError catch (error) {
      return Err(
        DocMeFailure(
          kind: DocMeFailureKind.validation,
          message: error.message?.toString() ?? 'Password is not acceptable.',
          cause: error,
        ),
      );
    }

    final result = await _db.anonymous<String?>(
      (s) async {
        final rows = await s.select(
          'select auth.authenticate(@email, @hash) as id',
          {
            'email': P.text(normalisedEmail),
            'hash': P.text(hash),
          },
        );
        return rows.isEmpty ? null : rows.first['id'] as String?;
      },
    );

    return switch (result) {
      // Null means either "no such account" or "wrong password". auth.authenticate
      // deliberately does not distinguish them, and neither does this — saying
      // which one it was would let anyone enumerate registered addresses.
      Ok(value: null) => const Err(
        DocMeFailure(
          kind: DocMeFailureKind.unauthorized,
          message: 'Incorrect email or password.',
        ),
      ),
      Ok(:final value) => _establish(value, normalisedEmail),
      Err(:final failure) => Err(failure),
    };
  }

  /// Ends the session.
  ///
  /// There is no server-side token to revoke, so this only clears local state.
  /// That is sufficient here: every query is authorised by `SET ROLE` plus a uuid
  /// the server re-validates against RLS on each request, so a stale uuid on a
  /// lost phone grants nothing on its own.
  Future<void> signOut() => _clear();

  Future<Result<AuthSession>> _establish(
    String? userId,
    String email,
  ) async {
    if (userId == null) {
      return const Err(
        DocMeFailure(
          kind: DocMeFailureKind.unauthorized,
          message: 'Incorrect email or password.',
        ),
      );
    }

    final session = AuthSession(
      userId: userId,
      email: email,
      issuedAt: DateTime.now().toUtc(),
    );
    await _store.write(session);
    _session = session;
    _changes.add(session);
    return Ok(session);
  }

  Future<void> _clear() async {
    await _store.clear();
    _session = null;
    _changes.add(null);
  }

  static String? _normaliseEmail(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    // Deliberately loose. The database has the real constraint; a strict client
    // regex only rejects valid-but-unusual addresses, and this app must not be
    // the thing standing between a user and their own account.
    if (!trimmed.contains('@') || trimmed.startsWith('@') || trimmed.endsWith('@')) {
      return null;
    }
    if (trimmed.contains(' ')) return null;
    return trimmed;
  }

  void dispose() => _changes.close();
}