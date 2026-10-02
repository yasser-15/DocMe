import 'package:flutter/cupertino.dart';
import 'package:docme_ui/docme_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'widgets/adherence_ring.dart';
import 'widgets/next_dose_card.dart';

/// The Today dashboard.
///
/// This is the app's centre of gravity: what is happening next, what the user
/// must take next, and how well they are complying.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      // GlassScaffold already inserts top padding for the app bar; these only
      // handle horizontal rhythm and the gap above the first card.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        const _Greeting(),
        const SizedBox(height: 22),

        // Hero surface — the one place premium quality is spent here.
        const NextDoseCard(),
        const SizedBox(height: 16),

        const _NextAppointmentCard(),
        const SizedBox(height: 26),

        const SectionHeader('Adherence'),
        const _AdherencePanel(),
        const SizedBox(height: 26),

        const SectionHeader('Quick actions'),
        const _QuickActions(),
        const SizedBox(height: 26),

        const _EmergencyCard(),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    const hour = 0; // TODO(M2): bind to real clock once auth/profile exists.
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Tuesday, 15 September',
          style: TextStyle(fontSize: 14, color: DocMeColors.inkDarkMuted),
        ),
      ],
    );
  }
}

class _NextAppointmentCard extends StatelessWidget {
  const _NextAppointmentCard();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      accent: DocMeAccent.info,
      onTap: () {}, // TODO(M2): push provider detail route.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'NEXT APPOINTMENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: DocMeColors.inkDarkMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: DocMeColors.sky.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Confirmed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DocMeColors.sky,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Dr. Amara Osei',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cardiology · St. Mary’s Clinic',
            style: TextStyle(fontSize: 13.5, color: DocMeColors.inkDarkMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                CupertinoIcons.clock,
                size: 15,
                color: DocMeColors.mint,
              ),
              const SizedBox(width: 7),
              const Text(
                '10:30 · Today',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              const Icon(
                CupertinoIcons.location,
                size: 15,
                color: DocMeColors.mint,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Room 402',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DocMeColors.inkDark.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdherencePanel extends StatelessWidget {
  const _AdherencePanel();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const SizedBox(
            width: 82,
            height: 82,
            child: AdherenceRing(value: 0.92),
          ),
          const SizedBox(width: 22),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MetricTile(label: 'Doses taken', value: '138'),
                SizedBox(height: 14),
                MetricTile(
                  label: 'On-time streak',
                  value: '11 d',
                  accent: DocMeAccent.medication,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // GlassIconButton on the page platter — NOT inside a ContentCard, to
        // avoid nested refraction.
        _action(CupertinoIcons.capsule_fill, 'Log dose', DocMeAccent.medication),
        _action(CupertinoIcons.book_fill, 'Records', DocMeAccent.primary),
        _action(CupertinoIcons.chat_bubble_2_fill, 'Message', DocMeAccent.info),
      ],
    );
  }

  Widget _action(IconData icon, String label, DocMeAccent accent) {
    return Expanded(
      child: Column(
        children: [
          GlassIconButton(
            icon: Icon(icon, size: 22, color: accent.color),
            onPressed: () {}, // TODO(M2)
            size: 56,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DocMeColors.inkDarkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard();

  @override
  Widget build(BuildContext context) {
    return ContentCard(
      accent: DocMeAccent.emergency,
      onTap: () {}, // TODO(M2): dispatch request flow.
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DocMeColors.coral.withValues(alpha: 0.18),
            ),
            child: const Icon(
              CupertinoIcons.bolt_fill,
              color: DocMeColors.coral,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency home visit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Request a provider to come to you',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: DocMeColors.inkDarkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: DocMeColors.inkDarkMuted,
          ),
        ],
      ),
    );
  }
}