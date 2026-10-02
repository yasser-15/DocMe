import '../database.dart';
import '../failure.dart';
import '../models/care.dart';
import '../models/identity.dart';

/// Booking, and the patient's own appointments.
///
/// ## The booking invariant
///
/// An appointment and the slot it consumes must be written together. Two
/// failure modes make that mandatory:
///
/// 1. **Double booking.** Two patients pick the same last open slot. Whoever
///    commits second must lose, cleanly.
/// 2. **Split state.** The appointment row is written and the slot update fails,
///    leaving a booked appointment attached to a slot that still reads `open`.
///
/// Both are prevented by doing it in one transaction with the slot claimed by a
/// conditional `UPDATE` — `update ... where status = 'open'`, checking
/// `affected_rows = 1`. The row lock that `UPDATE` takes serialises concurrent
/// bookings on the same slot, so the second transaction's `UPDATE` matches zero
/// rows and it aborts. That check is the whole mechanism; without it the app
/// would happily double-book, because RLS says nothing about slot capacity.
///
/// ## Status lifecycle
///
/// The patient may `requested -> cancelled`, and `confirmed -> cancelled`.
/// A `completed` appointment is what grants a clinician read access to the
/// patient's `health_records` (`is_completed_appointment()` in `0003_rls.sql`),
/// so it is deliberately not patient-settable here — a patient who could set it
/// could grant a clinician PHI access. Cancelling does *not* grant it, which is
/// why the test suite asserts a cancelled appointment opens nothing.
class AppointmentRepository {
  AppointmentRepository(this._db);
  final DocMeDatabase _db;

  /// Books an appointment.
  ///
  /// [slotId] may be null for an emergency home visit, which is dispatched
  /// immediately rather than scheduled. Pass a slot otherwise; the appointment
  /// is rejected if the slot is gone, too short for the service, or already
  /// claimed.
  ///
  /// [reason] is free text the patient supplies and is PHI. It is written as
  /// given — never logged, never included in an error message.
  Future<Result<Appointment>> book(
    String userId, {
    required String providerId,
    required String serviceId,
    String? slotId,
    required VisitMode visitMode,
    String? reason,
    DateTime? homeVisitAt,
  }) {
    return _db.asUser<Appointment>(userId, (s) async {
      // Validate the service before touching the slot. Catching a bad service id
      // after the slot has been claimed would burn the slot on a failed booking.
      final service = await s.select(
        '''
        select id, provider_id, duration_min, price, currency, visit_mode, is_published
          from services
         where id = @service
        ''',
        {'service': P.uuid(serviceId)},
      );
      if (service.isEmpty) {
        throw const DocMeRowMissing('services');
      }
      final row = service.first;
      if (row['provider_id'] != providerId) {
        throw const DocMeRejected('That service is not offered by this clinician.');
      }
      if (row['visit_mode'] != visitMode.toDb) {
        throw DocMeRejected(
          'That service is offered as ${VisitMode.parse(row['visit_mode'] as String?).label.toLowerCase()}, '
          'not ${visitMode.label.toLowerCase()}.',
        );
      }

      final claimedSlotId = slotId == null
          ? null
          : await _claimSlot(s, slotId, (row['duration_min'] as num).toInt());

      final created = await s.selectAs<Appointment>(
        '''
        insert into appointments
              (patient_id, provider_id, service_id, slot_id, status, visit_mode, reason)
        values
              (@patient, @provider, @service, @slot, @status, @mode, @reason)
        returning id, patient_id, provider_id, service_id, slot_id, status,
                  visit_mode, reason, created_at
        ''',
        Appointment.fromRow,
        {
          'patient': P.uuid(userId),
          'provider': P.uuid(providerId),
          'service': P.uuid(serviceId),
          'slot': P.uuid(claimedSlotId),
          // An emergency dispatch has nobody to confirm it, so it starts
          // confirmed. A scheduled booking starts `requested` and waits for the
          // clinician, matching the provider app's M7 workflow.
          'status': P.text(
            slotId == null && visitMode == VisitMode.homeVisit
                ? 'confirmed'
                : 'requested',
          ),
          'mode': P.text(visitMode.toDb),
          'reason': P.text(reason),
        },
      );

      return _hydrate(s, created.first);
    });
  }

