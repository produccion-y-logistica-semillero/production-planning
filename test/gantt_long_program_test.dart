// A program longer than 20 days used to be cut at day 20, and every segment
// after that was pinned onto the last displayed day, piling up on top of
// each other. The chart must cover the whole program and place each
// segment on its own date.
import 'package:dartz/dartz.dart' as dartz;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

PlanningTaskEntity task(int jobId, String name, DateTime start, DateTime end,
        {List<ProcessingSegment>? segments}) =>
    PlanningTaskEntity(
      sequenceId: 1,
      sequenceName: 'Ruta',
      displayName: name,
      taskId: jobId,
      numberProcess: 1,
      startDate: start,
      endDate: end,
      retarded: false,
      orderId: 1,
      jobId: jobId,
      machineName: 'Horno',
      segments: segments,
    );

Metrics noMetrics() => Metrics(
      idle: Duration.zero,
      totalJobs: 3,
      maxDelay: Duration.zero,
      avarageProcessingTime: Duration.zero,
      avarageDelayTime: Duration.zero,
      avarageLatenessTime: Duration.zero,
      avarageEarlinessTime: Duration.zero,
      delayedJobs: 0,
      makespan: Duration.zero,
      totalFlow: Duration.zero,
      totalTardiness: Duration.zero,
      maxTardiness: Duration.zero,
      totalWeightedTardiness: Duration.zero,
      maxLateness: Duration.zero,
    );

void main() {
  testWidgets('a 50-day program shows every day and does not pile up bars',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final start = DateTime(2026, 10, 15, 8);
    // One job early, two late in the program on different days: before the
    // fix, the two late ones were both pinned to day 20.
    final machines = [
      PlanningMachineEntity(1, 'Horno', [
        task(1, 'Job A', start, start.add(const Duration(hours: 4))),
        task(2, 'Job B', DateTime(2026, 11, 20, 8), DateTime(2026, 11, 20, 12)),
        task(3, 'Job C', DateTime(2026, 12, 3, 8), DateTime(2026, 12, 3, 12)),
      ]),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GanttChart(
            machines: machines,
            selectedRule: 1,
            items: const [DropdownMenuItem(value: 1, child: Text('EDD'))],
            metrics: noMetrics(),
            number: 1,
            schedule: const dartz.Tuple2(
                TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The whole program is covered: 15/10 .. 3/12 is 50 days.
    expect(find.text('Días: 50'), findsOneWidget);
    expect(find.text('3/12', skipOffstage: false), findsOneWidget);

    // Each late job sits on its own date, far apart, not on top of the other.
    final b = tester.getTopLeft(find.text('Job B', skipOffstage: false));
    final c = tester.getTopLeft(find.text('Job C', skipOffstage: false));
    expect(c.dx - b.dx, greaterThan(500),
        reason: 'B (20/11) and C (3/12) are 13 days apart');
  });
}
