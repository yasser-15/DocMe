import 'dart:async';
import 'dart:io';

// Prefixed deliberately. `package:postgres` also exports a type called `Result`
// (its row-count result), which collides with this package's own `Result<T>`.
// Hiding one of them is not an option: both are genuinely needed here — the
// postgres `Result` is the return type of `Session.execute`, and the local
// `Result` is what every repository returns. A prefix makes the distinction
// explicit at each use instead of hiding a name that will bite later.
import 'package:postgres/postgres.dart' as pg hide Result;

import 'config.dart';
import 'failure.dart';

/// Typed query parameters.
///
/// `postgres` uses the extended query protocol, which is strict: a parameter
/// sent as `text` cannot be stored into a `uuid` column, and the error surfaces
/// as an opaque "column is of type uuid but expression is of type text". Guessing
/// types from the Dart runtime value is exactly the wrong fix — `'0.3476'` and a
/// uuid are both `String`. So the type is always stated at the call site.
abstract final class P {
  /// uuid column.
  static pg.TypedValue uuid(String? v) => pg.TypedValue(pg.Type.uuid, v);

  /// text / varchar / citext column.
  static pg.TypedValue text(String? v) => pg.TypedValue(pg.Type.text, v);

  static pg.TypedValue integer(int? v) => pg.TypedValue(pg.Type.integer, v);

  static pg.TypedValue boolean(bool? v) => pg.TypedValue(pg.Type.boolean, v);

  static pg.TypedValue numeric(num? v) => pg.TypedValue(pg.Type.numeric, v);

  static pg.TypedValue timestamp(DateTime? v) => pg.TypedValue(pg.Type.timestampTz, v);

  /// A `date` column. Sent as text and cast in SQL, because the date codec's
  /// expectations around time zones are a trap and `::date` is unambiguous.
  static pg.TypedValue date(DateTime? v) =>
      pg.TypedValue(pg.Type.text, v == null ? null : _isoDate(v));

  /// A `time` column, as `HH:MM` or `HH:MM:SS`. Cast in SQL with `::time`.
  static pg.TypedValue time(String? v) => pg.TypedValue(pg.Type.text, v);

  /// A `jsonb` column.
  static pg.TypedValue jsonb(Object? v) => pg.TypedValue(pg.Type.jsonb, v);

  /// A `text[]` column, e.g. `languages` or `times_of_day`.
  static pg.TypedValue textArray(List<String>? v) =>
      pg.TypedValue(pg.Type.textArray, v);

  static String _isoDate(DateTime v) =>
      '${v.year.toString().padLeft(4, '0')}-'
      '${v.month.toString().padLeft(2, '0')}-'
      '${v.day.toString().padLeft(2, '0')}';
}

/// One database session, either authenticated or anonymous.
///
/// Deliberately not exposed outside `DocMeDatabase`: the only supported way to
/// run a query is [DocMeDatabase.asUser] or [DocMeDatabase.anonymous], because
/// both of those establish identity first. A session obtained any other way
/// could silently run with the wrong role, and since the role *is* the security
/// boundary here that would be invisible.
class DocMeSession {
  DocMeSession._(this._session);

  final pg.Session _session;

  /// Runs a query and returns every row as a map keyed by column name.
  ///
  /// Parameters use `@name` placeholders and must be built with [P].
  Future<List<Map<String, dynamic>>> select(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final result = await _run(sql, params);
    return [for (final row in result) row.toColumnMap()];
  }

  /// As [select], but maps each row immediately.
  ///
  /// Repositories use this so that every `Map<String, dynamic>` has exactly one
  /// consumer and a column rename becomes a compile error rather than a null
  /// surfacing three screens later.
  Future<List<T>> selectAs<T>(
    String sql,
    T Function(Map<String, dynamic> row) map, [
    Map<String, Object?> params = const {},
  ]) async {
    final rows = await select(sql, params);
    return [for (final row in rows) map(row)];
  }

  /// Runs a statement for effect and returns the number of rows affected.
  Future<int> run(String sql, [Map<String, Object?> params = const {}]) async {
    final result = await _run(sql, params);
    return result.affectedRows;
  }

  Future<pg.Result> _run(String sql, Map<String, Object?> params) {
    return _session.execute(
      params.isEmpty ? sql : pg.Sql.named(sql),
      parameters: params.isEmpty ? null : params,
    );
  }
}

