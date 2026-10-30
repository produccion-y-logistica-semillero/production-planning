// GENETICS is a real genetic algorithm in every shop environment (operation
// permutation + machine assignment in Job Shop / Open Shop / Recurrente and
// their flexible variants, job permutation in Flexible Flow Shop), and the
// old composite score lives on as PRIORIDAD_COMPUESTA.
//
//   * Every schedule it returns is valid: each operation exactly once, no
//     two operations at once on a machine, a job at one station at a time,
//     arrows respected.
//   * It is reproducible: the random generator is seeded.
//   * On instances with a known optimum it reaches it.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/shared/types/rnage.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

TaskDependencyEntity arrow(int from, int to) =>
    TaskDependencyEntity(predecessor_id: from, successor_id: to, sequenceId: 1);

bool overlap(Range a, Range b) =>
    a.start.isBefore(b.end) && b.start.isBefore(a.end);

/// jobId → taskId → (machineId, range), checked for validity.
void expectValid(
  Map<int, Map<int, Tuple2<int, Range>>> byJob, {
  required int operations,
  Map<int, List<TaskDependencyEntity>> arrows = const {},
}) {
  final all = <({int job, int machine, Range range})>[];
  byJob.forEach((job, tasks) {
    tasks.forEach((_, t) => all.add((job: job, machine: t.value1, range: t.value2)));
  });
  expect(all.length, operations, reason: 'every operation exactly once');
  for (int i = 0; i < all.length; i++) {
    for (int j = i + 1; j < all.length; j++) {
      if (all[i].machine == all[j].machine) {
        expect(overlap(all[i].range, all[j].range), isFalse,
            reason: 'two operations at once on machine ${all[i].machine}');
      }
      if (all[i].job == all[j].job) {
        expect(overlap(all[i].range, all[j].range), isFalse,
            reason: 'job ${all[i].job} at two stations at once');
      }
    }
  }
  arrows.forEach((job, deps) {
    for (final d in deps) {
      expect(
        byJob[job]![d.successor_id]!.value2.start
            .isBefore(byJob[job]![d.predecessor_id]!.value2.end),
        isFalse,
        reason: 'arrow ${d.predecessor_id}→${d.successor_id} of job $job',
      );
    }
  });
}

DateTime latest(Iterable<DateTime> ends) =>
    ends.reduce((a, b) => a.isAfter(b) ? a : b);

