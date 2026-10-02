import '../database.dart';
import '../failure.dart';
import '../models/care.dart';
import '../models/identity.dart';

/// Search for clinicians.
///
/// ## Why this does not join `profiles`
///
/// `profiles` is owner-only under RLS (`profiles_select_own ... id = auth.uid()`),
/// so a patient cannot read a provider's row from it — no name, no city, no
/// location. `provider_profiles` is the world-readable clinician projection
/// (migration `0007_provider_public_profile.sql`) and carries exactly the public
/// fields. Every table joined here is readable by `docme_authenticated`:
///
/// - `provider_profiles` — `using (true)`
/// - `specialties` — `using (true)`
/// - `services` — `is_published or provider_id = auth.uid()`
/// - `ratings` — `using (true)`
/// - `provider_insurance` / `insurance_plans` — `using (true)`
///
/// If a query here ever starts returning zero rows for every patient with no
/// error, a policy was changed. That is the signature to look for, not a null
/// parameter.
class DiscoveryRepository {
  DiscoveryRepository(this._db);
  final DocMeDatabase _db;

  /// Searches published clinicians.
  ///
  /// All filters are optional and combine with AND. Passing [origin] turns on
  /// both the radius filter and the distance calculation; without it, results are
  /// ordered by rating instead of proximity.
  ///
  /// [radiusKm] defaults to 25km. The radius filter uses `st_dwithin` on the
  /// indexed geography column, so this stays a cheap bbox/gist scan rather than a
  /// sequential distance sort over every clinician.
  Future<Result<List<Provider>>> search(
    String userId, {
    String? query,
    String? specialtySlug,
    String? city,
    double? originLatitude,
    double? originLongitude,
    double radiusKm = 25,
    bool emergencyOnly = false,
    int limit = 50,
  }) {
    if (originLatitude != null && originLongitude == null ||
        originLatitude == null && originLongitude != null) {
      return Future.value(const Err<List<Provider>>(DocMeFailure(kind: DocMeFailureKind.validation, message: 'A search origin needs both a latitude and a longitude.'))) as Future<Result<List<Provider>>>;





    }

    return _db.asUser<List<Provider>>(userId, (s) async {
      return s.selectAs<Provider>(
        '''
        select pp.id,
               pp.full_name,
               sp.name as specialty_name,
               sp.slug as specialty_slug,
               pp.clinic,
               pp.bio,
               pp.license_no,
               pp.years_experience,
               pp.languages,
               pp.is_verified,
               pp.city,
               pp.region,
               st_y(pp.location::geometry) as latitude,
               st_x(pp.location::geometry) as longitude,
               agg.avg_rating,
               agg.cnt                  as review_count,
               svc.min_price            as from_price,
               svc.currency             as currency,
               case
                 when @lat::float8 is null then null
                 else st_distance(
                        pp.location,
                        st_setsrid(st_makepoint(@lng, @lat), 4326)::geography
                      ) / 1000.0
               end                      as distance_km
          from provider_profiles pp
          left join specialties sp
                 on sp.id = pp.specialty_id
          left join lateral (
                select avg(r.stars)::float8 as avg_rating,
                       count(*)::int        as cnt
                  from ratings r
                 where r.provider_id = pp.id
          ) agg on true
          left join lateral (
                select min(sv.price)               as min_price,
                       (array_agg(sv.currency))[1]  as currency
                  from services sv
                 where sv.provider_id = pp.id
                   and sv.is_published
          ) svc on true
         where (@q::text is null
                or pp.full_name ilike '%' || @q || '%'
                or sp.name     ilike '%' || @q || '%'
                or pp.clinic   ilike '%' || @q || '%')
           and (@slug::text is null or sp.slug = @slug)
           and (@city::text is null or pp.city = @city)
           and (@lat::float8 is null
                or (pp.location is not null
                    and st_dwithin(
                          pp.location,
                          st_setsrid(st_makepoint(@lng, @lat), 4326)::geography,
                          @radius_m)))
           -- Emergency dispatch needs an actual emergency-capable service, and a
           -- conditional inside the lateral above cannot do this: `left join
           -- lateral (...) on true` filters columns, not rows, so putting the
           -- test there would leave every provider in the result. Hence EXISTS.
           and (not @emergency
                or exists (
                     select 1 from services ev
                      where ev.provider_id = pp.id
                        and ev.is_published
                        and ev.is_emergency
                        and ev.visit_mode = 'home_visit'
                ))
         order by
           -- Proximity only leads when the caller gave an origin.
           case when @lat::float8 is null then 1 else 0 end,
           distance_km   asc nulls last,
           avg_rating    desc nulls last,
           pp.full_name  asc
         limit @limit
        ''',
        Provider.fromRow,
        {
          'q': P.text(query?.trim().isEmpty ?? true ? null : query!.trim()),
          'slug': P.text(specialtySlug),
          'city': P.text(city),
          'lat': P.numeric(originLatitude),
          'lng': P.numeric(originLongitude),
          'radius_m': P.numeric(radiusKm * 1000),
          'emergency': P.boolean(emergencyOnly),
          'limit': P.integer(limit),
        },
      );
    });
  }

