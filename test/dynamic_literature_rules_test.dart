// MS, CR and ATCS are dynamic rules: the literature defines all three in
// terms of the clock t. Before this they were sorted once — against each
// job's release date, against the schedule start, or against DateTime.now()
// — which froze the very quantity they measure.
//
// These tests pin down three things:
//   1. each index reduces to its textbook formula when there are no setups
//      and no interruptions, and ATCS is calibrated as Lee, Bhaskaran &
//      Pinedo (1997) prescribe;
//   2. the index is evaluated at the schedule's own clock, behind the
//      release gate;
//   3. setups, interruptions and remaining work change the decision, in
//      every environment the rules are offered in.
import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/services/algorithms/parallel_machine.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

/// The literature rules under every name the environments accept.
const literatureRules = ['MS', 'MINSLACK', 'CR', 'ATCS'];

/// Machine 1 punishes switching family with a 4h changeover; machine 2 is
/// free to switch. Shared by the two route environments.
final routeSetupMatrix = {
  1: {
    'A': {'A': 0, 'B': 240},
    'B': {'A': 240, 'B': 0},
  },
  2: {
    'A': {'A': 0, 'B': 0},
    'B': {'A': 0, 'B': 0},
  },
};

/// jobId → machineId → state.
final routeJobStates = {
  1: {1: 'A', 2: 'A'},
  2: {1: 'B', 2: 'B'},
  3: {1: 'A', 2: 'A'},
};

/// A candidate priced as if nothing interrupted it: setup then processing,
/// starting right at [t].
DispatchCandidate<T> _priced<T>(
  T job,
  DateTime t, {
  required int id,
  required Duration processing,
  required DateTime due,
  Duration setup = Duration.zero,
  Duration remaining = Duration.zero,
  int priority = 1,
}) {
  final end = t.add(setup + processing);
  return DispatchCandidate(
    job: job,
    start: t,
    end: end,
    span: end.difference(t),
    dueDate: due,
    releaseDate: t,
    priority: priority,
    jobId: id,
    setup: setup,
    remainingWork: remaining,
  );
}