void main() {
  group('Job Shop / Flexible Job Shop / Recurrente', () {
    FlexibleJobInput jsJob(
      int id,
      List<Tuple2<int, Map<int, Duration>>> tasks, {
      List<TaskDependencyEntity> dependencies = const [],
    }) =>
        FlexibleJobInput(id, id, id, farDue, 1, start, tasks,
            dependencies: dependencies);

    Map<int, Map<int, Tuple2<int, Range>>> run(
      List<FlexibleJobInput> jobs,
      Map<int, DateTime> machines,
      String rule,
    ) =>
        {
          for (final o
              in FlexibleJobShop(start, workingSchedule, jobs, machines, rule)
                  .output)
            o.jobId: o.scheduling
        };

    test('reaches the 5 h optimum of the classic 2×2 job shop', () {
      // J1: M1 3h → M2 2h ; J2: M2 3h → M1 2h. Optimum: both start at once.
      List<FlexibleJobInput> jobs() => [
            jsJob(1, [
              const Tuple2(1, {1: Duration(hours: 3)}),
              const Tuple2(2, {2: Duration(hours: 2)}),
            ]),
            jsJob(2, [
              const Tuple2(3, {2: Duration(hours: 3)}),
              const Tuple2(4, {1: Duration(hours: 2)}),
            ]),
          ];
      final s = run(jobs(), {1: start, 2: start}, 'GENETICS');
      expectValid(s, operations: 4);
      final end = latest(s.values.expand((t) => t.values).map((t) => t.value2.end));
      expect(end, start.add(const Duration(hours: 5)));
    });

    test('flexible: valid, uses the machine genes, and is reproducible', () {
      List<FlexibleJobInput> jobs() => [
            for (int j = 1; j <= 4; j++)
              jsJob(j, [
                Tuple2(j * 10 + 1, {
                  1: Duration(minutes: 40 + 10 * j),
                  2: Duration(minutes: 70 - 5 * j),
                }),
                Tuple2(j * 10 + 2, {
                  3: Duration(minutes: 30 + 5 * j),
                  4: const Duration(minutes: 45),
                }),
              ]),
          ];
      final machines = {1: start, 2: start, 3: start, 4: start};
      final a = run(jobs(), machines, 'GENETICS');
      final b = run(jobs(), machines, 'GENETICS');
      expectValid(a, operations: 8);
      expect(a.toString(), b.toString(), reason: 'seeded: same schedule');
    });

    test('recurrent graph: arrows respected and branches never overlap', () {
      final deps = [arrow(1, 3), arrow(2, 3)];
      List<FlexibleJobInput> jobs() => [
            jsJob(1, [
              const Tuple2(1, {1: Duration(hours: 2)}),
              const Tuple2(2, {2: Duration(hours: 1)}),
              const Tuple2(3, {3: Duration(hours: 1)}),
            ], dependencies: deps),
            jsJob(2, [
              const Tuple2(1, {2: Duration(hours: 2)}),
              const Tuple2(2, {1: Duration(hours: 1)}),
              const Tuple2(3, {3: Duration(hours: 1)}),
            ], dependencies: deps),
          ];
      final s = run(jobs(), {1: start, 2: start, 3: start}, 'GENETICS');
      expectValid(s, operations: 6, arrows: {1: deps, 2: deps});
    });

    test('PRIORIDAD_COMPUESTA is still available and valid', () {
      final s = run([
        jsJob(1, [const Tuple2(1, {1: Duration(hours: 1)})]),
        jsJob(2, [const Tuple2(2, {1: Duration(hours: 2)})]),
      ], {1: start}, 'PRIORIDAD_COMPUESTA');
      expectValid(s, operations: 2);
    });
  });

  group('Open Shop', () {
    OpenShopInput osJob(int id, List<Tuple2<int, Map<int, Duration>>> ops) =>
        OpenShopInput(id, id, 1, farDue, 1, start, ops);

    test('valid and reproducible', () {
      List<OpenShopInput> jobs() => [
            for (int j = 1; j <= 3; j++)
              osJob(j, [
                Tuple2(j * 10 + 1, {1: Duration(minutes: 30 * j)}),
                Tuple2(j * 10 + 2, {2: Duration(minutes: 90 - 20 * j)}),
              ]),
          ];
      Map<int, Map<int, Tuple2<int, Range>>> run() => {
            for (final o in OpenShop(start, workingSchedule, jobs(),
                    {1: start, 2: start}, 'GENETICS')
                .output)
              o.jobId: o.scheduling
          };
      final a = run();
      expectValid(a, operations: 6);
      expect(a.toString(), run().toString());
    });
  });

  group('Flexible Flow Shop', () {
    FlexibleFlowInput ffsJob(int id, int p1, int p2) => FlexibleFlowInput(
          id,
          farDue,
          1,
          start,
          [
            Tuple2(1, {10: Duration(minutes: p1)}),
            Tuple2(2, {20: Duration(minutes: p2), 21: Duration(minutes: p2 + 10)}),
          ],
        );

    test('every job goes through both stations, reproducibly', () {
      List<FlexibleFlowInput> jobs() =>
          [ffsJob(1, 30, 50), ffsJob(2, 20, 60), ffsJob(3, 40, 20), ffsJob(4, 10, 30)];
      FlexibleFlowShop run() => FlexibleFlowShop(
          start, workingSchedule, jobs(), {10: start, 20: start, 21: start},
          'GENETICS');
      final a = run();
      expect(a.output.length, 4);
      for (final o in a.output) {
        expect(o.scheduling.keys.toSet(), {1, 2});
        expect(o.scheduling[2]!.value2.start.isBefore(o.scheduling[1]!.value2.end),
            isFalse);
      }
      String key(FlexibleFlowShop s) =>
          (s.output.map((o) => '${o.jobId}:${o.scheduling}').toList()..sort())
              .join(';');
      expect(key(a), key(run()));
    });
  });

  group('Flow Shop', () {
    test('keeps the best sequence: reaches Johnson\'s 18-minute optimum', () {
      // Two machines, (a, b) in minutes: J1 (3, 6), J2 (5, 2), J3 (1, 2),
      // J4 (6, 6). Johnson: J3, J1, J4, J2 → 18 min. Sorting the GA's
      // sequence back by job id gave J1..J4 → 21 min.
      // Task 1 runs on machine 1 and task 2 on machine 2.
      FlowShopInput fsJob(int id, int a, int b) => FlowShopInput(
            id,
            1,
            farDue,
            1,
            start,
            const [Tuple2(1, 1), Tuple2(2, 2)],
            {1: Duration(minutes: a), 2: Duration(minutes: b)},
          );
      final shop = FlowShop(
        start,
        workingSchedule,
        [fsJob(1, 3, 6), fsJob(2, 5, 2), fsJob(3, 1, 2), fsJob(4, 6, 6)],
        {1: start, 2: start},
        'GENETICS',
      );
      final end = latest(shop.output.map((o) => o.endTime));
      expect(end, start.add(const Duration(minutes: 18)));
    });
  });
}
