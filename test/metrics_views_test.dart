// Metrics comparison: best / worst per column, ranks, overall score, and
// the table fitting a 14" laptop window without sideways scrolling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metric_definitions.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metrics_dashboard.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/metrics_table.dart';

Metrics metrics({
  int makespanH = 10,
  int tardinessH = 0,
  int delayed = 0,
  int idleMin = 0,
}) =>
    Metrics(
      idle: Duration(minutes: idleMin),
      totalJobs: 12,
      maxDelay: Duration.zero,
      avarageProcessingTime: const Duration(hours: 1),
      avarageDelayTime: Duration(hours: tardinessH) ~/ 12,
      avarageLatenessTime: Duration.zero,
      avarageEarlinessTime: const Duration(minutes: 30),
      delayedJobs: delayed,
      makespan: Duration(hours: makespanH, minutes: 17, seconds: 23),
      totalFlow: Duration(hours: makespanH * 6, minutes: 41),
      totalTardiness: Duration(hours: tardinessH),
      maxTardiness: Duration(hours: tardinessH),
      totalWeightedTardiness: Duration(hours: tardinessH * 3),
      maxLateness: Duration.zero,
    );

void main() {
  final rows = [
    metrics(makespanH: 30, tardinessH: 5, delayed: 3, idleMin: 40),
    metrics(makespanH: 26, tardinessH: 9, delayed: 2, idleMin: 40),
    metrics(makespanH: 26, tardinessH: 1, delayed: 4, idleMin: 40),
  ];

  group('comparisons', () {
    test('best and worst per column, ties included', () {
      final ext = columnExtremes(metricById('makespan'), rows);
      expect(ext.best, {1, 2});
      expect(ext.worst, {0});
    });

    test('a column where everyone ties is not colored', () {
      expect(columnExtremes(metricById('idle'), rows).best, isEmpty);
    });

    test('earliness is shown but never ranked', () {
      expect(metricById('avgEarliness').ranked, isFalse);
      expect(columnExtremes(metricById('avgEarliness'), rows).best, isEmpty);
    });

    test('ranks share places on ties (1, 1, 3)', () {
      expect(columnRanks(metricById('makespan'), rows), [3, 1, 1]);
    });

    test('overall score is the average rank over the chosen metrics', () {
      final avg = averageRanks(['makespan', 'totalTardiness'], rows);
      // makespan ranks 3,1,1 ; tardiness ranks 2,3,1
      expect(avg, [2.5, 2.0, 1.0]);
    });
  });

  group('widgets', () {
    final names = [
      'EDD', 'SPT', 'LPT', 'FIFO', 'WSPT', 'MINSLACK', 'CR', 'ATCS',
    ];
    final eight = [
      for (int i = 0; i < 8; i++)
        metrics(
            makespanH: 20 + i * 7,
            tardinessH: (i * 5) % 11,
            delayed: i % 4,
            idleMin: 30 + i),
    ];

    Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the table fits a 912 px window with 8 algorithms, no '
        'sideways scroll', (tester) async {
      await pumpAt(
        tester,
        912,
        MetricsTable(
          ruleNames: names,
          metrics: eight,
          onGantt: (_) {},
          onDetail: (_) {},
        ),
      );

      expect(tester.takeException(), isNull);
      final horizontal = find.byWidgetPredicate((w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal);
      expect(horizontal, findsNothing);
      expect(find.text('ATCS'), findsOneWidget);
    });

    for (final width in [1280.0, 912.0])
    testWidgets('the dashboard lays out at $width px and switches metric',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MetricsDashboard(
            ruleNames: names,
            metrics: eight,
            onGantt: (_) {},
            onDetail: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Recomendado para estos objetivos'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Ociosidad'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
