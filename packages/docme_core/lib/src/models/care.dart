/// Care-delivery models: what a provider offers, when they are free, and the
/// appointments that result.
///
/// Mirrors `services`, `availability_slots`, `appointments`, `visit_records` and
/// `ratings`.
library;

import 'identity.dart';

/// `services.visit_mode`.
enum VisitMode {
  inPerson,
  video,
  homeVisit;

  static VisitMode parse(String? raw) => switch (raw) {
    'in_person' => VisitMode.inPerson,
    'video' => VisitMode.video,
    'home_visit' => VisitMode.homeVisit,
    _ => throw FormatException('services.visit_mode: unexpected value $raw'),
  };

  static VisitMode? tryParse(String? raw) => switch (raw) {
    'in_person' => VisitMode.inPerson,
    'video' => VisitMode.video,
    'home_visit' => VisitMode.homeVisit,
    _ => null,
  };

  String get toDb => switch (this) {
    VisitMode.inPerson => 'in_person',
    VisitMode.video => 'video',
    VisitMode.homeVisit => 'home_visit',
  };

  String get label => switch (this) {
    VisitMode.inPerson => 'In person',
    VisitMode.video => 'Video call',
    VisitMode.homeVisit => 'Home visit',
  };
}

/// `appointments.status`.
///
/// The ordering matters: `isPending` drives which actions the UI offers, and
/// `isCancellable` is deliberately wider than `isPending` because a confirmed
/// appointment can still be cancelled.
enum AppointmentStatus {
  requested,
  confirmed,
  completed,
  cancelled,
  noShow;

  static AppointmentStatus parse(String? raw) => switch (raw) {
    'requested' => AppointmentStatus.requested,
    'confirmed' => AppointmentStatus.confirmed,
    'completed' => AppointmentStatus.completed,
    'cancelled' => AppointmentStatus.cancelled,
    'no_show' => AppointmentStatus.noShow,
    _ => throw FormatException('appointments.status: unexpected value $raw'),
  };

  static AppointmentStatus? tryParse(String? raw) => switch (raw) {
    'requested' => AppointmentStatus.requested,
    'confirmed' => AppointmentStatus.confirmed,
    'completed' => AppointmentStatus.completed,
    'cancelled' => AppointmentStatus.cancelled,
    'no_show' => AppointmentStatus.noShow,
    _ => null,
  };

  String get toDb => switch (this) {
    AppointmentStatus.requested => 'requested',
    AppointmentStatus.confirmed => 'confirmed',
    AppointmentStatus.completed => 'completed',
    AppointmentStatus.cancelled => 'cancelled',
    AppointmentStatus.noShow => 'no_show',
  };

  String get label => switch (this) {
    AppointmentStatus.requested => 'Awaiting confirmation',
    AppointmentStatus.confirmed => 'Confirmed',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
    AppointmentStatus.noShow => 'No show',
  };

  /// Statuses that still occupy the slot.
  bool get isActive =>
      this == AppointmentStatus.requested || this == AppointmentStatus.confirmed;

  bool get isCancellable => isActive;

  /// A completed appointment is the precondition that grants a clinician read
  /// access to the patient's `health_records`. See `is_completed_appointment()`
  /// in `0003_rls.sql`.
  bool get grantsRecordAccess => this == AppointmentStatus.completed;
}

/// A bookable service offered by a provider.
class ServiceOffering {
  const ServiceOffering({
    required this.id,
    required this.providerId,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationMin,
    required this.visitMode,
    this.description,
    this.isEmergency = false,
    this.specialtyName,
  });

  final String id;
  final String providerId;
  final String name;
  final num price;
  final String currency;
  final int durationMin;
  final VisitMode visitMode;
  final String? description;

  /// Emergency-capable services surface in the home-visit dispatch flow.
  final bool isEmergency;
  final String? specialtyName;

  String get priceLabel => '$price $currency';

  static ServiceOffering fromRow(Map<String, dynamic> row) => ServiceOffering(
    id: row['id']! as String,
    providerId: row['provider_id']! as String,
    name: row['name']! as String,
    price: row['price']! as num,
    currency: (row['currency']! as String).trim(),
    durationMin: (row['duration_min'] as num?)?.toInt() ?? 30,
    visitMode: VisitMode.parse(row['visit_mode'] as String?),
    description: row['description'] as String?,
    isEmergency: row['is_emergency'] as bool? ?? false,
    specialtyName: row['specialty_name'] as String?,
  );
}

