import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Find care near you.
///
/// Category + city/region filtering, then ranked results. Geo resolution and
/// PostGIS radius queries land in M2; this screen is the layout contract.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String _category = 'All';
  String _query = '';

  static const _categories = <String>[
    'All',
    'Cardiology',
    'Dermatology',
    'Paediatrics',
    'Dental',
    'Ophthalmology',
    'Neurology',
  ];

  static const _services = <_Service>[
    _Service(
      'Dr. Amara Osei',
      'Cardiology',
      'St. Mary’s Clinic',
      4.9,
      212,
      '1.2 km',
      '\$120',
      DocMeAccent.info,
    ),
    _Service(
      'Dr. Ravi Menon',
      'Dermatology',
      'Skin & Laser Centre',
      4.7,
      158,
      '2.4 km',
      '\$85',
      DocMeAccent.neutral,
    ),
    _Service(
      'Dr. Lena Fischer',
      'Neurology',
      'Northgate Health',
      4.8,
      96,
      '3.1 km',
      '\$150',
      DocMeAccent.primary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _services
        : _services
              .where(
                (s) => s.doctor.toLowerCase().contains(_query.toLowerCase()) ||
                    s.specialty.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        GlassTextField(
          placeholder: 'Doctor, specialty or clinic',
          prefixIcon: const Icon(CupertinoIcons.search, size: 18),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 16),

        // GlassChip.label is a String, not a Widget.
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = _categories[i];
              return GlassChip(
                label: c,
                selected: c == _category,
                onTap: () => setState(() => _category = c),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        const _LocationBar(),
        const SizedBox(height: 22),

        SectionHeader(
          'Near you',
          trailing: Text(
            '${visible.length} results',
            style: const TextStyle(fontSize: 12, color: DocMeColors.inkDarkMuted),
          ),
        ),
        if (visible.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.search,
            title: 'No matches',
            message: 'Try a different specialty or clear your search.',
          )
        else
          for (final s in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ServiceCard(service: s),
            ),
      ],
    );
  }
}

class _LocationBar extends StatelessWidget {
  const _LocationBar();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () {}, // TODO(M2): geolocate + reverse geocode.
      child: Row(
        children: [
          const Icon(CupertinoIcons.location_fill, size: 18, color: DocMeColors.mint),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kampala · Central Region',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Using your location',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DocMeColors.inkDarkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_down,
            size: 15,
            color: DocMeColors.inkDarkMuted,
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});

  final _Service service;

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      onTap: () {}, // TODO(M2): provider detail route.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      service.accent.color.withValues(alpha: 0.35),
                      service.accent.color.withValues(alpha: 0.12),
                    ],
                  ),
                ),
                child: Text(
                  service.doctor.substring(4, 5),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: service.accent.color,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.doctor,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${service.specialty} · ${service.clinic}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: DocMeColors.inkDarkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                service.price,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DocMeColors.mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(CupertinoIcons.star_fill, size: 14, color: DocMeColors.amber),
              const SizedBox(width: 5),
              Text(
                '${service.rating}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 5),
              Text(
                '(${service.reviews})',
                style: const TextStyle(fontSize: 12, color: DocMeColors.inkDarkMuted),
              ),
              const SizedBox(width: 16),
              const Icon(CupertinoIcons.location, size: 13, color: DocMeColors.inkDarkMuted),
              const SizedBox(width: 5),
              Text(
                service.distance,
                style: const TextStyle(fontSize: 12, color: DocMeColors.inkDarkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Service {
  const _Service(
    this.doctor,
    this.specialty,
    this.clinic,
    this.rating,
    this.reviews,
    this.distance,
    this.price,
    this.accent,
  );

  final String doctor;
  final String specialty;
  final String clinic;
  final double rating;
  final int reviews;
  final String distance;
  final String price;
  final DocMeAccent accent;
}