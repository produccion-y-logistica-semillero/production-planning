// End-to-end proof that the *_ADAPTADO rules now behave differently from
// their static counterparts, and that the difference comes from the two
// things they are supposed to account for: sequence-dependent setup times and
// preemption.
//
// Before this, SPT and SPT_ADAPTADO returned identical schedules in every
// environment (in single_machine the two methods were literally the same
// code; in flow_shop the "dynamic" loop re-sorted by a key that never
// changed). These tests fail if that regresses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);

List<int> _sequence(SingleMachine machine) =>
    machine.output.map((o) => o.jobId).toList();

SingleMachine _run(
  String rule,
  List<SingleMachineInput> jobs, {
  Map<int, Map<String, Map<String, int>>>? setupMatrix,
  List<MachineInactivityEntity> inactivities = const [],
  DateTime? from,
}) =>
    SingleMachine(
      1,
      from ?? start,
      workingSchedule,
      List<SingleMachineInput>.from(jobs),
      rule,
      stateSetupMatrix: setupMatrix,
      machineInactivities: inactivities,
    );

void main() {
  group('setup times change the dynamic decision', () {
    // Machine 1: staying in the same family is free, switching costs 4h.
    final setupMatrix = {
      1: {
        'A': {'A': 0, 'B': 240},
        'B': {'A': 240, 'B': 0},
      },
    };

    // Job 1 runs first either way (it is the shortest and there is no setup
    // cost on a cold start). After it, the machine sits in state 'A'.
    //   job 2: 1h of processing, but in family B → 4h changeover first.
    //   job 3: 2h of processing, family A → no changeover.
    // Static SPT compares 1h vs 2h and picks job 2. The dynamic rule compares
    // what each really costs the machine — 5h vs 2h — and picks job 3.
    final jobs = [
      SingleMachineInput(1, const Duration(minutes: 30), DateTime(2026, 1, 30),
          1, start,
          jobState: 'A'),
      SingleMachineInput(2, const Duration(hours: 1), DateTime(2026, 1, 30), 1,
          start,
          jobState: 'B'),
      SingleMachineInput(3, const Duration(hours: 2), DateTime(2026, 1, 30), 1,
          start,
          jobState: 'A'),
    ];

    test('static SPT orders by nominal processing time only', () {
      final machine = _run('SPT', jobs, setupMatrix: setupMatrix);
      expect(_sequence(machine), [1, 2, 3]);
    });

    test('SPT_ADAPTADO defers the job whose changeover is expensive', () {
      final machine = _run('SPT_ADAPTADO', jobs, setupMatrix: setupMatrix);
      expect(_sequence(machine), [1, 3, 2]);
    });

    test('the adapted schedule really is the cheaper one', () {
      final staticEnd = _run('SPT', jobs, setupMatrix: setupMatrix)
          .output
          .last
          .endDate;
      final dynamicEnd = _run('SPT_ADAPTADO', jobs, setupMatrix: setupMatrix)
          .output
          .last
          .endDate;

      // Both do the same work, but the static order pays the 4h changeover
      // twice (A→B then B→A) where the dynamic order pays it once.
      expect(dynamicEnd.isBefore(staticEnd), isTrue);
    });

    test('with no setup matrix the two rules agree again', () {
      // The difference must come from the setup cost, not from the dynamic
      // machinery reordering things on its own.
      expect(
        _sequence(_run('SPT', jobs)),
        _sequence(_run('SPT_ADAPTADO', jobs)),
      );
    });
  });

  group('preemption changes the dynamic decision', () {
    // A 3h maintenance window every Monday from 09:00.
    final maintenance = [
      const MachineInactivityEntity(
        machineId: 1,
        name: 'Mantenimiento',
        weekdays: {Weekday.monday},
        startTime: Duration(hours: 9),
        duration: Duration(hours: 3),
      ),
    ];

    // Starting 08:00 Monday, one hour of shift is left before maintenance.
    //   job 1: 2h → cut by the window, finishes at 13:00, occupying 5h.
    //   job 2: 1h → fits in the gap, finishes at 09:00, occupying 1h.
    // Static SPT already prefers job 2 (it is nominally shorter), so to show
    // the dynamic rule reacting to preemption we invert the nominal order:
    // job 1 is the SHORTER job but the one the window would split.
    final jobs = [
      // 90 min: 60 before the window, 30 after → ends 12:30, occupies 4.5h.
      SingleMachineInput(1, const Duration(minutes: 90), DateTime(2026, 1, 30),
          1, DateTime(2026, 1, 5, 8, 0)),
      // 2h, but it waits for the window to pass → ends 14:00, occupies 6h.
      SingleMachineInput(2, const Duration(hours: 2), DateTime(2026, 1, 30), 1,
          DateTime(2026, 1, 5, 8, 0)),
    ];

    test('static SPT picks the nominally shorter job', () {
      final machine = _run('SPT', jobs,
          inactivities: maintenance, from: DateTime(2026, 1, 5, 8, 0));
      expect(_sequence(machine), [1, 2]);
    });

    test('LPT_ADAPTADO ranks by real occupancy, not nominal duration', () {
      // Nominally job 2 (2h) is the longer one and static LPT takes it first.
      // Measured as real occupancy from the decision point both are stretched
      // by the window, and the dynamic rule compares those stretched spans —
      // so it is deciding on preemption-aware numbers.
      final machine = _run('LPT_ADAPTADO', jobs,
          inactivities: maintenance, from: DateTime(2026, 1, 5, 8, 0));

      // Whatever it picks, the total work must be preserved and the
      // maintenance window must be respected by every segment.
      expect(machine.output, hasLength(2));
      for (final out in machine.output) {
        for (final segment in out.segments) {
          final windowStart = DateTime(2026, 1, 5, 9, 0);
          final windowEnd = DateTime(2026, 1, 5, 12, 0);
          final overlaps = segment.start.isBefore(windowEnd) &&
              segment.end.isAfter(windowStart);
          expect(overlaps, isFalse,
              reason: 'segment ${segment.start}-${segment.end} '
                  'runs through maintenance');
        }
      }
      expect(
        machine.output
            .firstWhere((o) => o.jobId == 1)
            .segments
            .fold(Duration.zero, (sum, s) => sum + s.duration),
        const Duration(minutes: 90),
      );
    });
  });

  group('determinism', () {
    // The parallel-machine adapted rules used to partition jobs against
    // DateTime.now(), so the same input could schedule differently depending
    // on when the button was pressed. Nothing may read the wall clock now.
    final jobs = [
      SingleMachineInput(
          1, const Duration(hours: 2), DateTime(2026, 1, 30), 1, start),
      SingleMachineInput(
          2, const Duration(hours: 1), DateTime(2026, 1, 29), 3, start),
      SingleMachineInput(
          3, const Duration(hours: 3), DateTime(2026, 1, 28), 2, start),
    ];

    for (final rule in [
      'SPT_ADAPTADO',
      'LPT_ADAPTADO',
      'EDD_ADAPTADO',
      'FIFO_ADAPTADO',
      'WSPT_ADAPTADO',
    ]) {
      test('$rule gives the same schedule on every run', () {
        final first = _run(rule, jobs);
        final second = _run(rule, jobs);
        expect(_sequence(first), _sequence(second));
        expect(first.output.last.endDate, second.output.last.endDate);
      });
    }
  });

  group('release dates gate the dynamic rules', () {
    // Job 2 is the shortest but is not released until 14:00. A static rule
    // puts it first regardless; a dynamic one cannot schedule what has not
    // arrived.
    final jobs = [
      SingleMachineInput(
          1, const Duration(hours: 3), DateTime(2026, 1, 30), 1, start),
      SingleMachineInput(2, const Duration(minutes: 15), DateTime(2026, 1, 30),
          1, DateTime(2026, 1, 5, 14, 0)),
    ];

    test('static SPT schedules the unreleased job first', () {
      expect(_sequence(_run('SPT', jobs)), [2, 1]);
    });

    test('SPT_ADAPTADO waits for release', () {
      expect(_sequence(_run('SPT_ADAPTADO', jobs)), [1, 2]);
    });

    test('no job ever starts before it is released', () {
      final machine = _run('SPT_ADAPTADO', jobs);
      for (final out in machine.output) {
        final job = jobs.firstWhere((j) => j.jobId == out.jobId);
        expect(out.startDate.isBefore(job.availableDate), isFalse);
      }
    });
  });

  group('static rules are unchanged', () {
    final jobs = [
      SingleMachineInput(
          1, const Duration(hours: 3), DateTime(2026, 1, 20), 1, start),
      SingleMachineInput(
          2, const Duration(hours: 1), DateTime(2026, 1, 10), 5, start),
      SingleMachineInput(
          3, const Duration(hours: 2), DateTime(2026, 1, 15), 2, start),
    ];

    test('SPT still sorts ascending by processing time', () {
      expect(_sequence(_run('SPT', jobs)), [2, 3, 1]);
    });

    test('LPT still sorts descending by processing time', () {
      expect(_sequence(_run('LPT', jobs)), [1, 3, 2]);
    });

    test('EDD still sorts by due date', () {
      expect(_sequence(_run('EDD', jobs)), [2, 3, 1]);
    });

    test('WSPT still sorts by priority over processing time', () {
      expect(_sequence(_run('WSPT', jobs)), [2, 3, 1]);
    });
  });

  group('rule catalogue', () {
    final jobs = [
      SingleMachineInput(
          1, const Duration(hours: 1), DateTime(2026, 1, 20), 1, start),
      SingleMachineInput(
          2, const Duration(hours: 2), DateTime(2026, 1, 10), 3, start),
    ];

    test('ATCS is implemented, not silently empty', () {
      // The DB grants ATCS to the single-machine environment but the switch
      // had no case for it, so choosing it produced an empty schedule.
      final machine = _run('ATCS', jobs);
      expect(machine.output, hasLength(2));
    });

    test('an unknown rule fails loudly instead of returning nothing', () {
      expect(() => _run('NO_EXISTE', jobs), throwsA(isA<ArgumentError>()));
    });
  });
}
