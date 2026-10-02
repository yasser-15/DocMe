/// Connection settings for the DocMe Postgres database.
///
/// Supplied via `--dart-define` at build time, because a mobile binary cannot
/// read a `.env` file and the values differ per machine:
///
/// ```
/// flutter run \
///   --dart-define=DOCME_DB_HOST=127.0.0.1 \
///   --dart-define=DOCME_DB_PORT=54329 \
///   --dart-define=DOCME_DB_NAME=docme \
///   --dart-define=DOCME_DB_USER=docme_client \
///   --dart-define=DOCME_DB_PASSWORD=change_me_local_only
/// ```
///
/// ## Reaching the host from a device
///
/// `docker/compose.yaml` binds Postgres to `127.0.0.1` only, because the
/// database holds PHI and must not be reachable from the LAN. That has a
/// consequence on mobile, where `127.0.0.1` means *the device itself*:
///
/// - **Android emulator** — use `DOCME_DB_HOST=10.0.2.2`. That alias maps to the
///   host's loopback interface, so the emulator reaches the same loopback-bound
///   port and no new host exposure is needed.
/// - **Physical device over USB** — run `adb reverse tcp:54329 tcp:54329`, then
///   `DOCME_DB_HOST=127.0.0.1` works as written.
/// - **iOS simulator** — `127.0.0.1` shares the host network stack, so it works
///   unmodified. A physical iOS device needs the same `adb reverse` equivalent
///   or a tunnel.
library;

class DocMeConfig {
  const DocMeConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
    this.ssl = false,
    this.connectTimeout = const Duration(seconds: 10),
  });

  /// Reads configuration from `--dart-define` values.
  ///
  /// The defaults match `.env.example`. They are deliberately *not* a usable
  /// production configuration: [isDefault] lets the app refuse to start with an
  /// unchanged default password rather than silently talking to the wrong
  /// database.
  factory DocMeConfig.fromEnvironment() {
    return DocMeConfig(
      host: const String.fromEnvironment(
        'DOCME_DB_HOST',
        defaultValue: '127.0.0.1',
      ),
      port: const int.fromEnvironment('DOCME_DB_PORT', defaultValue: 54329),
      database: const String.fromEnvironment(
        'DOCME_DB_NAME',
        defaultValue: 'docme',
      ),
      user: const String.fromEnvironment(
        'DOCME_DB_USER',
        defaultValue: 'docme_client',
      ),
      password: const String.fromEnvironment(
        'DOCME_DB_PASSWORD',
        defaultValue: 'change_me_local_only',
      ),
      ssl: const bool.fromEnvironment('DOCME_DB_SSL'),
    );
  }

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  /// Off for the local container, which serves no TLS. Must be on for anything
  /// that leaves the machine.
  final bool ssl;

  final Duration connectTimeout;

  /// True when nothing was supplied at build time.
  ///
  /// Only ever a useful signal in debug builds — see `kDebugMode` at the call
  /// site, because a release build must never be configured this way.
  bool get isDefault => password == 'change_me_local_only';

  /// Redacted form for logs. The password must never reach a log line.
  @override
  String toString() =>
      'DocMeConfig($user@$host:$port/$database, ssl: $ssl, password: ********)';
}