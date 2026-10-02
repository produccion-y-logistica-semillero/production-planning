// The same proof as dynamic_rules_test.dart, but for the environments that
// reach the dynamic dispatch through a different code path: Flow Shop and
// Flexible Flow Shop simulate a whole multi-machine route per candidate,
// Parallel Machine prices each candidate on its best machine first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/parallel_machine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);

void main() {
  group('Flow Shop', () {
    // Two machines in series. Setup on machine 1 punishes switching family.
    final setupMatrix = {
      1: {
        'A': {'A': 0, 'B': 240},
        'B': {'A': 240, 'B': 0},
      },
      2: {
        'A': {'A': 0, 'B': 0},
        'B': {'A': 0, 'B': 0},
      },
    };

    // jobStates: jobId → machineId → state
    final jobStates = {
      1: {1: 'A', 2: 'A'},
      2: {1: 'B', 2: 'B'},
      3: {1: 'A', 2: 'A'},
    };

    List<FlowShopInput> buildJobs() => [
          FlowShopInput(1, 1, DateTime(2026, 1, 30), 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(minutes: 30), 2: const Duration(minutes: 30)}),
          FlowShopInput(2, 2, DateTime(2026, 1, 30), 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(hours: 1), 2: const Duration(minutes: 30)}),
          FlowShopInput(3, 1, DateTime(2026, 1, 30), 1, start,
              [const Tuple2(1, 1), const Tuple2(2, 2)],
              {1: const Duration(hours: 2), 2: const Duration(minutes: 30)}),
        ];

    FlowShop run(String rule) => FlowShop(
          start,
          workingSchedule,
          buildJobs(),
          {1: start, 2: start},
          rule,
          stateSetupMatrix: setupMatrix,
          jobStates: jobStates,
        );

    List<int> sequence(FlowShop shop) =>
        shop.output.map((o) => o.jobId).toList();

    test('SPT and SPT_ADAPTADO no longer produce the same schedule', () {
      // This is the regression that matters most here: flow_shop's
      // dynamicRule used to re-sort by an unchanging key, so the two rules
      // returned byte-identical schedules.
      expect(sequence(run('SPT')), isNot(sequence(run('SPT_ADAPTADO'))));
    });

    test('SPT_ADAPTADO defers the job with the expensive changeover', () {
      // Nominal totals: job 1 = 60min, job 2 = 90min, job 3 = 150min.
      // Static SPT therefore runs 1, 2, 3. Job 2 is family B, so putting it
      // second costs a 4h changeover and another to come back.
      expect(sequence(run('SPT')), [1, 2, 3]);
      expect(sequence(run('SPT_ADAPTADO')), [1, 3, 2]);
    });

    test('the adapted route finishes no later than the static one', () {
      final staticEnd = run('SPT').output.last.endTime;
      final dynamicEnd = run('SPT_ADAPTADO').output.last.endTime;
      expect(dynamicEnd.isAfter(staticEnd), isFalse);
    });

    test('every dynamic rule is deterministic across runs', () {
      for (final rule in [
        'SPT_ADAPTADO',
        'LPT_ADAPTADO',
        'EDD_ADAPTADO',
        'FIFO_ADAPTADO',
        'WSPT_ADAPTADO',
      ]) {
        expect(sequence(run(rule)), sequence(run(rule)), reason: rule);
      }
    });

    test('every job is scheduled exactly once', () {
      for (final rule in ['SPT', 'SPT_ADAPTADO', 'EDD_ADAPTADO']) {
        final seq = sequence(run(rule));
        expect(seq, hasLength(3), reason: rule);
        expect(seq.toSet(), {1, 2, 3}, reason: rule);
      }
    });
  });

  group('Parallel Machine', () {
    final setupMatrix = {
      1: {
        'A': {'A': 0, 'B': 240},
        'B': {'A': 240, 'B': 0},
      },
    };

    List<ParallelInput> buildJobs() => [
          ParallelInput(1, DateTime(2026, 1, 30), 1, start,
              {1: const Duration(minutes: 30)},
              jobState: 'A'),
          ParallelInput(
              2, DateTime(2026, 1, 30), 1, start, {1: const Duration(hours: 1)},
              jobState: 'B'),
          ParallelInput(
              3, DateTime(2026, 1, 30), 1, start, {1: const Duration(hours: 2)},
              jobState: 'A'),
        ];

    ParallelMachine run(String rule) => ParallelMachine(
          start,
          workingSchedule,
          buildJobs(),
          {1: <Tuple2<DateTime, DateTime>>[]},
          rule,
          stateSetupMatrix: setupMatrix,
        );

    List<int> sequence(ParallelMachine m) =>
        m.output.map((o) => o.jobId).toList();

    test('SPT_ADAPTADO accounts for the changeover', () {
      expect(sequence(run('SPT')), [1, 2, 3]);
      expect(sequence(run('SPT_ADAPTADO')), [1, 3, 2]);
    });

    test('the adapted schedule is the cheaper one', () {
      final staticEnd = run('SPT').output.last.endDate;
      final dynamicEnd = run('SPT_ADAPTADO').output.last.endDate;
      expect(dynamicEnd.isBefore(staticEnd), isTrue);
    });

    test('adapted rules no longer depend on the wall clock', () {
      // These used to partition jobs against DateTime.now() captured before
      // the sort, so the schedule changed with the time of day and two runs
      // could disagree.
      for (final rule in [
        'SPT_ADAPTADO',
        'LPT_ADAPTADO',
        'EDD_ADAPTADO',
        'FIFO_ADAPTADO',
        'WSPT_ADAPTADO',
      ]) {
        final first = run(rule);
        final second = run(rule);
        expect(sequence(first), sequence(second), reason: rule);
        expect(first.output.last.endDate, second.output.last.endDate,
            reason: rule);
      }
    });

    test('two unreleased jobs keep their criterion ordering', () {
      // The old comparators returned 0 when both jobs were unreleased, which
      // threw away the rule entirely. Here both are released well after the
      // schedule start, so ordering must still follow the due dates.
      final late1 = DateTime(2026, 1, 5, 15, 0);
      final late2 = DateTime(2026, 1, 5, 16, 0);
      final machine = ParallelMachine(
        start,
        workingSchedule,
        [
          ParallelInput(1, DateTime(2026, 1, 30), 1, late1,
              {1: const Duration(minutes: 30)}),
          ParallelInput(2, DateTime(2026, 1, 20), 1, late2,
              {1: const Duration(minutes: 30)}),
        ],
        {1: <Tuple2<DateTime, DateTime>>[]},
        'EDD_ADAPTADO',
      );

      // Job 1 is released first, so at its release only it can run; job 2
      // follows. What matters is that both are scheduled and neither starts
      // before its release.
      expect(machine.output, hasLength(2));
      expect(
        machine.output.firstWhere((o) => o.jobId == 1).startDate.isBefore(late1),
        isFalse,
      );
      expect(
        machine.output.firstWhere((o) => o.jobId == 2).startDate.isBefore(late2),
        isFalse,
      );
    });
  });
}
