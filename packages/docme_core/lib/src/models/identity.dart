/// Identity models: who the user is, and who they can see.
///
/// Row shapes here mirror `profiles`, `specialties` and `provider_profiles` in
/// `supabase/migrations/0002_schema.sql`. Every `fromRow` reads columns by
/// name, so a schema rename surfaces as an immediate type error at the
/// repository that maps it, rather than as a `null` reaching the UI.
library;

import 'package:characters/characters.dart';

/// `profiles.role`.
enum UserRole {
  patient,
  provider;

  static UserRole parse(String? raw) => switch (raw) {
    'patient' => UserRole.patient,
    'provider' => UserRole.provider,
    _ => throw FormatException(
      'profiles.role has an unexpected value: $raw',
    ),
  };

  String get toDb => name;
}

/// The signed-in user's own row.
///
/// Always loaded as [UserRole.patient] in this app; the provider variant of the
/// product is a different binary (M7).
class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.countryCode,
    required this.locale,
    this.phone,
    this.city,
    this.region,
    this.latitude,
    this.longitude,
    this.avatarUrl,
    required this.createdAt,
  });

  final String id;
  final UserRole role;
  final String fullName;
  final String countryCode;
  final String locale;
  final String? phone;
  final String? city;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String? avatarUrl;
  final DateTime createdAt;

  /// True once the device has a usable location for discovery filtering.
  bool get hasLocation => latitude != null && longitude != null;

  /// "Kampala · Central Region", falling back to whichever part is known.
  String get localityLabel {
    final parts = [city, region].whereType<String>().where((s) => s.isNotEmpty);
    if (parts.isEmpty) return 'Location not set';
    return parts.join(' · ');
  }

  /// Two-letter country code uppercased. Postgres stores `char(2)`, which
  /// pads with spaces on read, so trailing blanks are stripped.
  String get country => countryCode.trim().toUpperCase();

  /// Initials for the avatar fallback. Handles single-word names and skips a
  /// title, so "Dr. Amara Osei" is "AO". Delegates to [Provider.initialsOf] so
  /// a patient's initials and a clinician's initials come from one rule.
  String get initials => Provider.initialsOf(fullName);

  static Profile fromRow(Map<String, dynamic> row) => Profile(
    id: row['id']! as String,
    role: UserRole.parse(row['role'] as String?),
    fullName: row['full_name']! as String,
    countryCode: (row['country_code']! as String).trim(),
    locale: row['locale'] as String? ?? 'en',
    phone: row['phone'] as String?,
    city: row['city'] as String?,
    region: row['region'] as String?,
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
    avatarUrl: row['avatar_url'] as String?,
    createdAt: row['created_at']! as DateTime,
  );

  Profile copyWith({
    String? fullName,
    String? phone,
    String? city,
    String? region,
    double? latitude,
    double? longitude,
  }) => Profile(
    id: id,
    role: role,
    fullName: fullName ?? this.fullName,
    countryCode: countryCode,
    locale: locale,
    phone: phone ?? this.phone,
    city: city ?? this.city,
    region: region ?? this.region,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    avatarUrl: avatarUrl,
    createdAt: createdAt,
  );
}

/// `specialties`. World-readable reference data — see `medications_read` and
/// friends in `0003_rls.sql`.
class Specialty {
  const Specialty({
    required this.id,
    required this.slug,
    required this.name,
    this.icon,
    this.category,
  });

  final String id;
  final String slug;
  final String name;
  final String? icon;
  final String? category;

  static Specialty fromRow(Map<String, dynamic> row) => Specialty(
    id: row['id']! as String,
    slug: row['slug']! as String,
    name: row['name']! as String,
    icon: row['icon'] as String?,
    category: row['category'] as String?,
  );
}

/// A clinician, as discovery needs them.
///
/// A flat projection of `profiles` ⋈ `provider_profiles` ⋈ `specialties` plus
/// the aggregate rating and distance that PostGIS computes. Deliberately not the
/// three tables separately: the screens that render a provider always need all
/// of it, and splitting it would mean every call site re-joining them.
class Provider {
  const Provider({
    required this.id,
    required this.fullName,
    this.specialty,
    this.specialtySlug,
    this.clinic,
    this.bio,
    this.licenseNo,
    this.yearsExperience = 0,
    this.languages = const [],
    this.isVerified = false,
    this.city,
    this.region,
    this.latitude,
    this.longitude,
    this.averageRating,
    this.reviewCount = 0,
    this.distanceKm,
    this.fromPrice,
    this.currency,
  });

  final String id;
  final String fullName;
  final String? specialty;
  final String? specialtySlug;
  final String? clinic;
  final String? bio;
  final String? licenseNo;
  final int yearsExperience;
  final List<String> languages;
  final bool isVerified;
  final String? city;
  final String? region;
  final double? latitude;
  final double? longitude;

  /// Null when there are no ratings yet. Distinct from zero — "unrated" and
  /// "rated 0" must not render the same.
  final double? averageRating;
  final int reviewCount;

  /// Distance from the search origin, in km. Null when no origin was supplied.
  final double? distanceKm;

  /// Cheapest published service price, so a result card can show a number.
  final num? fromPrice;
  final String? currency;

/// "Dr. Amara Osei" -> "AO".
  ///
  /// Static so every avatar in the app derives initials the same way — a card,
  /// an appointment row and a prescription header must not disagree about what a
  /// clinician's initials are.
  ///
  /// A leading honorific is skipped, since "Dr" is the doctor's title, not part
  /// of their name: "Dr. Amara Osei" is "AO", not "DA".
  static String initialsOf(String fullName) {
    final meaningful = fullName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_titles.contains(w.toLowerCase()))
        .toList();
    if (meaningful.isEmpty) return '?';
    final letters = meaningful
        .map((w) => w.characters.first.toUpperCase())
        .take(meaningful.length > 1 ? 2 : 1)
        .join();
    return letters;
  }

  static const _titles = {'dr', 'dr.', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.'};

  static Provider fromRow(Map<String, dynamic> row) => Provider(
    id: row['id']! as String,
    fullName: row['full_name']! as String,
    specialty: row['specialty_name'] as String?,
    specialtySlug: row['specialty_slug'] as String?,
    clinic: row['clinic'] as String?,
    bio: row['bio'] as String?,
    licenseNo: row['license_no'] as String?,
    yearsExperience: (row['years_experience'] as num?)?.toInt() ?? 0,
    languages:
        (row['languages'] as List?)?.cast<String>() ?? const <String>[],
    isVerified: row['is_verified'] as bool? ?? false,
    city: row['city'] as String?,
    region: row['region'] as String?,
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
    averageRating: (row['average_rating'] as num?)?.toDouble(),
    reviewCount: (row['review_count'] as num?)?.toInt() ?? 0,
    distanceKm: (row['distance_km'] as num?)?.toDouble(),
    fromPrice: row['from_price'] as num?,
    currency: row['currency'] as String?,
  );

  /// See [initialsOf]. An instance getter purely so a widget can read
  /// `provider.initials` directly.
  String get initials => initialsOf(fullName);
}