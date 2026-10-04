import 'dart:async';
import 'dart:convert';

/// A signed-in identity.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.token,
    required this.issuedAt,
  });

  final String userId;
  final String email;
  final String token;
  final DateTime issuedAt;

  bool get isExpired => false;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'email': email,
        'token': token,
        'issued_at': issuedAt.toIso8601String(),
      };

  static AuthSession? fromJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final userId = map['user_id'];
      final email = map['email'];
      final token = map['token'];
      final issuedAt = map['issued_at'];
      if (userId is! String || email is! String || token is! String || issuedAt is! String) {
        return null;
      }
      final parsed = DateTime.tryParse(issuedAt);
      if (parsed == null) return null;
      return AuthSession(
        userId: userId,
        email: email,
        token: token,
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
abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

/// Default store.
class InMemorySessionStore implements SessionStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
