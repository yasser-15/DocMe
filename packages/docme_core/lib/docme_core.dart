/// DocMe domain layer.
///
/// `patient_app` and (from M7) `provider_app` both depend on this package and
/// nothing else from the server side: there is no second data layer to keep in
/// step.
///
/// The shape is deliberate:
///
/// - [DocMeDatabase] is the only thing that talks to Postgres, and every call it
///   makes establishes identity first. Access rules live in the database's RLS
///   policies, not here — see `supabase/migrations/0003_rls.sql`.
/// - Repositories return `Result<T>` instead of throwing, because every failure
///   mode (RLS denial, wrong password, slot just taken) is a normal state the UI
///   has to render.
/// - Models are plain data with a `fromRow` per table, so a column rename is a
///   compile error at the repository that maps it rather than a null reaching the
///   screen.
library;

export 'src/config.dart';
export 'src/database.dart';
export 'src/failure.dart';
export 'src/models/care.dart';
export 'src/models/health.dart';
export 'src/models/identity.dart';
export 'src/password.dart';
export 'src/repositories/appointment_repository.dart';
export 'src/repositories/auth_repository.dart';
export 'src/repositories/discovery_repository.dart';
export 'src/repositories/profile_repository.dart';