  /// Atomically marks a slot booked, failing if it was already taken.
  ///
  /// `affected_rows == 0` is the contention signal: another transaction claimed
  /// the slot between the availability listing and this booking. Surfaced as a
  /// `conflict` so the UI can say "that time was just taken" and offer the next
  /// slot, rather than a generic failure the user cannot act on.
  Future<String> _claimSlot(
    DocMeSession s,
    String slotId,
    int serviceDurationMin,
  ) async {
    final affected = await s.run(
      '''
      update availability_slots
         set status = 'booked'
       where id = @slot
         and status = 'open'
         and ends_at - starts_at >= make_interval(mins => @duration)
         and not exists (
               select 1 from appointments a
                where a.slot_id = @slot
                  and a.status not in ('cancelled', 'no_show')
         )
      ''',
      {'slot': P.uuid(slotId), 'duration': P.integer(serviceDurationMin)},
    );

    if (affected != 1) {
      throw const DocMeFailure(
        kind: DocMeFailureKind.conflict,
        message: 'That time was just taken. Please pick another.',
        code: 'SLOT_TAKEN',
      );
    }
    return slotId;
  }

  /// The patient's appointments, newest first.
  ///
  /// [upcoming] returns only future `requested`/`confirmed` appointments, which
  /// is what the Today screen's "next visit" tile wants. [past] returns the
  /// completed/cancelled history.
  Future<Result<List<Appointment>>> list(
    String userId, {
    bool upcoming = false,
    bool includeCancelled = false,
    int limit = 100,
  }) {
    return _db.asUser<List<Appointment>>(userId, (s) async {
      final rows = await s.select(
        _appointmentSelect + '''
         where a.patient_id = @patient
           and (@upcoming::boolean is false
                or (coalesce(sl.starts_at, a.created_at) >= @now
                    and a.status in ('requested', 'confirmed')))
           and (@cancelled::boolean or a.status <> 'cancelled')
         order by coalesce(sl.starts_at, a.created_at) desc
         limit @limit
        ''',
        {
          'patient': P.uuid(userId),
          'upcoming': P.boolean(upcoming),
          'now': P.timestamp(DateTime.now().toUtc()),
          'cancelled': P.boolean(includeCancelled),
          'limit': P.integer(limit),
        },
      );
      return [for (final row in rows) _mapAppointment(row)];
    });
  }

  /// One appointment, if it is the patient's own.
  Future<Result<Appointment>> get(String userId, String appointmentId) {
    return _db.asUser<Appointment>(userId, (s) async {
      final rows = await s.select(
        _appointmentSelect + ' where a.id = @id',
        {'id': P.uuid(appointmentId)},
      );
      if (rows.isEmpty) throw const DocMeRowMissing('appointments');
      return _mapAppointment(rows.first);
    });
  }

  /// Cancels an appointment and releases its slot.
  ///
  /// Only `requested` and `confirmed` can be cancelled. A `completed` visit is
  /// part of the clinical record and is immutable from the patient side; letting
  /// them cancel one would both rewrite history and revoke the clinician's
  /// record access, which would silently make a clinician's notes disappear.
  ///
  /// Releasing the slot is not optional — otherwise a cancelled booking leaves a
  /// permanently unavailable slot in the clinician's diary.
  Future<Result<Appointment>> cancel(
    String userId,
    String appointmentId, {
    String? reason,
  }) {
    return _db.asUser<Appointment>(userId, (s) async {
      final changed = await s.run(
        '''
        update appointments
           set status = 'cancelled',
               reason  = coalesce(@reason, reason)
         where id = @id
           and patient_id = @patient
           and status in ('requested', 'confirmed')
        ''',
        {
          'id': P.uuid(appointmentId),
          'patient': P.uuid(userId),
          'reason': P.text(reason),
        },
      );

      if (changed == 0) {
        // Either it is not theirs (RLS hides it, so it reads as missing) or it is
        // no longer cancellable. Both are a no-op from the UI's point of view,
        // but they deserve different copy.
        final exists = await s.select(
          "select status from appointments where id = @id",
          {'id': P.uuid(appointmentId)},
        );
        if (exists.isEmpty) throw const DocMeRowMissing('appointments');
        throw DocMeRejected(
          'This appointment is ${AppointmentStatus.parse(exists.first['status'] as String?).label.toLowerCase()} '
          'and can no longer be cancelled.',
        );
      }

      await s.run(
        '''
        update availability_slots
           set status = 'open'
         where id = (select slot_id from appointments where id = @id)
        ''',
        {'id': P.uuid(appointmentId)},
      );

      final rows = await s.select(
        _appointmentSelect + ' where a.id = @id',
        {'id': P.uuid(appointmentId)},
      );
      return _mapAppointment(rows.first);
    });
  }

