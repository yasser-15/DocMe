/// Medication models: the catalogue, what was prescribed, when to take it, and
/// whether it was actually taken.
///
/// This is the loop described in PLAN.md section 9 — a clinician writes a
/// prescription, it becomes a schedule, the schedule fires notifications, and
/// the taps accumulate into [DoseLog] as adherence.
library;

/// An entry in the drug catalogue (`medications`).
class Medication {
  const Medication({
    required this.id,
    required this.genericName,
    required this.countryCode,
    this.rxcui,
    this.nationalCode,
    this.brandName,
    this.form,
    this.strength,
  });

  final String id;
  final String genericName;

  /// RxNorm code — present for US entries.
  final String? rxcui;

  /// National code — present for non-US entries.
  final String? nationalCode;
  final String? brandName;
  final String? form;
  final String? strength;
  final String countryCode;

  /// "Metformin 500mg tablet", preferring the brand when there is one.
  String get label {
    final parts = [
      if (brandName != null && brandName!.isNotEmpty) brandName!,
      genericName,
      if (strength != null && strength!.isNotEmpty) strength!,
    ];
    return parts.join(' ');
  }

  /// Short form for a dense list: "Metformin 500mg".
  String get shortLabel =>
      strength == null || strength!.isEmpty ? genericName : '$genericName $strength';

  static Medication fromRow(Map<String, dynamic> row) => Medication(
    id: row['id']! as String,
    genericName: row['generic_name']! as String,
    countryCode: (row['country_code']! as String).trim(),
    rxcui: row['rxcui'] as String?,
    nationalCode: row['national_code'] as String?,
    brandName: row['brand_name'] as String?,
    form: row['form'] as String?,
    strength: row['strength'] as String?,
  );
}

/// A prescription written by a clinician, joined with its medication.
class Prescription {
  const Prescription({
    required this.id,
    required this.patientId,
    required this.providerId,
    required this.medicationId,
    required this.dosage,
    required this.frequency,
    required this.refillsTotal,
    required this.refillsUsed,
    required this.active,
    required this.createdAt,
    this.visitRecordId,
    this.durationDays,
    this.instructions,
    this.medication,
    this.providerName,
  });

  final String id;
  final String patientId;
  final String providerId;
  final String medicationId;
  final String dosage;
  final String frequency;
  final int refillsTotal;
  final int refillsUsed;
  final bool active;
  final DateTime createdAt;
  final String? visitRecordId;
  final int? durationDays;
  final String? instructions;
  final Medication? medication;
  final String? providerName;

  int get refillsRemaining => refillsTotal - refillsUsed;

  /// A refill is due once the prescription is inactive or the allowance is
  /// spent. Both are surfaced as the same nudge: "talk to your provider".
  bool get needsRefill => !active || refillsRemaining <= 0;

  bool get isLowOnRefills => refillsRemaining > 0 && refillsRemaining <= 1;

  String get title => medication?.label ?? 'Medication';

  static Prescription fromRow(Map<String, dynamic> row) {
    final medId = row['medication_id'] as String?;
    return Prescription(
      id: row['id']! as String,
      patientId: row['patient_id']! as String,
      providerId: row['provider_id']! as String,
      medicationId: medId!,
      dosage: row['dosage']! as String,
      frequency: row['frequency']! as String,
      refillsTotal: (row['refills_total'] as num?)?.toInt() ?? 0,
      refillsUsed: (row['refills_used'] as num?)?.toInt() ?? 0,
      active: row['active'] as bool? ?? true,
      createdAt: row['created_at']! as DateTime,
      visitRecordId: row['visit_record_id'] as String?,
      durationDays: (row['duration_days'] as num?)?.toInt(),
      instructions: row['instructions'] as String?,
      medication: row['generic_name'] == null
          ? null
          : Medication.fromRow(row),
      providerName: row['provider_name'] as String?,
    );
  }
}

/// When a prescription is taken (`medication_schedule`).
///
/// [timesOfDay] are wall-clock `HH:MM` strings rather than instants. That is
/// deliberate: "08:00 and 20:00 every day" must survive a timezone change or a
/// DST shift staying at 08:00 local, which an instant-based schedule cannot do.
/// The concrete instants are computed per day at scheduling time.
class MedicationSchedule {
  const MedicationSchedule({
    required this.id,
    required this.prescriptionId,
    required this.patientId,
    required this.timesOfDay,
    required this.startDate,
    required this.reminderEnabled,
    this.endDate,
    this.prescription,
  });

  final String id;
  final String prescriptionId;
  final String patientId;
  final List<String> timesOfDay;

  /// Midnight-UTC on the first day, matching how Postgres `date` round-trips
  /// through the Dart driver.
  final DateTime startDate;
  final DateTime? endDate;
  final bool reminderEnabled;
  final Prescription? prescription;

  bool get isActive {
    final now = DateTime.now().toUtc();
    if (now.isBefore(startDate)) return false;
    final end = endDate;
    return end == null || !now.isAfter(end);
  }

  int get dailyDoseCount => timesOfDay.length;