void main() {
  group('indices reduce to the textbook formulas', () {
    final t = DateTime(2026, 1, 5, 8, 0);
    final due = DateTime(2026, 1, 5, 12, 0);

    test('MS is d − t − p, minus the work still to do after it', () {
      final c = _priced(1, t,
          id: 1, processing: const Duration(minutes: 90), due: due);
      expect(slackMinutes(c), 240 - 90);

      final withRest = _priced(1, t,
          id: 1,
          processing: const Duration(minutes: 90),
          due: due,
          remaining: const Duration(minutes: 60));
      expect(slackMinutes(withRest), 240 - 90 - 60);
    });

    test('CR is (d − t) / p, counting the work still to do after it', () {
      final c =
          _priced(1, t, id: 1, processing: const Duration(hours: 2), due: due);
      expect(criticalRatio(c, t), 2.0);

      final withRest = _priced(1, t,
          id: 1,
          processing: const Duration(hours: 2),
          due: due,
          remaining: const Duration(hours: 2));
      expect(criticalRatio(withRest, t), 1.0);
    });

    test('ATCS is (w/p)·exp(−slack/(K1·p̄))·exp(−s/(K2·s̄))', () {
      const params = AtcsParameters(
          k1: 2, k2: 0.5, meanProcessingMinutes: 60, meanSetupMinutes: 30);
      final c = _priced(1, t,
          id: 1,
          processing: const Duration(minutes: 90),
          setup: const Duration(minutes: 15),
          due: due,
          priority: 3);

      // slack = d − p − t = 240 − 90: the setup sits in its own factor, not
      // in the look-ahead.
      final expected = log(3 / 90) - (240 - 90) / (2 * 60) - 15 / (0.5 * 30);
      expect(atcsLogIndex(c, params), closeTo(expected, 1e-9));
    });

    test('with no setups in the instance the setup factor switches off', () {
      const params = AtcsParameters(
          k1: 2, k2: 0.5, meanProcessingMinutes: 60, meanSetupMinutes: 0);
      final c = _priced(1, t,
          id: 1,
          processing: const Duration(minutes: 90),
          due: due,
          priority: 3);
      expect(atcsLogIndex(c, params), closeTo(log(3 / 90) - 150 / 120, 1e-9));
    });

    test('a late job ranks first under MS and CR — no clamping at zero', () {
      // The old static versions clamped negative slack and ratios to 0,
      // tying every late job with one exactly on the edge.
      final late = _priced(1, t,
          id: 1,
          processing: const Duration(hours: 1),
          due: t.subtract(const Duration(hours: 1)));
      final onTime = _priced(2, t,
          id: 2,
          processing: const Duration(minutes: 30),
          due: t.add(const Duration(hours: 1)));

      for (final criterion in [DispatchCriterion.ms, DispatchCriterion.cr]) {
        expect(compareCandidates(criterion, late, onTime, decisionTime: t),
            lessThan(0),
            reason: criterion.name);
      }
    });

    test('CR re-ranks as the clock advances — it is not a fixed key', () {
      final t0 = DateTime(2026, 1, 5, 6, 0);
      // A: 1h of work due in 10h. B: 4h of work due in 20h.
      final jobs = [
        (id: 1, p: const Duration(hours: 1), due: t0.add(const Duration(hours: 10))),
        (id: 2, p: const Duration(hours: 4), due: t0.add(const Duration(hours: 20))),
      ];
      int pickAt(DateTime at) => selectNext(
            pending: jobs,
            decisionTime: at,
            releaseTime: (_) => t0,
            criterion: DispatchCriterion.cr,
            evaluate: (job, when) =>
                _priced(job, when, id: job.id, processing: job.p, due: job.due),
          )!
              .jobId;

      // At t0:        CR_A = 10/1 = 10,  CR_B = 20/4 = 5  → B.
      expect(pickAt(t0), 2);
      // Eight hours on: CR_A =  2/1 = 2,  CR_B = 12/4 = 3  → A.
      expect(pickAt(t0.add(const Duration(hours: 8))), 1);
    });

    test('ATCS without parameters is a programming error, not a default', () {
      expect(
        () => selectNext<int>(
          pending: [1],
          decisionTime: t,
          releaseTime: (_) => t,
          criterion: DispatchCriterion.atcs,
          evaluate: (id, at) => _priced(id, at,
              id: id, processing: const Duration(hours: 1), due: due),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ATCS calibration (Lee, Bhaskaran & Pinedo, 1997)', () {
    final t0 = DateTime(2026, 1, 5, 6, 0);

    test('K1 = 4.5 + R and K2 = τ / (2·√η) for a narrow due-date range', () {
      // d̄ = 800 of Ĉ = 1000 → τ = 0.2;  R = 400/1000 = 0.4;  η = 25/100.
      final p = AtcsParameters.calibrate(
        start: t0,
        dueDates: [
          t0.add(const Duration(minutes: 600)),
          t0.add(const Duration(minutes: 1000)),
        ],
        meanProcessingMinutes: 100,
        meanSetupMinutes: 25,
        makespanMinutes: 1000,
      );
      expect(p.k1, closeTo(4.9, 1e-9));
      expect(p.k2, closeTo(0.2, 1e-9));
    });

    test('K1 = 6 − 2R once the due-date range passes 0.5', () {
      // R = 700/1000.
      final p = AtcsParameters.calibrate(
        start: t0,
        dueDates: [
          t0.add(const Duration(minutes: 200)),
          t0.add(const Duration(minutes: 900)),
        ],
        meanProcessingMinutes: 100,
        meanSetupMinutes: 25,
        makespanMinutes: 1000,
      );
      expect(p.k1, closeTo(4.6, 1e-9));
    });

    test('loose due dates clamp τ to 0 instead of flipping K2 negative', () {
      final p = AtcsParameters.calibrate(
        start: t0,
        dueDates: [t0.add(const Duration(days: 30))],
        meanProcessingMinutes: 100,
        meanSetupMinutes: 25,
        makespanMinutes: 1000,
      );
      expect(p.k2, AtcsParameters.minK2);
      expect(p.k1, closeTo(4.5, 1e-9));
    });
  });

  group('Single Machine', () {
    SingleMachine run(
      String rule,
      List<SingleMachineInput> jobs, {
      Map<int, Map<String, Map<String, int>>>? setupMatrix,
      List<MachineInactivityEntity> inactivities = const [],
      DateTime? from,
    }) =>
        SingleMachine(1, from ?? start, workingSchedule, List.of(jobs), rule,
            stateSetupMatrix: setupMatrix, machineInactivities: inactivities);

    List<int> sequence(SingleMachine m) =>
        m.output.map((o) => o.jobId).toList();

    test('the release gate holds: nothing is dispatched before it arrives',
        () {
      // Job 2 is the most urgent by every measure, but arrives at 14:00.
      // Sorted once — as MS and CR used to be — it went first regardless.
      final release2 = DateTime(2026, 1, 5, 14, 0);
      final jobs = [
        SingleMachineInput(1, const Duration(hours: 3), farDue, 1, start),
        SingleMachineInput(2, const Duration(minutes: 15),
            DateTime(2026, 1, 5, 10, 0), 1, release2),
      ];

      for (final rule in literatureRules) {
        final machine = run(rule, jobs);
        expect(sequence(machine), [1, 2], reason: rule);
        final second = machine.output.firstWhere((o) => o.jobId == 2);
        expect(second.startDate.isBefore(release2), isFalse, reason: rule);
      }
    });

    test("CR is evaluated at the machine's clock, not at the release date",
        () {
      // Job 1 is alone at 06:00 and holds the machine until 14:00. Then:
      //   job 2: 1h,  due 20:00 → CR = 6h / 1h   = 6
      //   job 3: 30m, due 16:00 → CR = 2h / 0.5h = 4   → job 3 first.
      // Measured from their 06:01 release instead, as CR used to be, the
      // ratios are about 14 and 20, and job 2 would have gone first.
      final release = DateTime(2026, 1, 5, 6, 1);
      final jobs = [
        SingleMachineInput(1, const Duration(hours: 8), farDue, 1, start),
        SingleMachineInput(2, const Duration(hours: 1),
            DateTime(2026, 1, 5, 20, 0), 1, release),
        SingleMachineInput(3, const Duration(minutes: 30),
            DateTime(2026, 1, 5, 16, 0), 1, release),
      ];
      expect(sequence(run('CR', jobs)), [1, 3, 2]);
    });

    test('MS reads the maintenance calendar: a window eats into slack', () {
      // From 08:00, with maintenance 09:00–12:00:
      //   job 1: 2h, due 14:00 → split by the window, ends 13:00 → slack 1h
      //   job 2: 1h, due 10:30 → fits before it,     ends 09:00 → slack 1.5h
      // Without the window job 1 would end at 10:00 with 4h of slack and
      // job 2 would go first.
      final from = DateTime(2026, 1, 5, 8, 0);
      final jobs = [
        SingleMachineInput(1, const Duration(hours: 2),
            DateTime(2026, 1, 5, 14, 0), 1, from),
        SingleMachineInput(2, const Duration(hours: 1),
            DateTime(2026, 1, 5, 10, 30), 1, from),
      ];
      final maintenance = [
        const MachineInactivityEntity(
          machineId: 1,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 9),
          duration: Duration(hours: 3),
        ),
      ];

      expect(sequence(run('MS', jobs, from: from)), [2, 1]);
      expect(
        sequence(run('MS', jobs, from: from, inactivities: maintenance)),
        [1, 2],
      );
    });

    test('ATCS prices the changeover in its own factor', () {
      // Same instance as the SPT_ADAPTADO proof in dynamic_rules_test.dart:
      // after job 1 the machine is in state A; job 2 (1h, family B) needs a
      // 4h changeover, job 3 (2h, family A) none.
      final setupMatrix = {
        1: {
          'A': {'A': 0, 'B': 240},
          'B': {'A': 240, 'B': 0},
        },
      };
      final jobs = [
        SingleMachineInput(1, const Duration(minutes: 30), farDue, 1, start,
            jobState: 'A'),
        SingleMachineInput(2, const Duration(hours: 1), farDue, 1, start,
            jobState: 'B'),
        SingleMachineInput(3, const Duration(hours: 2), farDue, 1, start,
            jobState: 'A'),
      ];

      expect(sequence(run('ATCS', jobs, setupMatrix: setupMatrix)), [1, 3, 2]);
      // Without setups the index is plain ATC and the shorter job wins.
      expect(sequence(run('ATCS', jobs)), [1, 2, 3]);
    });

    test('every rule is deterministic and schedules each job once', () {
      final jobs = [
        SingleMachineInput(
            1, const Duration(hours: 2), DateTime(2026, 1, 7), 1, start),
        SingleMachineInput(
            2, const Duration(hours: 1), DateTime(2026, 1, 6), 3, start),
        SingleMachineInput(3, const Duration(hours: 3),
            DateTime(2026, 1, 5, 18, 0), 2, start),
      ];
      for (final rule in literatureRules) {
        final first = run(rule, jobs);
        final second = run(rule, jobs);
        expect(sequence(first), sequence(second), reason: rule);
        expect(sequence(first).toSet(), {1, 2, 3}, reason: rule);
        expect(first.output.last.endDate, second.output.last.endDate,
            reason: rule);
      }
    });
  });

  group('Parallel Machine', () {
    ParallelMachine run(
      String rule,
      List<ParallelInput> jobs, {
      Map<int, Map<String, Map<String, int>>>? setupMatrix,
    }) =>
        ParallelMachine(start, workingSchedule, List.of(jobs),
            {1: <Tuple2<DateTime, DateTime>>[]}, rule,
            stateSetupMatrix: setupMatrix);

    List<int> sequence(ParallelMachine m) =>
        m.output.map((o) => o.jobId).toList();

    test('the release gate holds', () {
      final release2 = DateTime(2026, 1, 5, 14, 0);
      final jobs = [
        ParallelInput(1, farDue, 1, start, {1: const Duration(hours: 3)}),
        ParallelInput(2, DateTime(2026, 1, 5, 10, 0), 1, release2,
            {1: const Duration(minutes: 15)}),
      ];
      for (final rule in literatureRules) {
        final machine = run(rule, jobs);
        expect(sequence(machine), [1, 2], reason: rule);
        expect(
          machine.output
              .firstWhere((o) => o.jobId == 2)
              .startDate
              .isBefore(release2),
          isFalse,
          reason: rule,
        );
      }
    });

    test('ATCS prices the changeover in its own factor', () {
      final setupMatrix = {
        1: {
          'A': {'A': 0, 'B': 240},
          'B': {'A': 240, 'B': 0},
        },
      };
      final jobs = [
        ParallelInput(1, farDue, 1, start, {1: const Duration(minutes: 30)},
            jobState: 'A'),
        ParallelInput(2, farDue, 1, start, {1: const Duration(hours: 1)},
            jobState: 'B'),
        ParallelInput(3, farDue, 1, start, {1: const Duration(hours: 2)},
            jobState: 'A'),
      ];

      expect(sequence(run('ATCS', jobs, setupMatrix: setupMatrix)), [1, 3, 2]);
      expect(sequence(run('ATCS', jobs)), [1, 2, 3]);
    });

    test('every rule is deterministic and schedules each job once', () {
      final jobs = [
        ParallelInput(
            1, DateTime(2026, 1, 7), 1, start, {1: const Duration(hours: 2)}),
        ParallelInput(
            2, DateTime(2026, 1, 6), 3, start, {1: const Duration(hours: 1)}),
        ParallelInput(3, DateTime(2026, 1, 5, 18, 0), 2, start,
            {1: const Duration(hours: 3)}),
      ];
      for (final rule in literatureRules) {
        final first = run(rule, jobs);
        final second = run(rule, jobs);
        expect(sequence(first), sequence(second), reason: rule);
        expect(sequence(first).toSet(), {1, 2, 3}, reason: rule);
      }
    });
  });

  group('Flow Shop', () {
    List<FlowShopInput> changeoverJobs() => [
          FlowShopInput(1, 1, farDue, 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(minutes: 30), 2: const Duration(minutes: 30)}),
          FlowShopInput(2, 2, farDue, 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(hours: 1), 2: const Duration(minutes: 30)}),
          FlowShopInput(3, 1, farDue, 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(hours: 2), 2: const Duration(minutes: 30)}),
        ];

    FlowShop run(String rule, List<FlowShopInput> jobs,
            {bool withSetups = false}) =>
        FlowShop(start, workingSchedule, jobs, {1: start, 2: start}, rule,
            stateSetupMatrix: withSetups ? routeSetupMatrix : null,
            jobStates: withSetups ? routeJobStates : null);

    List<int> sequence(FlowShop shop) =>
        shop.output.map((o) => o.jobId).toList();

    test('ATCS prices the changeover along the route', () {
      expect(
          sequence(run('ATCS', changeoverJobs(), withSetups: true)), [1, 3, 2]);
      expect(sequence(run('ATCS', changeoverJobs())), [1, 2, 3]);
    });

    test('the release gate holds, deterministically, once per job', () {
      final release2 = DateTime(2026, 1, 5, 14, 0);
      List<FlowShopInput> jobs() => [
            FlowShopInput(1, 1, farDue, 1, start,
                [const Tuple2(1, 1), const Tuple2(2, 2)],
                {1: const Duration(hours: 3), 2: const Duration(minutes: 30)}),
            FlowShopInput(2, 1, DateTime(2026, 1, 5, 10, 0), 1, release2,
                [const Tuple2(1, 1), const Tuple2(2, 2)], {
              1: const Duration(minutes: 15),
              2: const Duration(minutes: 15),
            }),
          ];
      for (final rule in literatureRules) {
        final first = run(rule, jobs());
        expect(sequence(first), [1, 2], reason: rule);
        expect(
          first.output
              .firstWhere((o) => o.jobId == 2)
              .startDate
              .isBefore(release2),
          isFalse,
          reason: rule,
        );
        expect(sequence(run(rule, jobs())), sequence(first), reason: rule);
      }
    });
  });

  group('Flexible Flow Shop', () {
    // Two stations of one machine each: station 1 is machine 1, station 2
    // is machine 2 — the same shop as the Flow Shop group.
    FlexibleFlowInput job(int id, Duration onM1, Duration onM2,
            {DateTime? due, DateTime? release}) =>
        FlexibleFlowInput(id, due ?? farDue, 1, release ?? start, [
          Tuple2(1, {1: onM1}),
          Tuple2(2, {2: onM2}),
        ]);

    FlexibleFlowShop run(String rule, List<FlexibleFlowInput> jobs,
            {bool withSetups = false}) =>
        FlexibleFlowShop(
            start, workingSchedule, jobs, {1: start, 2: start}, rule,
            stateSetupMatrix: withSetups ? routeSetupMatrix : null,
            jobStates: withSetups ? routeJobStates : null);

    List<int> sequence(FlexibleFlowShop shop) =>
        shop.output.map((o) => o.jobId).toList();

    List<FlexibleFlowInput> changeoverJobs() => [
          job(1, const Duration(minutes: 30), const Duration(minutes: 30)),
          job(2, const Duration(hours: 1), const Duration(minutes: 30)),
          job(3, const Duration(hours: 2), const Duration(minutes: 30)),
        ];

    test('ATCS prices the changeover along the route', () {
      expect(
          sequence(run('ATCS', changeoverJobs(), withSetups: true)), [1, 3, 2]);
      expect(sequence(run('ATCS', changeoverJobs())), [1, 2, 3]);
    });

    test('the release gate holds, deterministically, once per job', () {
      final release2 = DateTime(2026, 1, 5, 14, 0);
      List<FlexibleFlowInput> jobs() => [
            job(1, const Duration(hours: 3), const Duration(minutes: 30)),
            job(2, const Duration(minutes: 15), const Duration(minutes: 15),
                due: DateTime(2026, 1, 5, 10, 0), release: release2),
          ];
      for (final rule in literatureRules) {
        final first = run(rule, jobs());
        expect(sequence(first), [1, 2], reason: rule);
        expect(
          first.output
              .firstWhere((o) => o.jobId == 2)
              .startDate
              .isBefore(release2),
          isFalse,
          reason: rule,
        );
        expect(sequence(run(rule, jobs())), sequence(first), reason: rule);
      }
    });
  });

  group('Open Shop', () {
    OpenShop run(String rule, List<OpenShopInput> jobs) =>
        OpenShop(start, workingSchedule, jobs, {1: start, 2: start}, rule);

    DateTime startOf(OpenShop shop, int jobId, int taskId) => shop.output
        .firstWhere((o) => o.jobId == jobId)
        .scheduling[taskId]!
        .value2
        .startDate;

    test('the tighter job goes first, measured on the schedule clock', () {
      // These rules used to read DateTime.now(). Against a plan dated in the
      // past every job looked overdue, slack and ratios clamped to 0, and
      // the choice fell to list order: job 1 first, every time.
      List<OpenShopInput> jobs() => [
            OpenShopInput(1, 1, 1, farDue, 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
            ]),
            OpenShopInput(2, 2, 1, DateTime(2026, 1, 5, 8, 0), 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
            ]),
          ];
      for (final rule in literatureRules) {
        final shop = run(rule, jobs());
        expect(startOf(shop, 2, 1), start, reason: rule);
        expect(startOf(shop, 1, 1), start.add(const Duration(hours: 1)),
            reason: rule);
        expect(startOf(run(rule, jobs()), 2, 1), startOf(shop, 2, 1),
            reason: rule);
      }
    });

    test("a job's pending operations count against its due date", () {
      // On machine 1 at 06:00, both jobs have a 1h operation ready:
      //   job 1: due 13:00, with 5h more on machine 2 after this one
      //          → slack = 13:00 − 07:00 − 5h = 1h
      //   job 2: due 09:00, nothing after → slack = 09:00 − 07:00 = 2h
      // Judged on the ready operation alone, job 1 would seem to have 6h.
      List<OpenShopInput> jobs() => [
            OpenShopInput(1, 1, 1, DateTime(2026, 1, 5, 13, 0), 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
              const Tuple2(2, {2: Duration(hours: 5)}),
            ]),
            OpenShopInput(2, 2, 1, DateTime(2026, 1, 5, 9, 0), 1, start, [
              const Tuple2(3, {1: Duration(hours: 1)}),
            ]),
          ];
      for (final rule in ['MS', 'CR', 'ATCS']) {
        expect(startOf(run(rule, jobs()), 1, 1), start, reason: rule);
      }
    });
  });

  group('Flexible Job Shop', () {
    FlexibleJobShop run(String rule, List<FlexibleJobInput> jobs) =>
        FlexibleJobShop(
            start, workingSchedule, jobs, {1: start, 2: start}, rule);

    DateTime startOf(FlexibleJobShop shop, int jobId, int taskId) => shop
        .output
        .firstWhere((o) => o.jobId == jobId)
        .scheduling[taskId]!
        .value2
        .startDate;

    test('the tighter job goes first, measured on the schedule clock', () {
      List<FlexibleJobInput> jobs() => [
            FlexibleJobInput(1, 1, 1, farDue, 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
            ]),
            FlexibleJobInput(2, 2, 1, DateTime(2026, 1, 5, 8, 0), 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
            ]),
          ];
      for (final rule in literatureRules) {
        final shop = run(rule, jobs());
        expect(startOf(shop, 2, 1), start, reason: rule);
        expect(startOf(shop, 1, 1), start.add(const Duration(hours: 1)),
            reason: rule);
        expect(startOf(run(rule, jobs()), 2, 1), startOf(shop, 2, 1),
            reason: rule);
      }
    });

    test("a job's pending operations count against its due date", () {
      List<FlexibleJobInput> jobs() => [
            FlexibleJobInput(1, 1, 1, DateTime(2026, 1, 5, 13, 0), 1, start, [
              const Tuple2(1, {1: Duration(hours: 1)}),
              const Tuple2(2, {2: Duration(hours: 5)}),
            ]),
            FlexibleJobInput(2, 2, 1, DateTime(2026, 1, 5, 9, 0), 1, start, [
              const Tuple2(3, {1: Duration(hours: 1)}),
            ]),
          ];
      for (final rule in ['MS', 'CR', 'ATCS']) {
        expect(startOf(run(rule, jobs()), 1, 1), start, reason: rule);
      }
    });
  });
}
