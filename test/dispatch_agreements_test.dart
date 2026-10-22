// The agreements on how the dispatching rules read each environment:
//
//   * Flow Shop (permutation): SPT / LPT / WSPT use the time on the FIRST
//     station and the resulting order is kept at every station (FIFO
//     downstream). LWR / MWR use the nominal work of the whole route.
//   * Flexible Flow Shop: every rule is re-applied at EACH station, with the
//     job's time at that station.
//   * Job Shop / Flexible Job Shop: same, operation by operation, and the
//     conflict set is built on the EFFECTIVE start for every rule.
//   * Among the machines of a station that are available, the operation goes
//     to the one that FINISHES it first (ECT) — the dispatching rule orders
//     jobs, it does not pick machines.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

FlowShopInput flowJob(int id, Duration first, Duration second) => FlowShopInput(
      id,
      1,
      farDue,
      1,
      start,
      [const Tuple2(1, 10), const Tuple2(2, 20)],
      {1: first, 2: second},
    );

FlexibleFlowInput ffsJob(int id, List<Tuple2<int, Map<int, Duration>>> route) =>
    FlexibleFlowInput(id, farDue, 1, start, route);

FlexibleJobInput jsJob(
  int id,
  List<Tuple2<int, Map<int, Duration>>> operations, {
  DateTime? release,
  List<TaskDependencyEntity> dependencies = const [],
  Map<int, bool> interruptibleByTask = const {},
}) =>
    FlexibleJobInput(
      id,
      id,
      1,
      farDue,
      1,
      release ?? start,
      operations,
      dependencies: dependencies,
      interruptibleByTask: interruptibleByTask,
    );

Duration total(List<ProcessingSegment> segments) =>
    segments.fold(Duration.zero, (sum, s) => sum + s.duration);

