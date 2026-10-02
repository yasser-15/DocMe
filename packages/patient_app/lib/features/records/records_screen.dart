import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The health vault.
///
/// Every item carries a provenance badge so the user can always tell whether a
/// record was entered by them, written by a clinician, or synced from Apple
/// Health / Health Connect. On a medical record that distinction is not
/// cosmetic — it is the difference between a symptom report and a diagnosis.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  int _filter = 0;

  static const _filters = ['Conditions', 'Allergies', 'Medications', 'Visits'];

  static const _byFilter = <List<_Record>>[
    [
      _Record('Hypertension', 'Diagnosed 2021 · Dr. Amara Osei', _Source.provider),
      _Record('Type 2 diabetes', 'Diagnosed 2023 · Dr. Amara Osei', _Source.provider),
      _Record('Seasonal allergic rhinitis', 'Reported by you', _Source.manual),
    ],
    [
      _Record('Penicillin', 'Hives · reported 2019', _Source.manual),
      _Record('Peanuts', 'Anaphylaxis · reported 2015', _Source.healthPlatform),
    ],
    [
      _Record('Metformin 500mg', 'Daily · 1 ref left', _Source.provider),
      _Record('Amlodipine 5mg', 'Daily', _Source.provider),
      _Record('Loratadine 10mg', 'As needed', _Source.healthPlatform),
    ],
    [
      _Record('Dr. Amara Osei · Cardiology', '12 Sept · notes published', _Source.provider),
      _Record('Dr. Ravi Menon · Dermatology', '28 Aug · notes published', _Source.provider),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final records = _byFilter[_filter];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // The critical product promise: what is synced, and what is not.
        const _SyncStatusBanner(),
        const SizedBox(height: 18),

        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => GlassChip(
              label: _filters[i],
              selected: i == _filter,
              onTap: () => setState(() => _filter = i),
            ),
          ),
        ),
        const SizedBox(height: 22),

        if (records.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.doc_text,
            title: 'Nothing recorded yet',
            message: 'Records added by a clinician or synced from your health '
                'platform will appear here.',
          )
        else
          GlassGroupedSection(
            header: SectionHeader(
              '${_filters[_filter]} · ${records.length}',
            ),
            children: [
              for (final r in records) _RecordTile(record: r),
            ],
          ),

        const SizedBox(height: 26),
        const _AddRecordButton(),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final _Record record;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      onTap: () {}, // TODO(M4): record detail.
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: record.source.color.withValues(alpha: 0.18),
        ),
        child: Icon(record.source.icon, size: 17, color: record.source.color),
      ),
      title: Text(
        record.title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        record.subtitle,
        style: const TextStyle(fontSize: 12.5, color: DocMeColors.inkDarkMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: record.source.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              record.source.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: record.source.color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: DocMeColors.inkDarkMuted,
          ),
        ],
      ),
    );
  }
}

class _AddRecordButton extends StatelessWidget {
  const _AddRecordButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      // GlassButton takes `onTap` (GlassIconButton takes `onPressed`).
      child: GlassButton(
        icon: const Icon(CupertinoIcons.add, size: 20),
        label: 'Add record',
        width: 168,
        height: 46,
        onTap: () {}, // TODO(M4): manual entry form.
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      accent: DocMeAccent.primary,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.heart_fill,
            size: 20,
            color: DocMeColors.coral,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health sync not connected',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Connect Apple Health or Health Connect to import vitals, '
                  'medications and allergies automatically.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: DocMeColors.inkDarkMuted,
                  ),
                ),
                const SizedBox(height: 12),
                GlassButton(
                  icon: const Icon(CupertinoIcons.link, size: 15),
                  label: 'Connect',
                  width: 128,
                  height: 38,
                  onTap: () {}, // TODO(M4): permission flow.
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Source {
  manual('Manual', DocMeColors.violet, CupertinoIcons.person),
  provider('Clinician', DocMeColors.mint, CupertinoIcons.checkmark_seal_fill),
  healthPlatform('Health app', DocMeColors.sky, CupertinoIcons.heart_fill);

  const _Source(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

class _Record {
  const _Record(this.title, this.subtitle, this.source);

  final String title;
  final String subtitle;
  final _Source source;
}