/// The application's connection to Postgres.
///
/// ## How identity works
///
/// The compose stack runs plain Postgres — there is no PostgREST and no GoTrue —
/// so `supabase_flutter` cannot be used. [asUser] reproduces what PostgREST does
/// for an authenticated request, using the two statements `rls_test.sql` already
/// relies on:
///
/// ```sql
/// set local role docme_authenticated;
/// select set_config('request.jwt.claims', '{"sub":"<uuid>"}', true);
/// ```
///
/// `set local role` is what makes RLS apply; the `request.jwt.claims` GUC is
/// what `auth.uid()` reads (defined in `0001_extensions.sql`). Both are
/// transaction-scoped, so the identity cannot leak to the next request on a
/// pooled connection. That is the property that makes it safe to keep the pool
/// open.
///
/// **RLS is not an app-layer check and this class does not implement access
/// rules.** It only establishes *who is asking*. Whether that person may see a
/// row is decided by the policies in `0003_rls.sql`, which is the only place the
/// rules live. When PostgREST is added, these two statements are replaced by a
/// verified JWT and the policies need no change.
class DocMeDatabase {
  DocMeDatabase._(this._pool, this._config);

  final pg.Pool _pool;
  final DocMeConfig _config;

  /// Opens the pool.
  ///
  /// Small on purpose: this is a phone talking to a local container, and every
  /// extra idle connection is a Postgres backend doing nothing.
  static Future<DocMeDatabase> open(
    DocMeConfig config, {
    int maxConnections = 4,
  }) async {
    final pool = pg.Pool.withEndpoints(
      [
        pg.Endpoint(
          host: config.host,
          port: config.port,
          database: config.database,
          username: config.user,
          password: config.password,
        ),
      ],
      settings: pg.PoolSettings(
        applicationName: 'docme_app',
        // UTC on the wire. Timestamps are stored and returned in UTC and
        // converted to the user's zone in Dart, so a device changing timezone
        // cannot shift a stored appointment.
        timeZone: 'UTC',
        connectTimeout: config.connectTimeout,
        sslMode: config.ssl ? pg.SslMode.require : pg.SslMode.disable,
      ),
    );

    // A Pool connects lazily, so `open` succeeding does not mean the database
    // is reachable. Prove it, so a misconfigured host is a clear failure at
    // startup instead of a confusing empty screen later.
    try {
      await pool.execute('select 1');
    } on Object catch (error) {
      await pool.close();
      throw DocMeDatabaseUnavailable(_mapError(error, config));
    }

    return DocMeDatabase._(pool, config);
  }

  DocMeConfig get config => _config;

  /// Runs [body] as [userId], with RLS fully enforced.
  ///
  /// Every read and write of user data goes through here. [body] runs inside a
  /// transaction, so several statements share one identity and one snapshot,
  /// and a failure part-way through rolls the whole thing back — which matters
  /// for booking, where writing the appointment and marking the slot booked must
  /// not come apart.
  ///
  /// Errors from inside [body] are mapped to [DocMeFailure] and returned as
  /// `Err`, except [DocMeFailure] values [body] returns deliberately.
  Future<Result<T>> asUser<T>(
    String userId,
    Future<T> Function(DocMeSession session) body,
  ) async {
    try {
      return Ok(
        await _pool.runTx((tx) async {
          await tx.execute('set local role docme_authenticated');
          await tx.execute(
            'select set_config(\'request.jwt.claims\', @claims, true)',
            parameters: {'claims': P.text('{"sub":"$userId"}')},
          );
          return body(DocMeSession._(tx));
        }),
      );
    } on Object catch (error) {
      return Err(_mapError(error, _config));
    }
  }

  /// Runs [body] with no identity.
  ///
  /// Only for `auth.signup` and `auth.authenticate`, which are SECURITY DEFINER
  /// functions and must be callable before the caller has an identity to present.
  /// [DocMeConfig.isDefault] is not checked here — a misconfigured password will
  /// simply fail to authenticate, and a specific error beats a guess.
  Future<Result<T>> anonymous<T>(
    Future<T> Function(DocMeSession session) body,
  ) async {
    try {
      return Ok(
        await _pool.runTx((tx) async {
          return body(DocMeSession._(tx));
        }),
      );
    } on Object catch (error) {
      return Err(_mapError(error, _config));
    }
  }