  /// The next dose instant at or after [from], or null if the schedule is
  /// finished or disabled.
  ///
  /// [from] defaults to now. Times are interpreted in the device's current local
  /// zone and returned in UTC, matching how they are stored.
  DateTime? nextDose({DateTime? from}) {
    if (!reminderEnabled || !isActive) return null;

    final now = (from ?? DateTime.now()).toUtc();
    // Check today and tomorrow. Checking two days covers every DST edge without
    // a loop, and no legitimate schedule is further out than 24h.
    for (var dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final day = now.add(Duration(days: dayOffset));
      for (final hhmm in timesOfDay) {
        final parts = hhmm.split(':');
        final candidate = DateTime.utc(
          day.year,
          day.month,
          day.day,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        if (!candidate.isBefore(now)) return candidate;
      }
    }
    return null;
  }

  static MedicationSchedule fromRow(Map<String, dynamic> row) {
    final start = row['start_date']! as DateTime;
    return MedicationSchedule(
      id: row['id']! as String,
      prescriptionId: row['prescription_id']! as String,
      patientId: row['patient_id']! as String,
      timesOfDay: _parseTimesOfDay(row['times_of_day']),
      startDate: DateTime.utc(start.year, start.month, start.day),
      endDate: _asDate(row['end_date']),
      reminderEnabled: row['reminder_enabled'] as bool? ?? true,
      prescription: row['rx_dosage'] == null ? null : Prescription.fromRow(row),
    );
  }

  /// Accepts a `time[]` column however the driver chose to decode it.
  ///
  /// Postgres has no single wire representation for `time[]`: the driver may
  /// hand back `LocalTime` objects, `String`s, or `Duration`s depending on
  /// version and codec. Rather than assume one and crash at runtime — which is
  /// what a bare `.cast<String>()` would do — every shape is reduced to `HH:MM`.
  ///
  /// The repositories also normalise this column to `text[]` in SQL, so in
  /// practice the `String` branch is what runs. This is the belt to that
  /// braces: a codec change should degrade to slightly-wrong formatting, never
  /// to a crash on the Today screen.
  static List<String> _parseTimesOfDay(Object? raw) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final value in raw) {
      final text = switch (value) {
        final String s => s,
        final Duration d => _hhmm(d),
        _ => value.toString(),
      };
      final parts = text.split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      out.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    }
    return out;
  }

  /// `LocalTime` decodes to a `Duration` since midnight on some drivers.
  static String _hhmm(Duration d) {
    final total = d.inMinutes;
    final hour = (total ~/ 60) % 24;
    final minute = total % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static DateTime? _asDate(Object? value) {
    if (value is! DateTime) return null;
    return DateTime.utc(value.year, value.month, value.day);
  }
}

/// One scheduled dose, ready to render on the Today screen.
class ScheduledDose {
  const ScheduledDose({
    required this.schedule,
    required this.dueAt,
    this.log,
  });

  final MedicationSchedule schedule;

  /// The instant this dose is due, in UTC.
  final DateTime dueAt;

  /// The existing log, if this dose was already taken or skipped.
  final DoseLog? log;

  bool get isTaken => log?.taken == true;
  bool get isSkipped => log?.skipped == true;
  bool get isPending => log == null;

  String get medicationLabel => schedule.prescription?.title ?? 'Medication';

  String get dosageLabel => schedule.prescription?.dosage ?? '';
}

/// A record that a dose was taken or skipped (`medication_logs`).
///
/// `takenAt` is unique per (schedule, takenAt) in the database, so an offline
/// phone that retries the same tap cannot double-count a dose. That constraint
/// is why [DoseLog.id] may be absent on an insert that was deduplicated away.
class DoseLog {
  const DoseLog({
    required this.scheduleId,
    required this.takenAt,
    this.id,
    this.skipped = false,
    this.note,
  });

  final String? id;
  final String scheduleId;
  final DateTime takenAt;
  final bool skipped;
  final String? note;

  /// "Taken at 08:04" vs "Skipped at 08:04".
  String get actionLabel => skipped ? 'Skipped' : 'Taken';

  /// The complement of [skipped].
  ///
  /// Stored as `skipped` rather than `taken` so a new row defaults to the
  /// medically-safe reading (nothing recorded) instead of to "the patient took
  /// it" — a default that would silently manufacture adherence data.
  bool get taken => !skipped;

  static DoseLog fromRow(Map<String, dynamic> row) => DoseLog(
    id: row['id'] as String?,
    scheduleId: row['schedule_id']! as String,
    takenAt: row['taken_at']! as DateTime,
    skipped: row['skipped'] as bool? ?? false,
    note: row['note'] as String?,
  );
}

/// Adherence over a window, for the ring on the Today screen.
class AdherenceSummary {
  const AdherenceSummary({
    required this.taken,
    required this.skipped,
    required this.dueCount,
    this.currentStreakDays = 0,
  });

  final int taken;
  final int skipped;
  final int dueCount;
  final int currentStreakDays;

  int get logged => taken + skipped;

  /// 0.0–1.0. Returns 0 when nothing has been logged: showing a confident 0%
  /// for "no data" would read as "you are doing badly", which is a different
  /// and much more alarming claim.
  double get ratio {
    if (logged == 0) return 0;
    return taken / logged;
  }

  bool get hasData => logged > 0;

  String get percentLabel => '${(ratio * 100).round()}%';

  static const empty = AdherenceSummary(taken: 0, skipped: 0, dueCount: 0);
}