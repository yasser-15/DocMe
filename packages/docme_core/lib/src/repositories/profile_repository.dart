import '../database.dart';
import '../failure.dart';
import '../models/identity.dart';

/// The signed-in user's own profile, plus the reference data the shell needs.
///
/// Everything here is owner-scoped: `profiles_select_own` limits reads to
/// `id = auth.uid()`, and [DocMeDatabase.asUser] sets that claim. No query in
/// this file can reach another user's row.
class ProfileRepository {
  ProfileRepository(this._db);
  final DocMeDatabase _db;

  /// Loads the signed-in user's profile.
  ///
  /// Returns `notFound` when RLS hides the row, which for an authenticated user
  /// means the account has no profile — a state the app treats as "finish
  /// setting up", not as an error to display raw.
  Future<Result<Profile>> load(String userId) {
    return _db.asUser<Profile>(userId, (s) async {
      final rows = await s.selectAs<Profile>(
        '''
        select id, role, full_name, phone, country_code, locale, city, region,
               st_y(location::geometry) as latitude,
               st_x(location::geometry) as longitude,
               avatar_url, created_at
          from profiles
         where id = @id
        ''',
        Profile.fromRow,
        {'id': P.uuid(userId)},
      );
      if (rows.isEmpty) {
        throw const DocMeRowMissing('profiles');
      }
      return rows.first;
    });
  }

  /// Updates the editable profile fields.
  ///
  /// Null means "leave alone" rather than "clear", so a partial update cannot
  /// silently wipe a phone number the user did not touch. There is no
  /// `clearField` parameter by design: clearing a field is a separate,
  /// deliberate action.
  Future<Result<Profile>> update(
    String userId, {
    String? fullName,
    String? phone,
    String? city,
    String? region,
  }) {
    return _db.asUser<Profile>(userId, (s) async {
      final updated = await s.selectAs<Profile>(
        '''
        update profiles
           set full_name = coalesce(@full_name, full_name),
               phone      = coalesce(@phone,      phone),
               city       = coalesce(@city,       city),
               region     = coalesce(@region,     region)
         where id = @id
        returning id, role, full_name, phone, country_code, locale, city, region,
                   st_y(location::geometry) as latitude,
                   st_x(location::geometry) as longitude,
                   avatar_url, created_at
        ''',
        Profile.fromRow,
        {
          'id': P.uuid(userId),
          'full_name': P.text(fullName),
          'phone': P.text(phone),
          'city': P.text(city),
          'region': P.text(region),
        },
      );
      if (updated.isEmpty) throw const DocMeRowMissing('profiles');
      return updated.first;
    });
  }

  /// Records the device's resolved position.
  ///
  /// [latitude] and [longitude] go to `profiles.location`, which RLS keeps
  /// private — "near me" discovery uses the *provider's* public location and
  /// filters it against this value in the query, so the patient's own coordinate
  /// is never handed to the client for filtering.
  ///
  /// [city] and [region] come from reverse geocoding and are cached here so
  /// discovery has a textual fallback when GPS is unavailable.
  Future<Result<Profile>> setLocation(
    String userId, {
    required double latitude,
    required double longitude,
    String? city,
    String? region,
  }) {
    // PostGIS wants (longitude, latitude). Getting this backwards puts every
    // patient near the antimeridian and is silent, so reject the impossible
    // values rather than storing them.
    if (latitude < -90 || latitude > 90) {
      return Future.value(const Err<Profile>(DocMeFailure(kind: DocMeFailureKind.validation, message: 'Latitude must be between -90 and 90.'))) as Future<Result<Profile>>;





    }
    if (longitude < -180 || longitude > 180) {
      return Future.value(const Err<Profile>(DocMeFailure(kind: DocMeFailureKind.validation, message: 'Longitude must be between -180 and 180.'))) as Future<Result<Profile>>;





    }

    return _db.asUser<Profile>(userId, (s) async {
      final rows = await s.selectAs<Profile>(
        '''
        update profiles
           set location = st_setsrid(st_makepoint(@lng, @lat), 4326)::geography,
               city     = coalesce(@city,   city),
               region   = coalesce(@region, region)
         where id = @id
        returning id, role, full_name, phone, country_code, locale, city, region,
                   st_y(location::geometry) as latitude,
                   st_x(location::geometry) as longitude,
                   avatar_url, created_at
        ''',
        Profile.fromRow,
        {
          'id': P.uuid(userId),
          'lat': P.numeric(latitude),
          'lng': P.numeric(longitude),
          'city': P.text(city),
          'region': P.text(region),
        },
      );
      if (rows.isEmpty) throw const DocMeRowMissing('profiles');
      return rows.first;
    });
  }

  /// All specialties, for the discovery filter chips.
  ///
  /// World-readable reference data (`specialties_read ... using (true)`), so this
  /// works before sign-in too.
  Future<Result<List<Specialty>>> specialties(String userId) {
    return _db.asUser<List<Specialty>>(userId, (s) async {
      return s.selectAs(
        'select id, slug, name, icon, category from specialties order by name',
        Specialty.fromRow,
      );
    });
  }
}