  /// One clinician, with their published services.
  ///
  /// Returns `notFound` if the clinician has no `provider_profiles` row. That is
  /// not a permission denial: the table is world-readable, so absence means the
  /// account is not a clinician or is not yet set up.
  Future<Result<Provider>> provider(String userId, String providerId) {
    return _db.asUser<Provider>(userId, (s) async {
      final rows = await s.selectAs<Provider>(
        '''
        select pp.id,
               pp.full_name,
               sp.name as specialty_name,
               sp.slug as specialty_slug,
               pp.clinic,
               pp.bio,
               pp.license_no,
               pp.years_experience,
               pp.languages,
               pp.is_verified,
               pp.city,
               pp.region,
               st_y(pp.location::geometry) as latitude,
               st_x(pp.location::geometry) as longitude,
               agg.avg_rating,
               agg.cnt                  as review_count,
               (select min(sv.price) from services sv
                 where sv.provider_id = pp.id and sv.is_published) as from_price,
               (select (array_agg(sv.currency))[1] from services sv
                 where sv.provider_id = pp.id and sv.is_published) as currency
          from provider_profiles pp
          left join specialties sp on sp.id = pp.specialty_id
          left join lateral (
                select avg(r.stars)::float8 as avg_rating, count(*)::int as cnt
                  from ratings r where r.provider_id = pp.id
          ) agg on true
         where pp.id = @id
        ''',
        Provider.fromRow,
        {'id': P.uuid(providerId)},
      );
      if (rows.isEmpty) throw const DocMeRowMissing('provider_profiles');
      return rows.first;
    });
  }

  /// A clinician's published services.
  Future<Result<List<ServiceOffering>>> services(
    String userId,
    String providerId,
  ) {
    return _db.asUser<List<ServiceOffering>>(userId, (s) async {
      return s.selectAs<ServiceOffering>(
        '''
        select sv.id,
               sv.provider_id,
               sv.name,
               sv.price,
               sv.currency,
               sv.duration_min,
               sv.visit_mode,
               sv.description,
               sv.is_emergency,
               sp.name as specialty_name
          from services sv
          left join specialties sp on sp.id = sv.specialty_id
         where sv.provider_id = @provider
           and sv.is_published
         order by sv.price
        ''',
        ServiceOffering.fromRow,
        {'provider': P.uuid(providerId)},
      );
    });
  }

  /// Open slots for a clinician, optionally for one service.
  ///
  /// `availability_slots_select` permits reading `status = 'open'` rows for any
  /// clinician, or every row for one's own. A patient therefore sees availability
  /// but not another clinician's diary — booked slots are simply absent rather
  /// than shown, which is why this filters `status = 'open'` explicitly instead
  /// of trusting the caller.
  Future<Result<List<AvailabilitySlot>>> openSlots(
    String userId, {
    required String providerId,
    String? serviceId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) {
    final start = from ?? DateTime.now().toUtc();
    return _db.asUser<List<AvailabilitySlot>>(userId, (s) async {
      return s.selectAs<AvailabilitySlot>(
        '''
        select sl.id,
               sl.provider_id,
               sl.starts_at,
               sl.ends_at,
               sl.status,
               sl.recurrence_rule
          from availability_slots sl
         where sl.provider_id = @provider
           and sl.status = 'open'
           and sl.starts_at >= @from
           and (@to::timestamptz is null or sl.starts_at < @to)
           -- Only slots that can actually accommodate the service. Without this
           -- a 15-minute slot is offered for a 60-minute consultation and the
           -- booking either overlaps the next patient or is rejected later.
           and (@service::uuid is null
                or sl.ends_at - sl.starts_at
                   >= (select duration_min * interval '1 minute'
                         from services sv where sv.id = @service))
           and not exists (
                 select 1 from appointments a
                  where a.slot_id = sl.id
                    and a.status not in ('cancelled', 'no_show')
           )
         order by sl.starts_at
         limit @limit
        ''',
        AvailabilitySlot.fromRow,
        {
          'provider': P.uuid(providerId),
          'service': P.uuid(serviceId),
          'from': P.timestamp(start),
          'to': P.timestamp(to),
          'limit': P.integer(limit),
        },
      );
    });
  }

  /// Whether a clinician accepts a given insurance plan.
  Future<Result<bool>> acceptsInsurance(
    String userId, {
    required String providerId,
    required String insurancePlanId,
  }) {
    return _db.asUser<bool>(userId, (s) async {
      final rows = await s.select(
        '''
        select exists (
          select 1 from provider_insurance pi
           where pi.provider_id = @provider
             and pi.insurance_plan_id::text = @plan
        ) as ok
        ''',
        {'provider': P.uuid(providerId), 'plan': P.text(insurancePlanId)},
      );
      return (rows.first['ok'] as bool?) ?? false;
    });
  }
}