  /// Leaves a rating for a completed appointment.
  ///
  /// Only the patient of a *completed* appointment may rate it, and only once —
  /// `ratings.appointment_id` is unique. Both are enforced by the schema, so the
  /// second attempt returns a conflict rather than double-counting the average.
  Future<Result<void>> rate(
    String userId, {
    required String appointmentId,
    required int stars,
    String? review,
    List<String> tags = const [],
  }) {
    if (stars < 1 || stars > 5) {
      return Future.value(const Err< void >(DocMeFailure(kind: DocMeFailureKind.validation, message: 'Rating must be between 1 and 5.'))) as Future<Result<void>>;





    }

    return _db.asUser<void>(userId, (s) async {
      final providerId = await s.select(
        '''
        select provider_id from appointments
         where id = @id
           and patient_id = @patient
           and status = 'completed'
        ''',
        {'id': P.uuid(appointmentId), 'patient': P.uuid(userId)},
      );
      if (providerId.isEmpty) {
        throw const DocMeRejected('You can only rate a visit once it has taken place.');
      }

      await s.run(
        '''
        insert into ratings (appointment_id, patient_id, provider_id, stars, review, tags)
        values (@appointment, @patient, @provider, @stars, @review, @tags)
        ''',
        {
          'appointment': P.uuid(appointmentId),
          'patient': P.uuid(userId),
          'provider': P.uuid(providerId.first['provider_id'] as String),
          'stars': P.integer(stars),
          'review': P.text(review),
          'tags': P.textArray(tags),
        },
      );
    });
  }

  /// Visits the patient attended, newest first.
  Future<Result<List<VisitRecord>>> visitRecords(
    String userId, {
    int limit = 50,
  }) {
    return _db.asUser<List<VisitRecord>>(userId, (s) async {
      return s.selectAs<VisitRecord>(
        '''
        select vr.id,
               vr.appointment_id,
               vr.provider_id,
               vr.patient_id,
               vr.chief_complaint,
               vr.diagnosis,
               vr.notes,
               vr.follow_up_at,
               vr.created_at,
               pp.full_name as provider_name,
               sp.name     as specialty_name
          from visit_records vr
          join provider_profiles pp on pp.id = vr.provider_id
          left join specialties sp   on sp.id = pp.specialty_id
         where vr.patient_id = @patient
         order by vr.created_at desc
         limit @limit
        ''',
        VisitRecord.fromRow,
        {'patient': P.uuid(userId), 'limit': P.integer(limit)},
      );
    });
  }

  /// The shared projection for an appointment card.
  ///
  /// Provider name comes from `provider_profiles` (world-readable), never from
  /// `profiles` — see `DiscoveryRepository` for why the latter is unreachable.
  /// Initials are computed in SQL rather than in Dart so the same string is used
  /// everywhere a clinician avatar appears.
  static const _appointmentSelect = '''
    select a.id,
           a.patient_id,
           a.provider_id,
           a.service_id,
           a.slot_id,
           a.status,
           a.visit_mode,
           a.reason,
           a.created_at,
           sl.starts_at,
           sl.ends_at,
           pp.full_name as provider_name,
           pp.clinic,
           sp.name      as specialty_name,
           sv.name      as service_name,
           sv.price,
           sv.currency
      from appointments a
      left join availability_slots sl on sl.id = a.slot_id
      left join provider_profiles pp  on pp.id = a.provider_id
      left join specialties sp        on sp.id = pp.specialty_id
      left join services sv           on sv.id = a.service_id
  ''';

  Future<Appointment> _hydrate(DocMeSession s, Appointment bare) async {
    final rows = await s.select(
      _appointmentSelect + ' where a.id = @id',
      {'id': P.uuid(bare.id)},
    );
    return rows.isEmpty ? bare : _mapAppointment(rows.first);
  }

  /// Maps a joined row, deriving initials from the provider name in Dart.
  ///
  /// Initials are computed here rather than in SQL because stripping a honorific
  /// and taking the first letter of each remaining word is too fiddly for one
  /// expression, and `Provider.initials` already gets it right — so this reuses
  /// that exact logic instead of approximating it with a `substring()` regex that
  /// would disagree on names like "Dr. Amara Osei" and "Cher".
  static Appointment _mapAppointment(Map<String, dynamic> row) {
    final appointment = Appointment.fromRow(row);
    final name = appointment.providerName;
    if (name == null || name.isEmpty) return appointment;
    return appointment.copyWith(
      providerInitials: Provider.initialsOf(name),
    );
  }
}