  /// True if the database answers. Used by the UI to distinguish "no data" from
  /// "cannot reach the server".
  Future<bool> ping() async {
    try {
      await _pool.execute('select 1');
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> close() => _pool.close();

  /// Translates a thrown object into a [DocMeFailure].
  ///
  /// The mapping is driven by SQLSTATE rather than message text, because the
  /// messages are localisation- and version-dependent while the codes are fixed
  /// by the SQL standard.
  static DocMeFailure _mapError(Object error, DocMeConfig config) {
    if (error is DocMeDatabaseUnavailable) return error.failure;

    // Checked before ServerException and the generic branches: a repository
    // signalling "the query worked, the row is not there" is not a fault, and
    // without this it would be stringified and shown to the user.
    if (error is DocMeRowMissing) {
      return DocMeFailure(
        kind: DocMeFailureKind.notFound,
        message: 'That information is not available.',
        cause: error,
      );
    }

    // Refused on the merits. `validation` rather than `server` so the UI does
    // not offer a retry for a request that can never succeed.
    if (error is DocMeRejected) {
      return DocMeFailure(
        kind: DocMeFailureKind.validation,
        message: error.message,
        cause: error,
      );
    }

    if (error is pg.ServerException) {
      return _fromSqlState(error.code, error.message, error);
    }

    if (error is TimeoutException) {
      return DocMeFailure(
        kind: DocMeFailureKind.network,
        message: 'The server took too long to respond.',
        cause: error,
      );
    }

    if (error is SocketException || error is HandshakeException) {
      return DocMeFailure(
        kind: DocMeFailureKind.network,
        message:
            'Cannot reach the DocMe database at ${config.host}:${config.port}. '
            'Is it running? (`\\.\\build.ps1 db up`)',
        cause: error,
      );
    }

    if (error is StateError || error is ArgumentError) {
      return DocMeFailure(
        kind: DocMeFailureKind.validation,
        message: error.toString(),
        cause: error,
      );
    }

    return DocMeFailure(
      kind: DocMeFailureKind.server,
      message: error.toString(),
      cause: error,
    );
  }

  static DocMeFailure _fromSqlState(
    String? code,
    String message,
    Object cause,
  ) {
    switch (code) {
      case '42501': // insufficient_privilege — an RLS policy refused the row.
        return DocMeFailure(
          kind: DocMeFailureKind.permissionDenied,
          message:
              'You do not have access to this. (denied by access rules)',
          code: code,
          cause: cause,
        );

      case '23505': // unique_violation
        // auth.signup raises this with a deliberate message for a taken email,
        // which is a validation problem the form can explain, not a conflict.
        if (message.startsWith('AUTH_EMAIL_TAKEN')) {
          return DocMeFailure(
            kind: DocMeFailureKind.validation,
            message: 'An account already exists for that email.',
            code: code,
            cause: cause,
          );
        }
        return DocMeFailure(
          kind: DocMeFailureKind.conflict,
          message: 'That already exists.',
          code: code,
          cause: cause,
        );

      case '23503': // foreign_key_violation
      case '23514': // check_violation
      case '23502': // not_null_violation
      case '22023': // invalid_parameter_value
      case '22P02': // invalid_text_representation
        return DocMeFailure(
          kind: DocMeFailureKind.validation,
          message: _cleanMessage(message),
          code: code,
          cause: cause,
        );

      case 'P0001': // raise_exception — our own auth functions
        return DocMeFailure(
          kind: message.startsWith('AUTH_INVALID')
              ? DocMeFailureKind.validation
              : DocMeFailureKind.server,
          message: message.replaceFirst('AUTH_INVALID: ', ''),
          code: code,
          cause: cause,
        );

      case '57014': // query_canceled — statement timeout
        return DocMeFailure(
          kind: DocMeFailureKind.server,
          message: 'The query took too long and was cancelled.',
          code: code,
          cause: cause,
        );

      default:
        return DocMeFailure(
          kind: DocMeFailureKind.server,
          message: _cleanMessage(message),
          code: code,
          cause: cause,
        );
    }
  }

  /// Strips the `CONTEXT:`/`STATEMENT:` tails Postgres appends.
  ///
  /// Those repeat the failing SQL verbatim. Showing the SQL to a user leaks
  /// table and column names, which is a small disclosure but a free one.
  static String _cleanMessage(String message) {
    final cut = message.indexOf('\nCONTEXT:');
    final base = cut == -1 ? message : message.substring(0, cut);
    return base.trim();
  }
}

/// Thrown by [DocMeDatabase.open] when the initial connection fails.
///
/// Distinct from a plain [DocMeFailure] because it happens during construction,
/// where there is no `Result` to return yet.
class DocMeDatabaseUnavailable implements Exception {
  const DocMeDatabaseUnavailable(this.failure);
  final DocMeFailure failure;

  @override
  String toString() => 'DocMeDatabaseUnavailable: $failure';
}
