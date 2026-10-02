import 'package:docme_core/docme_core.dart';
import 'package:test/test.dart';

void main() {
  group('initialsOf', () {
    test('skips a leading honorific', () {
      expect(Provider.initialsOf('Dr. Amara Osei'), 'AO');
      expect(Provider.initialsOf('Mr Chen'), 'C');
      expect(Provider.initialsOf('Mrs. Fatima Bello'), 'FB');
    });

    test('uses one letter for a single-word name', () {
      expect(Provider.initialsOf('Cher'), 'C');
    });

    test('returns a placeholder rather than an empty string', () {
      expect(Provider.initialsOf(''), '?');
      expect(Provider.initialsOf('   '), '?');
      expect(Provider.initialsOf('Dr.'), '?');
    });

    test('collapses repeated whitespace', () {
      expect(Provider.initialsOf('Dr.  Amara   Osei'), 'AO');
    });

    test('a patient and a clinician share one rule', () {
      final profile = Profile(
        id: 'p',
        role: UserRole.patient,
        fullName: 'Dr. Amara Osei',
        countryCode: 'GB',
        locale: 'en',
        createdAt: DateTime.utc(2026),
      );
      expect(profile.initials, Provider.initialsOf('Dr. Amara Osei'));
    });
  });

  group('AuthSession persistence', () {
    test('round-trips through JSON', () {
      final session = AuthSession(
        userId: '11111111-1111-1111-1111-111111111111',
        email: 'a@b.com',
        issuedAt: DateTime.utc(2026, 3, 1, 12),
      );
      final restored = AuthSession.fromJson(_encode(session));
      expect(restored, isNotNull);
      expect(restored!.userId, session.userId);
      expect(restored.email, session.email);
      expect(restored.issuedAt, session.issuedAt);
    });

    test('returns null for corrupt or partial stored data', () {
      expect(AuthSession.fromJson(null), isNull);
      expect(AuthSession.fromJson(''), isNull);
      expect(AuthSession.fromJson('not json'), isNull);
      expect(AuthSession.fromJson('{"user_id":"x"}'), isNull);
      expect(AuthSession.fromJson('[]'), isNull);
    });
  });
}

String _encode(AuthSession session) =>
    '{"user_id":"${session.userId}","email":"${session.email}",'
    '"issued_at":"${session.issuedAt.toIso8601String()}"}';