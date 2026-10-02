import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:patient_app/app/home_shell.dart';
import 'package:patient_app/features/discover/discover_screen.dart';
import 'package:patient_app/features/home/home_screen.dart';
import 'package:patient_app/features/home/widgets/adherence_ring.dart';
import 'package:patient_app/features/home/widgets/next_dose_card.dart';
import 'package:patient_app/features/profile/profile_screen.dart';
import 'package:patient_app/features/records/records_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(CupertinoApp(home: screen));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  group('HomeShell', () {
    testWidgets('boots with the Today tab', (tester) async {
      await tester.pumpWidget(const CupertinoApp(home: HomeShell()));
      await tester.pump();
      expect(find.text('Today'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches tabs', (tester) async {
      await tester.pumpWidget(const CupertinoApp(home: HomeShell()));
      await tester.pump();

      await tester.tap(find.text('Records').last);
      // Not pumpAndSettle: DocMeBackdrop drifts forever by design, so the
      // tree never reaches a quiescent state.
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Conditions'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('HomeScreen', () {
    testWidgets('renders without layout errors', (tester) async {
      await _pump(tester, const HomeScreen());
      expect(find.text('Metformin'), findsWidgets);
    });
  });

  group('NextDoseCard', () {
    testWidgets('shows the next medication', (tester) async {
      await _pump(tester, const NextDoseCard());
      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('Taken'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });
  });

  group('AdherenceRing', () {
    testWidgets('renders a percentage', (tester) async {
      await _pump(tester, const AdherenceRing(value: 0.94));
      expect(find.text('94%'), findsOneWidget);
    });

    testWidgets('clamps out-of-range values', (tester) async {
      await _pump(tester, const AdherenceRing(value: 1.8));
      expect(find.text('100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DiscoverScreen', () {
    testWidgets('renders search and categories', (tester) async {
      await _pump(tester, const DiscoverScreen());
      expect(find.text('Cardiology'), findsWidgets);
      expect(find.text('Dermatology'), findsWidgets);
    });

    testWidgets('filters by search query', (tester) async {
      await _pump(tester, const DiscoverScreen());
      await tester.enterText(find.byType(CupertinoTextField).first, 'Ravi');
      await tester.pumpAndSettle();

      expect(find.text('Dr. Ravi Menon'), findsOneWidget);
      expect(find.text('Dr. Amara Osei'), findsNothing);
    });
  });

  group('RecordsScreen', () {
    testWidgets('prompts for health sync', (tester) async {
      await _pump(tester, const RecordsScreen());
      expect(find.text('Health sync not connected'), findsOneWidget);
    });

    testWidgets('switches record categories', (tester) async {
      await _pump(tester, const RecordsScreen());
      await tester.tap(find.text('Allergies').last);
      await tester.pumpAndSettle();

      expect(find.text('Penicillin'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ProfileScreen', () {
    testWidgets('renders identity, insurance and data controls', (tester) async {
      await _pump(tester, const ProfileScreen());
      expect(find.text('Joseph Kato'), findsOneWidget);
      expect(find.text('INSURANCE'), findsOneWidget);
      expect(find.text('Export health records'), findsOneWidget);
    });
  });
}