void main() {
  group('Flow Shop — the rule is read on the first station', () {
    // Job 1: long on station 1, short overall.  Job 2: the opposite.
    List<FlowShopInput> jobs() => [
          flowJob(1, const Duration(hours: 3), const Duration(minutes: 10)),
          flowJob(2, const Duration(hours: 1), const Duration(hours: 5)),
        ];

    List<int> order(String rule) =>
        FlowShop(start, workingSchedule, jobs(), {10: start, 20: start}, rule)
            .output
            .map((o) => o.jobId)
            .toList();

    test('SPT puts first the job that is shortest on station 1', () {
      expect(order('SPT'), [2, 1]);
    });

    test('LPT puts first the job that is longest on station 1', () {
      expect(order('LPT'), [1, 2]);
    });

    test('LWR / MWR read the whole route instead', () {
      // Route totals: job 1 = 3h10, job 2 = 6h.
      expect(order('LWR'), [1, 2]);
      expect(order('MWR'), [2, 1]);
    });

    test('the order of station 1 is kept on station 2 (FIFO downstream)', () {
      final output =
          FlowShop(start, workingSchedule, jobs(), {10: start, 20: start}, 'SPT')
              .output;
      final first = output.firstWhere((o) => o.jobId == 2);
      final second = output.firstWhere((o) => o.jobId == 1);

      expect(
        first.machinesScheduling[20]!.value2.start
            .isBefore(second.machinesScheduling[20]!.value2.start),
        isTrue,
      );
    });

    test('SPT_ADAPTADO also compares station 1, with what it really costs',
        () {
      expect(
        FlowShop(start, workingSchedule, jobs(), {10: start, 20: start},
                'SPT_ADAPTADO')
            .output
            .map((o) => o.jobId)
            .toList(),
        [2, 1],
      );
    });
  });

  group('Flexible Flow Shop — the rule is re-applied at each station', () {
    // One machine per station, so only the per-station dispatch can make
    // station 2 disagree with station 1. Every job takes 10 min on station
    // 1; job 1 then holds station 2 for 3h, and jobs 2 and 3 queue behind.
    List<FlexibleFlowInput> jobs() => [
          ffsJob(1, [
            const Tuple2(1, {10: Duration(minutes: 10)}),
            const Tuple2(2, {20: Duration(hours: 3)}),
          ]),
          ffsJob(2, [
            const Tuple2(1, {10: Duration(minutes: 10)}),
            const Tuple2(2, {20: Duration(hours: 2)}),
          ]),
          ffsJob(3, [
            const Tuple2(1, {10: Duration(minutes: 10)}),
            const Tuple2(2, {20: Duration(minutes: 10)}),
          ]),
        ];

    DateTime startAtStation2(List<FlexibleFlowOutput> output, int jobId) =>
        output.firstWhere((o) => o.jobId == jobId).scheduling[2]!.value2.start;

    test('static SPT uses the time of THAT station', () {
      final output = FlexibleFlowShop(
              start, workingSchedule, jobs(), {10: start, 20: start}, 'SPT')
          .output;

      // Station 1: all tied at 10 min, so jobs go 1, 2, 3. Job 1 reaches
      // station 2 alone and takes it; when it frees up, job 3 (10 min
      // there) overtakes job 2 (2h there).
      expect(startAtStation2(output, 1), start.add(const Duration(minutes: 10)));
      expect(
        startAtStation2(output, 3).isBefore(startAtStation2(output, 2)),
        isTrue,
      );
    });

    test('static FIFO is first to ARRIVE at the station', () {
      final output = FlexibleFlowShop(
              start, workingSchedule, jobs(), {10: start, 20: start}, 'FIFO')
          .output;

      // Job 2 left station 1 before job 3, so it is served first.
      expect(
        startAtStation2(output, 2).isBefore(startAtStation2(output, 3)),
        isTrue,
      );
    });

    test('LWR / MWR compare the work left from this station on', () {
      // Job 1: 1h + 5h = 6h.   Job 2: 2h + 1h = 3h.
      List<FlexibleFlowInput> two() => [
            ffsJob(1, [
              const Tuple2(1, {10: Duration(hours: 1)}),
              const Tuple2(2, {20: Duration(hours: 5)}),
            ]),
            ffsJob(2, [
              const Tuple2(1, {10: Duration(hours: 2)}),
              const Tuple2(2, {20: Duration(hours: 1)}),
            ]),
          ];
      int firstOnStation1(String rule) => FlexibleFlowShop(
              start, workingSchedule, two(), {10: start, 20: start}, rule)
          .output
          .firstWhere((o) => o.scheduling[1]!.value2.start == start)
          .jobId;

      expect(firstOnStation1('LWR'), 2);
      expect(firstOnStation1('MWR'), 1);
    });
  });

  group('Machine choice — earliest completion among available machines', () {
    // One station, two NON-identical machines: 10 is fast, 11 is slow.
    const station = Tuple2(1, {
      10: Duration(hours: 1),
      11: Duration(hours: 3),
    });

    for (final rule in [
      'SPT',
      'LPT',
      'EDD',
      'FIFO',
      'WSPT',
      'LPT_ADAPTADO',
      'MS',
      'CR',
      'LWR',
      'MWR',
    ]) {
      test('Flexible Flow Shop, $rule: the job goes to the fast machine', () {
        final output = FlexibleFlowShop(start, workingSchedule,
                [ffsJob(1, [station])], {10: start, 11: start}, rule)
            .output;

        expect(output.single.scheduling[1]!.value1, 10);
      });

      // The *_ADAPTADO rules are not offered in Job Shop / Flexible Job Shop.
      if (rule.endsWith('_ADAPTADO')) continue;

      test('Flexible Job Shop, $rule: the operation goes to the fast machine',
          () {
        final output = FlexibleJobShop(start, workingSchedule,
                [jsJob(1, [station])], {10: start, 11: start}, rule)
            .output;

        expect(output.single.scheduling[1]!.value1, 10);
      });
    }

    test('a busy fast machine is not waited for (non-delay)', () {
      // Machine 10 is taken until 08:00; the slow one is free now.
      final output = FlexibleJobShop(
        start,
        workingSchedule,
        [jsJob(1, [station])],
        {10: start.add(const Duration(hours: 2)), 11: start},
        'SPT',
      ).output;

      expect(output.single.scheduling[1]!.value1, 11);
    });

    test('ties on completion go to the cheaper changeover, then lowest id',
        () {
      DispatchCandidate<int> candidate(DateTime end, Duration setup) =>
          DispatchCandidate(
            job: 1,
            start: start,
            end: end,
            span: end.difference(start),
            dueDate: farDue,
            releaseDate: start,
            priority: 1,
            jobId: 1,
            setup: setup,
          );
      final at8 = start.add(const Duration(hours: 2));

      expect(
        compareMachineChoice(candidate(at8, const Duration(minutes: 30)), 1,
            candidate(at8, const Duration(minutes: 5)), 2),
        greaterThan(0),
      );
      expect(
        compareMachineChoice(
            candidate(at8, Duration.zero), 2, candidate(at8, Duration.zero), 1),
        greaterThan(0),
      );
    });
  });

  group('Job Shop / Flexible Job Shop — static rules see the calendar', () {
    test('an operation that cannot start yet does not take the machine', () {
      // Machine 1 has maintenance 08:00–09:00. Job 1 is 5h and may not be
      // interrupted, so it cannot begin before 09:00; job 2 is 1h and fits
      // right now. LPT prefers job 1, but only among operations that can
      // really start — it used to give job 1 the machine and leave it idle
      // from 06:00 to 09:00.
      final maintenance = MachineInactivityEntity(
        machineId: 1,
        name: 'Mantenimiento',
        weekdays: Weekday.values.toSet(),
        startTime: const Duration(hours: 8),
        duration: const Duration(hours: 1),
      );

      final output = FlexibleJobShop(
        start,
        workingSchedule,
        [
          jsJob(1, [
            const Tuple2(1, {1: Duration(hours: 5)}),
          ], interruptibleByTask: const {
            1: false
          }),
          jsJob(2, [
            const Tuple2(2, {1: Duration(hours: 1)}),
          ]),
        ],
        {1: start},
        'LPT',
        machineInactivities: {
          1: [maintenance]
        },
      ).output;

      final longJob = output.firstWhere((o) => o.jobId == 1);
      final shortJob = output.firstWhere((o) => o.jobId == 2);

      expect(shortJob.scheduling[2]!.value2.start, start);
      expect(longJob.scheduling[1]!.value2.start,
          start.add(const Duration(hours: 3)));
    });

    test('a job with no state does not erase the state of the machine', () {
      // Machine 1 runs job 1 (state A), then job 2 (no state registered),
      // then job 3 (state B). The changeover into job 3 is A → B: the
      // machine is still set up as job 1 left it.
      final output = FlexibleJobShop(
        start,
        workingSchedule,
        [
          jsJob(1, [
            const Tuple2(1, {1: Duration(hours: 1)}),
          ]),
          jsJob(2, [
            const Tuple2(2, {1: Duration(hours: 1)}),
          ], release: start.add(const Duration(minutes: 30))),
          jsJob(3, [
            const Tuple2(3, {1: Duration(hours: 1)}),
          ], release: start.add(const Duration(minutes: 90))),
        ],
        {1: start},
        'FIFO',
        stateSetupMatrix: {
          1: {
            'A': {'A': 0, 'B': 60},
            'B': {'A': 60, 'B': 0},
          },
        },
        jobStates: {
          1: {1: 'A'},
          3: {1: 'B'},
        },
      ).output;

      final last = output.firstWhere((o) => o.jobId == 3);
      expect(total(last.setupSegmentsByTask[3] ?? const []),
          const Duration(hours: 1));
    });

    test('LWR / MWR count the operations really left, with a precedence graph',
        () {
      // Job 1: operations 10 (machine 2, 4h) and 11 (machine 1, 1h) have no
      // order between them; 12 (machine 3, 1h) needs both. Job 2 is a
      // single 3h operation on machine 1.
      //
      // On machine 1 at 06:00, operation 11 competes with job 2. Work
      // remaining: job 1 = 1h + 4h + 1h = 6h, job 2 = 3h.
      List<FlexibleJobInput> jobs() => [
            jsJob(1, [
              const Tuple2(10, {2: Duration(hours: 4)}),
              const Tuple2(11, {1: Duration(hours: 1)}),
              const Tuple2(12, {3: Duration(hours: 1)}),
            ], dependencies: [
              TaskDependencyEntity(
                  successor_id: 12, predecessor_id: 10, sequenceId: 1),
              TaskDependencyEntity(
                  successor_id: 12, predecessor_id: 11, sequenceId: 1),
            ]),
            jsJob(2, [
              const Tuple2(20, {1: Duration(hours: 3)}),
            ]),
          ];

      DateTime startOf(String rule, int jobId, int taskId) => FlexibleJobShop(
              start, workingSchedule, jobs(), {1: start, 2: start, 3: start}, rule)
          .output
          .firstWhere((o) => o.jobId == jobId)
          .scheduling[taskId]!
          .value2
          .start;

      // MWR: job 1 (6h left) takes machine 1 first.
      expect(startOf('MWR', 1, 11), start);
      expect(startOf('MWR', 2, 20), start.add(const Duration(hours: 1)));
      // LWR: job 2 (3h left) takes it first.
      expect(startOf('LWR', 2, 20), start);
      expect(startOf('LWR', 1, 11), start.add(const Duration(hours: 3)));
    });
  });
}
