import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Identity, coverage, connected sources, and data controls.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        const _IdentityCard(),
        const SizedBox(height: 26),

        const SectionHeader('Insurance'),
        GlassGroupedSection(
          children: [
            GlassListTile(
              leading: const Icon(CupertinoIcons.shield_fill, color: DocMeColors.mint),
              title: const Text('HealthGuard Basic'),
              subtitle: const Text('Renews 1 Oct · covers 4 specialists'),
              trailing: GlassListTile.chevron,
              onTap: () {}, // TODO(M5): manage subscription.
            ),
            GlassListTile(
              leading: const Icon(CupertinoIcons.checkmark_shield_fill, color: DocMeColors.sky),
              title: const Text('Check provider coverage'),
              subtitle: const Text('Is this doctor covered by my plan?'),
              trailing: GlassListTile.chevron,
              onTap: () {}, // TODO(M5): coverage lookup.
            ),
          ],
        ),
        const SizedBox(height: 26),

        const SectionHeader('Connected sources'),
        GlassGroupedSection(
          children: [
            GlassListTile(
              leading: const Icon(CupertinoIcons.heart_fill, color: DocMeColors.coral),
              title: const Text('Apple Health'),
              subtitle: const Text('Not connected'),
              trailing: const Text(
                'Connect',
                style: TextStyle(fontSize: 14, color: DocMeColors.mint),
              ),
              onTap: () {}, // TODO(M4).
            ),
            GlassListTile(
              leading: const Icon(CupertinoIcons.waveform_path_ecg, color: DocMeColors.sky),
              title: const Text('Health Connect'),
              subtitle: const Text('Not connected'),
              trailing: const Text(
                'Connect',
                style: TextStyle(fontSize: 14, color: DocMeColors.mint),
              ),
              onTap: () {}, // TODO(M4).
            ),
          ],
        ),
        const SizedBox(height: 26),

        const SectionHeader('Your data'),
        GlassGroupedSection(
          children: [
            GlassListTile(
              leading: const Icon(CupertinoIcons.arrow_down_doc, color: DocMeColors.violet),
              title: const Text('Export health records'),
              subtitle: const Text('FHIR-style JSON or PDF'),
              trailing: GlassListTile.chevron,
              onTap: () {}, // TODO(M5).
            ),
            GlassListTile(
              leading: const Icon(CupertinoIcons.hand_raised_fill, color: DocMeColors.amber),
              title: const Text('Sharing & consent'),
              subtitle: const Text('Control what clinicians can see'),
              trailing: GlassListTile.chevron,
              onTap: () {}, // TODO(M5).
            ),
            GlassListTile(
              leading: const Icon(CupertinoIcons.globe, color: DocMeColors.inkDarkMuted),
              title: const Text('Region & language'),
              subtitle: const Text('Kampala, Uganda · English'),
              trailing: GlassListTile.chevron,
              onTap: () {}, // TODO(M5): drives the country adapter.
            ),
          ],
        ),
        const SizedBox(height: 26),

        Center(
          child: GlassButton(
            icon: const Icon(CupertinoIcons.person_crop_circle, size: 17),
            label: 'Sign out',
            width: 190,
            height: 46,
            onTap: () {}, // TODO(M2): auth.
          ),
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  DocMeColors.mint.withValues(alpha: 0.5),
                  DocMeColors.sky.withValues(alpha: 0.35),
                ],
              ),
            ),
            child: const Text(
              'JK',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Joseph Kato',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Patient · since March 2025',
                  style: TextStyle(fontSize: 12.5, color: DocMeColors.inkDarkMuted),
                ),
              ],
            ),
          ),
          // GlassIconButton takes `onPressed`.
          GlassIconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 17),
            onPressed: () {}, // TODO(M2).
            semanticLabel: 'Edit profile',
          ),
        ],
      ),
    );
  }
}