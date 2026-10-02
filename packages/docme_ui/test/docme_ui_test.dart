import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:docme_ui/docme_ui.dart';

Widget _host(Widget child) => CupertinoApp(
  home: CupertinoPageScaffold(
    child: Stack(
      children: [
        const DocMeBackdrop(),
        Center(child: child),
      ],
    ),
  ),
);

void main() {
  group('DocMeAccent', () {
    test('exposes a distinct colour per accent', () {
      final colours = DocMeAccent.values.map((a) => a.color.toARGB32()).toSet();
      expect(colours.length, DocMeAccent.values.length);
    });
  });

  group('DocMeBackdrop', () {
    testWidgets('paints behind content without overflowing', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Stack(
              children: [
                DocMeBackdrop(),
                Center(child: Text('DocMe')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('DocMe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ContentCard', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        _host(
          const ContentCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hypertension'),
                Text('Diagnosed 2021'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Hypertension'), findsOneWidget);
      expect(find.text('Diagnosed 2021'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          ContentCard(
            onTap: () => taps++,
            child: const Text('Tap me'),
          ),
        ),
      );
      await tester.tap(find.text('Tap me'));
      expect(taps, 1);
    });
  });

  group('SectionHeader', () {
    testWidgets('renders label and trailing', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionHeader('Near you'),
              SectionHeader('Conditions · 3', trailing: Text('12 results')),
            ],
          ),
        ),
      );
      expect(find.text('NEAR YOU'), findsOneWidget);
      expect(find.text('CONDITIONS · 3'), findsOneWidget);
      expect(find.text('12 results'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows icon, title and message', (tester) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: CupertinoIcons.doc_text,
            title: 'Nothing recorded yet',
            message: 'Records will appear here.',
          ),
        ),
      );
      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(find.text('Records will appear here.'), findsOneWidget);
    });
  });

  group('MetricTile', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(
        _host(
          const MetricTile(label: 'Blood pressure', value: '124/79'),
        ),
      );
      expect(find.text('Blood pressure'), findsOneWidget);
      expect(find.text('124/79'), findsOneWidget);
    });
  });
}