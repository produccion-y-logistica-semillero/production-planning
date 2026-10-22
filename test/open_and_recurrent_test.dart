// Open Shop / Flexible Open Shop and Recurrente / Flexible Recurrente.
//
//   * A job with no precedences is a true open-shop job: its operations go in
//     any order, but never two at once.
//   * In an order that mixes free jobs with routed ones, the routed jobs keep
//     their route.
//   * A recurrent job (A and B enable C) runs A and B in parallel and C only
//     after both.
//   * Every operation goes to the machine that finishes it first, and LWR /
//     MWR rank by the work actually left.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/shared/types/rnage.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

OpenShopInput openJob(
  int id,
  List<Tuple2<int, Map<int, Duration>>> operations, {
  List<TaskDependencyEntity> dependencies = const [],
}) =>
    OpenShopInput(id, id, 1, farDue, 1, start, operations,
        dependencies: dependencies);

TaskDependencyEntity arrow(int from, int to) =>
    TaskDependencyEntity(predecessor_id: from, successor_id: to, sequenceId: 1);

bool overlap(Range a, Range b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

void main() {
  group('Open Shop — free order, one machine at a time', () {
    test('operations are not forced into list order', () {
      // Listed: station 1 first, then station 2. Machine 1 is busy until
      // 10:00, machine 2 is free: an open shop starts on station 2.
      final output = OpenShop(
        start,
        workingSchedule,
        [
          openJob(1, [
            const Tuple2(1, {1: Duration(hours: 1)}),
            const Tuple2(2, {2: Duration(hours: 1)}),
          ]),
        ],
        {1: start.add(const Duration(hours: 4)), 2: start},
        'SPT',
      ).output;

      expect(output.single.scheduling[2]!.value2.start, start);
    });

    for (final rule in ['SPT', 'LPT', 'EDD', 'FIFO', 'WSPT', 'MS', 'CR',
        'ATCS', 'LWR', 'MWR']) {
      test('$rule: a job never runs two operations at once', () {
        final output = OpenShop(
          start,
          workingSchedule,
          [
            openJob(1, [
              const Tuple2(1, {1: Duration(hours: 2)}),
              const Tuple2(2, {2: Duration(hours: 1)}),
              const Tuple2(3, {3: Duration(hours: 3)}),
            ]),
            openJob(2, [
              const Tuple2(4, {1: Duration(hours: 1)}),
              const Tuple2(5, {2: Duration(hours: 2)}),
              const Tuple2(6, {3: Duration(hours: 1)}),
            ]),
          ],
          {1: start, 2: start, 3: start},
          rule,
        ).output;

        expect(output, hasLength(2));
        for (final job in output) {
          final ranges = job.scheduling.values.map((e) => e.value2).toList();
          expect(ranges, hasLength(3));
          for (int i = 0; i < ranges.length; i++) {
            for (int j = i + 1; j < ranges.length; j++) {
              expect(overlap(ranges[i], ranges[j]), isFalse,
                  reason: 'job ${job.jobId} overlaps itself under $rule');
            }
          }
        }
      });
    }

    test('in a mixed order, the routed job keeps its route', () {
      // Job 1 is free; job 2 must do task 11 (station 2) before task 10
      // (station 1), even though task 10 is listed first.
      final output = OpenShop(
        start,
        workingSchedule,
        [
          openJob(1, [
            const Tuple2(1, {1: Duration(hours: 1)}),
            const Tuple2(2, {2: Duration(hours: 1)}),
          ]),
          openJob(2, [
            const Tuple2(10, {1: Duration(hours: 1)}),
            const Tuple2(11, {2: Duration(hours: 1)}),
          ], dependencies: [arrow(11, 10)]),
        ],
        {1: start, 2: start},
        'SPT',
      ).output;

      final routed = output.firstWhere((o) => o.jobId == 2).scheduling;
      expect(routed[10]!.value2.start.isBefore(routed[11]!.value2.end),
          isFalse);
    });

    test('the operation goes to the machine that finishes it first', () {
      for (final rule in ['LPT', 'EDD', 'FIFO', 'MS']) {
        final output = OpenShop(
          start,
          workingSchedule,
          [
            openJob(1, [
              const Tuple2(1, {10: Duration(hours: 1), 11: Duration(hours: 3)}),
            ]),
          ],
          {10: start, 11: start},
          rule,
        ).output;
        expect(output.single.scheduling[1]!.value1, 10, reason: rule);
      }
    });

    test('LWR / MWR rank by the work left', () {
      // On machine 1 at 06:00: job 1 has 1h there + 4h elsewhere = 5h,
      // job 2 has 2h in total.
      List<OpenShopInput> jobs() => [
            openJob(1, [
              const Tuple2(1, {1: Duration(hours: 1)}),
              const Tuple2(2, {2: Duration(hours: 4)}),
            ]),
            openJob(2, [
              const Tuple2(3, {1: Duration(hours: 2)}),
            ]),
          ];
      // Machine 2 starts busy so that job 1 can only begin on machine 1.
      Map<int, DateTime> availability() =>
          {1: start, 2: start.add(const Duration(hours: 8))};

      DateTime startOf(String rule, int jobId, int taskId) =>
          OpenShop(start, workingSchedule, jobs(), availability(), rule)
              .output
              .firstWhere((o) => o.jobId == jobId)
              .scheduling[taskId]!
              .value2
              .start;

      expect(startOf('MWR', 1, 1), start);
      expect(startOf('LWR', 2, 3), start);
    });

    test('WSPT survives a zero-minute operation', () {
      expect(
        () => OpenShop(
          start,
          workingSchedule,
          [
            openJob(1, [const Tuple2(1, {1: Duration.zero})]),
            openJob(2, [const Tuple2(2, {1: Duration(hours: 1)})]),
          ],
          {1: start},
          'WSPT',
        ),
        returnsNormally,
      );
    });
  });

  group('Recurrente — A and B enable C', () {
    FlexibleJobInput assembly(int id, Map<int, Duration> stationC) =>
        FlexibleJobInput(
          id,
          id,
          1,
          farDue,
          1,
          start,
          [
            const Tuple2(1, {1: Duration(hours: 2)}),
            const Tuple2(2, {2: Duration(hours: 3)}),
            Tuple2(3, stationC),
          ],
          dependencies: [arrow(1, 3), arrow(2, 3)],
        );

    for (final rule in ['SPT', 'FIFO', 'EDD', 'MS', 'LWR', 'MWR']) {
      test('$rule: A and B run in parallel, C waits for both', () {
        final s = FlexibleJobShop(
          start,
          workingSchedule,
          [assembly(1, {3: const Duration(hours: 1)})],
          {1: start, 2: start, 3: start},
          rule,
        ).output.single.scheduling;

        expect(s[1]!.value2.start, start);
        expect(s[2]!.value2.start, start);
        expect(s[3]!.value2.start, start.add(const Duration(hours: 3)));
      });
    }

    test('Flexible Recurrente: C goes to the machine that finishes it first',
        () {
      final s = FlexibleJobShop(
        start,
        workingSchedule,
        [
          assembly(1, {
            30: const Duration(hours: 2),
            31: const Duration(hours: 1),
          })
        ],
        {1: start, 2: start, 30: start, 31: start},
        'LPT',
      ).output.single.scheduling;

      expect(s[3]!.value1, 31);
    });
  });
}
