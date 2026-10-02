/// Failure and Result types.
///
/// Repositories return `Result<T>` rather than throwing, because every failure
/// mode here is an expected state the UI has to render, not an exception to be
/// swallowed at a catch block somewhere above the widget tree:
library;
///
/// - RLS denying a query is normal (`inPermissionDenied`), not a crash.
/// - "wrong password" is normal (`unauthorized`).
/// - "email already registered" is normal (`conflict`).
///
/// A thrown exception in this codebase would also be ambiguous about *which*
/// role failed. `SET LOCAL ROLE docme_authenticated` is per transaction, so a
/// denial is genuinely a denial by policy — worth surfacing as such.

/// What went wrong, in terms the UI can act on.
enum DocMeFailureKind {
  /// Cannot reach the database at all — container down, wrong host, no network.
  network,

  /// Credentials were rejected. For login, or a session that has expired.
  unauthorized,

  /// Authenticated, but RLS refused the row.
  ///
  /// This is a *policy* outcome, not a bug. Seeing it usually means the app
  /// asked for something the access rules deliberately do not allow — for
  /// example a provider reading a patient's `health_records` before a completed
  /// appointment exists.
  permissionDenied,

  /// The row does not exist, or the caller cannot see it (RLS makes those two
  /// indistinguishable on purpose — a 404 would leak existence).
  notFound,

  /// Unique violation, or a check constraint rejected the write.
  conflict,

  /// Input the database refused. Not retryable without changing the input.
  validation,

  /// Server-side error or anything unrecognised.
  server,
}

/// A single failure, with enough context to show a message and decide a retry.
class DocMeFailure implements Exception {
  const DocMeFailure({
    required this.kind,
    required this.message,
    this.code,
    this.cause,
  });

  final DocMeFailureKind kind;

  /// Human-readable. Safe to show; Postgres `detail`/`hint` text is included
  /// only where it cannot contain PHI.
  final String message;

  /// SQLSTATE when the failure came from the server (`'42501'`, `'23505'`...).
  final String? code;

  /// The underlying error, kept for logging. Never shown.
  final Object? cause;

  /// Whether retrying the identical request could plausibly succeed.
  bool get isRetryable =>
      kind == DocMeFailureKind.network || kind == DocMeFailureKind.server;

  @override
  String toString() =>
      'DocMeFailure(${kind.name}${code == null ? '' : ' $code'}): $message';
}

/// Thrown inside a repository callback when the query succeeded but the row the
/// caller expects is absent — the `rows.isEmpty` case, where there is no SQLSTATE
/// to key off because `select` returning nothing is not an error.
///
/// This exists as a distinct type rather than each repository returning its own
/// sentinel because `DocMeDatabase._mapError` has to recognise it. A private
/// exception that the mapper does not know about falls through to the generic
/// `server` branch, which stringifies it — so a missing profile would surface to
/// the user as the literal text `_MissingProfile`. That is the failure mode this
/// type prevents.
///
/// Note the ambiguity is deliberate and matches [DocMeFailureKind.notFound]: an
/// owner-scoped query that returns nothing may mean the row is missing *or* that
/// RLS hid it, and the two must not be distinguishable to the caller.
class DocMeRowMissing implements Exception {
  const DocMeRowMissing([this.what]);

  /// What was being looked up, for logging only. Never shown to a user.
  final String? what;

  @override
  String toString() => 'DocMeRowMissing(${what ?? 'row'})';
}

/// Thrown inside a repository callback when the request was understood but is
/// being refused for a reason the user can act on — wrong visit mode for a
/// service, a clinician who does not offer the requested service, cancelling an
/// appointment that has already taken place.
///
/// Distinct from a [DocMeFailureKind.server] because retrying unchanged will
/// never succeed, and [DocMeFailure.isRetryable] would otherwise tell the UI to
/// offer a retry button for a permanently invalid request.
///
/// [message] is written for the user. It must never contain PHI: these
/// rejections travel through logs and crash reporters.
class DocMeRejected implements Exception {
  const DocMeRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Success-or-failure. Sealed so `switch` over it is exhaustive:
///
/// ```dart
/// switch (await repo.load()) {
///   case Ok(:final value):  render(value);
///   case Err(:final failure): showError(failure);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Folds both branches into a single value.
  R when<R>({
    required R Function(T) ok,
    required R Function(DocMeFailure) err,
  }) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final DocMeFailure failure;
}

/// Transforms the success value, leaving a failure untouched.
extension ResultMap<T> on Result<T> {
  Result<R> map<R>(R Function(T) transform) => when(
    ok: (value) => Ok(transform(value)),
    err: (failure) => Err<R>(failure),
  );
}

/// Convenience for repositories whose value is often absent.
extension ResultValue<T> on Result<T> {
  /// The value, or `null` on failure.
  T? get valueOrNull => when(ok: (v) => v, err: (_) => null);
}