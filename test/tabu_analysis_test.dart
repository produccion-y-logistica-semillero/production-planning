import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';
import 'package:production_planning/presentation/2_orders/widgets/metrics/tabu_analysis.dart';

Metrics _metrics(int flowMinutes, {TabuRunStats? stats}) => Metrics(
      idle: Duration.zero,
      totalJobs: 4,
      maxDelay: Duration.zero,
      avarageProcessingTime: const Duration(minutes: 30),
      avarageDelayTime: Duration.zero,
      avarageLatenessTime: Duration.zero,
      avarageEarlinessTime: Duration.zero,
      delayedJobs: 0,
      makespan: const Duration(hours: 5),
      totalFlow: Duration(minutes: flowMinutes),
      totalTardiness: Duration.zero,
      maxTardiness: Duration.zero,
      totalWeightedTardiness: Duration.zero,
      maxLateness: Duration.zero,
      tabuStats: stats,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  const stats = TabuRunStats(
    iterations: 100,
    maxIterations: 100,
    elapsedMs: 1200,
    timeBudgetMs: 4000,
    initialFlowMinutes: 800,
    bestFlowMinutes: 760,
    stoppedByTime: false,
  );

  testWidgets('shows run stats, parameters and the comparison with TABU first',
      (tester) async {
    await _pump(
      tester,
      TabuAnalysis(
        ruleNames: const ['SPT', 'TABU', 'EDD'],
        metrics: [_metrics(800), _metrics(760, stats: stats), _metrics(900)],
        params: const TabuParams(timeBudgetMs: 6000),
      ),
    );

    expect(find.text('Análisis de la búsqueda tabú'), findsOneWidget);
    expect(find.text('Busqueda tabu'), findsOneWidget); // TabuStatsCard
    expect(find.text('Parámetros usados'), findsOneWidget);
    expect(find.text('6,0 s'), findsOneWidget);
    expect(find.textContaining('TABU ocupa el puesto 1 de 3'), findsOneWidget);
    expect(find.textContaining('mejora en 40 min'), findsOneWidget);
    expect(find.text('+5,3 %'), findsOneWidget); // SPT: 800 vs 760
  });

  testWidgets('explains when the run has no stats (Single Machine TABU)',
      (tester) async {
    await _pump(
      tester,
      TabuAnalysis(
        ruleNames: const ['TABU', 'SPT'],
        metrics: [_metrics(500), _metrics(500)],
      ),
    );

    expect(find.textContaining('no registró estadísticas'), findsOneWidget);
    expect(find.textContaining('empata con la mejor otra regla'), findsOneWidget);
    expect(find.text('Busqueda tabu'), findsNothing);
  });

  testWidgets('renders nothing when TABU is not among the rules', (tester) async {
    await _pump(
      tester,
      TabuAnalysis(ruleNames: const ['SPT'], metrics: [_metrics(500)]),
    );
    expect(find.text('Análisis de la búsqueda tabú'), findsNothing);
  });
}