/// A bookable window in a provider's diary.
class AvailabilitySlot {
  const AvailabilitySlot({
    required this.id,
    required this.providerId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.recurrenceRule,
  });

  final String id;
  final String providerId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String? recurrenceRule;

  Duration get duration => endsAt.difference(startsAt);

  bool get isOpen => status == 'open';

  static AvailabilitySlot fromRow(Map<String, dynamic> row) => AvailabilitySlot(
    id: row['id']! as String,
    providerId: row['provider_id']! as String,
    startsAt: row['starts_at']! as DateTime,
    endsAt: row['ends_at']! as DateTime,
    status: row['status']! as String,
    recurrenceRule: row['recurrence_rule'] as String?,
  );
}

/// A booking, joined with enough provider and service detail to render a card.
///
/// Joined rather than bare so the Today screen's "next appointment" tile needs
/// one query, not a fan-out per row.
class Appointment {
  const Appointment({
    required this.id,
    required this.patientId,
    required this.providerId,
    required this.status,
    required this.visitMode,
    required this.createdAt,
    this.serviceId,
    this.slotId,
    this.reason,
    this.providerName,
    this.providerInitials,
    this.specialtyName,
    this.clinic,
    this.serviceName,
    this.startsAt,
    this.endsAt,
    this.price,
    this.currency,
  });

  final String id;
  final String patientId;
  final String providerId;
  final AppointmentStatus status;
  final VisitMode visitMode;
  final DateTime createdAt;
  final String? serviceId;
  final String? slotId;
  final String? reason;

  // Joined from provider/service/slot. Null when the row was booked without one
  // (an emergency dispatch has no slot).
  final String? providerName;
  final String? providerInitials;
  final String? specialtyName;
  final String? clinic;
  final String? serviceName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final num? price;
  final String? currency;

  bool get isUpcoming {
    if (!status.isActive) return false;
    final start = startsAt;
    if (start == null) return false;
    return start.isAfter(DateTime.now().toUtc());
  }

  /// Title line for a card: the service if there is one, else the visit mode.
  String get title => serviceName ?? visitMode.label;

  /// "Cardiology · St Mary's Clinic", skipping whatever is absent.
  String get subtitle {
    final parts = [
      if (specialtyName != null && specialtyName!.isNotEmpty) specialtyName!,
      if (clinic != null && clinic!.isNotEmpty) clinic!,
    ];
    if (parts.isEmpty) return visitMode.label;
    return parts.join(' · ');
  }

  /// Copy with the joined fields filled in.
  ///
  /// Only the display-only joined columns are overridable. Identity, status and
  /// mode come straight from the `appointments` row and are deliberately not
  /// settable, so a derived copy can never disagree with the row it came from —
  /// a mutated status on a card would tell the user something the database does
  /// not say.
  Appointment copyWith({
    String? providerName,
    String? providerInitials,
    String? specialtyName,
    String? clinic,
    String? serviceName,
    DateTime? startsAt,
    DateTime? endsAt,
    num? price,
    String? currency,
  }) => Appointment(
    id: id,
    patientId: patientId,
    providerId: providerId,
    status: status,
    visitMode: visitMode,
    createdAt: createdAt,
    serviceId: serviceId,
    slotId: slotId,
    reason: reason,
    providerName: providerName ?? this.providerName,
    providerInitials: providerInitials ?? this.providerInitials,
    specialtyName: specialtyName ?? this.specialtyName,
    clinic: clinic ?? this.clinic,
    serviceName: serviceName ?? this.serviceName,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    price: price ?? this.price,
    currency: currency ?? this.currency,
  );

