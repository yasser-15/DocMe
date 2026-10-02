import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Password hashing.
///
/// The app derives a PBKDF2-SHA256 hash **on the device** and sends only that to
/// the database. The password itself never leaves the process, so a dump of
/// `auth.users` reveals no credentials, and there is nothing in the wire
/// protocol worth replaying against `auth.authenticate()`.
///
/// The stored string is self-describing:
///
/// ```
/// pbkdf2_sha256$<iterations>$<base64 salt>$<base64 hash>
/// ```
///
/// Iteration count and salt live inside the string so the cost can be raised
/// later without invalidating existing rows: [verify] reads the parameters from
/// whatever it is given rather than assuming the current defaults.
class PasswordHasher {
  const PasswordHasher({
    this.iterations = defaultIterations,
    this.saltLengthBytes = 16,
  });

  /// OWASP's 2023 floor for PBKDF2-HMAC-SHA256 is 600 000, but that is tuned for
  /// server hardware. This runs on a phone UI thread, so it is deliberately
  /// lower — the trade is made in [DartPbkdf2.pauseFrequency] instead, which
  /// yields to the event loop so the frame does not drop.
  ///
  /// Revisit if the account system ever gains a server component.
  static const int defaultIterations = 100000;

  final int iterations;
  final int saltLengthBytes;

  /// The algorithm used for both [hash] and [_encode].
  ///
  /// `pauseFrequency` is the reason [hash] is async: `DartPbkdf2` yields to the
  /// event loop every [pauseFrequency] rounds, so a 100k-round derivation costs a
  /// few short slices of work instead of one long synchronous block that would
  /// drop the first frame of the sign-in transition.
  static DartPbkdf2 _algorithm({required int rounds, required int bits}) =>
      DartPbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: rounds,
        bits: bits,
        pauseFrequency: 500,
        pausePeriod: const Duration(milliseconds: 1),
      );

  /// Derives the stored representation of [password], using a fresh random salt.
  Future<String> hash(String password) async {
    _validate(password);

    final rng = Random.secure();
    final salt = List<int>.generate(saltLengthBytes, (_) => rng.nextInt(256));

    return _encode(password, salt, iterations);
  }

  /// Checks [password] against a stored hash produced by [hash].
  ///
  /// Returns false rather than throwing on a malformed hash, so a corrupted row
  /// denies access instead of crashing the sign-in screen.
  Future<bool> verify(String password, String? stored) async {
    if (stored == null || stored.isEmpty) return false;

    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;

    final storedIterations = int.tryParse(parts[1]);
    if (storedIterations == null || storedIterations < 1) return false;

    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }

    final algorithm = _algorithm(
      rounds: storedIterations,
      bits: expected.length * 8,
    );

    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final actual = await key.extractBytes();

    // Constant-time: a length-then-content comparison leaks the prefix length
    // through timing, which is enough to narrow a brute-force search.
    return _constantTimeEquals(actual, expected);
  }

  Future<String> _encode(String password, List<int> salt, int rounds) async {
    final algorithm = _algorithm(rounds: rounds, bits: 256);

    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final hash = await key.extractBytes();

    return 'pbkdf2_sha256\$$rounds\$${base64Encode(salt)}\$${base64Encode(hash)}';
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Rejects input the database would reject anyway, but with a message that can
  /// be shown to the user. Called before hashing so the expensive derivation is
  /// not spent on input that cannot be accepted.
  static void _validate(String password) {
    if (password.length < 8) {
      throw ArgumentError.value(
        password.length,
        'password',
        'must be at least 8 characters',
      );
    }
    if (password.length > 256) {
      // PBKDF2 cost is linear in password length; an unbounded input is both a
      // UI freeze and a cheap way to burn someone's battery.
      throw ArgumentError.value(
        password.length,
        'password',
        'must be at most 256 characters',
      );
    }
  }

  /// Length check for the UI, so the sign-up form can validate before submitting.
  static const int minimumLength = 8;
}

/// Hashes a password for a fixture or a seed, outside any UI context.
///
/// Seed migrations need a hash whose plaintext is a published demo credential,
/// and they cannot call back into Dart. This exists so the demo password in
/// `supabase/migrations/0008_seed.sql` can be regenerated rather than
/// hand-computed:
///
/// ```sh
/// dart run tool/hash_password.dart docme123
/// ```
Future<String> hashPasswordForSeed(String password) =>
    const PasswordHasher().hash(password);