  static Appointment fromRow(Map<String, dynamic> row) => Appointment(
    id: row['id']! as String,
    patientId: row['patient_id']! as String,
    providerId: row['provider_id']! as String,
    status: AppointmentStatus.parse(row['status'] as String?),
    visitMode: VisitMode.parse(row['visit_mode'] as String?),
    createdAt: row['created_at']! as DateTime,
    serviceId: row['service_id'] as String?,
    slotId: row['slot_id'] as String?,
    reason: row['reason'] as String?,
    providerName: row['provider_name'] as String?,
    providerInitials: row['provider_initials'] as String?,
    specialtyName: row['specialty_name'] as String?,
    clinic: row['clinic'] as String?,
    serviceName: row['service_name'] as String?,
    startsAt: row['starts_at'] as DateTime?,
    endsAt: row['ends_at'] as DateTime?,
    price: row['price'] as num?,
    currency: row['currency'] as String?,
  );
}

/// What a clinician wrote after a visit.
///
/// Visible to the patient and to that clinician only. Note the asymmetry: the
/// patient may also read their `health_records`, but a clinician needs a
/// *completed* appointment to do so.
class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.appointmentId,
    required this.providerId,
    required this.patientId,
    required this.createdAt,
    this.chiefComplaint,
    this.diagnosis,
    this.notes,
    this.followUpAt,
    this.providerName,
    this.specialtyName,
  });

  final String id;
  final String appointmentId;
  final String providerId;
  final String patientId;
  final DateTime createdAt;
  final String? chiefComplaint;
  final String? diagnosis;
  final String? notes;
  final DateTime? followUpAt;
  final String? providerName;
  final String? specialtyName;

  bool get hasFollowUp => followUpAt != null;

  static VisitRecord fromRow(Map<String, dynamic> row) => VisitRecord(
    id: row['id']! as String,
    appointmentId: row['appointment_id']! as String,
    providerId: row['provider_id']! as String,
    patientId: row['patient_id']! as String,
    createdAt: row['created_at']! as DateTime,
    chiefComplaint: row['chief_complaint'] as String?,
    diagnosis: row['diagnosis'] as String?,
    notes: row['notes'] as String?,
    followUpAt: row['follow_up_at'] as DateTime?,
    providerName: row['provider_name'] as String?,
    specialtyName: row['specialty_name'] as String?,
  );
}

/// A patient's own clinical entries. The PHI at the centre of the product.
class HealthRecordEntry {
  const HealthRecordEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.source,
    required this.createdAt,
    this.codeSystem,
    this.code,
    this.notes,
    this.occurredAt,
  });

  final String id;
  final String type;
  final String title;
  final String source;
  final DateTime createdAt;
  final String? codeSystem;
  final String? code;
  final String? notes;
  final DateTime? occurredAt;

  static HealthRecordEntry fromRow(Map<String, dynamic> row) => HealthRecordEntry(
    id: row['id']! as String,
    type: row['type']! as String,
    title: row['title']! as String,
    source: row['source']! as String,
    createdAt: row['created_at']! as DateTime,
    codeSystem: row['code_system'] as String?,
    code: row['code'] as String?,
    notes: row['notes'] as String?,
    occurredAt: row['occurred_at'] as DateTime?,
  );
}

/// A rating attached to a completed appointment.
class Rating {
  const Rating({
    required this.id,
    required this.appointmentId,
    required this.providerId,
    required this.stars,
    required this.createdAt,
    this.review,
    this.tags = const [],
  });

  final String id;
  final String appointmentId;
  final String providerId;
  final int stars;
  final DateTime createdAt;
  final String? review;
  final List<String> tags;

  static Rating fromRow(Map<String, dynamic> row) => Rating(
    id: row['id']! as String,
    appointmentId: row['appointment_id']! as String,
    providerId: row['provider_id']! as String,
    stars: (row['stars']! as num).toInt(),
    createdAt: row['created_at']! as DateTime,
    review: row['review'] as String?,
    tags: (row['tags'] as List?)?.cast<String>() ?? const <String>[],
  );
}

/// Aggregate of several ratings, for the provider card.
class RatingSummary {
  const RatingSummary({this.average, this.count = 0});

  final double? average;
  final int count;

  bool get hasRatings => average != null && count > 0;

  /// One decimal place, which is all a card needs and avoids implying precision
  /// the data does not have.
  String get label => average == null ? 'New' : average!.toStringAsFixed(1);
}

/// Convenience for screens that hold a [Provider] plus its joined ratings.
class ProviderWithRating {
  const ProviderWithRating(this.provider, this.rating);
  final Provider provider;
  final RatingSummary rating;
}