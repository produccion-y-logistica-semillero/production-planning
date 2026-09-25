// A machine's first job used to always pay zero setup, because there was
// no "previous state" to compare it against. `initialMachineState` (per
// order, machineId → state letter A-J) fixes that: the first job on a
// machine now compares against the configured initial state, same as any
// later job compares against whatever the previous job left behind.
//
// Without a configured initial state, behaviour is unchanged: zero setup
// for the first job, same as before this field existed.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

Duration _setupOf(List<ProcessingSegment> segments) =>
    segments.fold(Duration.zero, (sum, s) => sum + s.duration);

void main() {
  group('Single Machine — initial machine state', () {
    final setupMatrix = {
      1: {
        'A': {'A': 0, 'B': 240},
        'B': {'A': 240, 'B': 0},
      },
    };

    test('the first job pays setup from the configured initial state', () {
      final job = SingleMachineInput(
          1, const Duration(minutes: 30), farDue, 1, start,
          jobState: 'B');

      final withInitial = SingleMachine(
        1,
        start,
        workingSchedule,
        [job],
        'SPT',
        stateSetupMatrix: setupMatrix,
        initialMachineState: const {1: 'A'},
      ).output.single;

      expect(_setupOf(withInitial.setupSegments), const Duration(hours: 4));
    });

    test('with no initial state configured, the first job pays nothing '
        '(unchanged behaviour)', () {
      final job = SingleMachineInput(
          1, const Duration(minutes: 30), farDue, 1, start,
          jobState: 'B');

      final withoutInitial = SingleMachine(
        1,
        start,
        workingSchedule,
        [job],
        'SPT',
        stateSetupMatrix: setupMatrix,
      ).output.single;

      expect(withoutInitial.setupSegments, isEmpty);
    });
  });

  group('Flow Shop — initial machine state', () {
    final setupMatrix = {
      1: {
        'A': {'A': 0, 'B': 240},
        'B': {'A': 240, 'B': 0},
      },
    };
    final jobStates = {
      1: {1: 'B'},
    };

    test('the first job on the route pays setup from the machine\'s '
        'configured initial state', () {
      final job = FlowShopInput(1, 1, farDue, 1, start, [const Tuple2(1, 1)],
          {1: const Duration(minutes: 30)});

      final withInitial = FlowShop(
        start,
        workingSchedule,
        [job],
        {1: start},
        'SPT',
        stateSetupMatrix: setupMatrix,
        jobStates: jobStates,
        initialMachineState: const {1: 'A'},
      ).output.single;

      expect(_setupOf(withInitial.setupSegmentsByMachine[1] ?? const []),
          const Duration(hours: 4));
    });

    test('with no initial state configured, the first job pays nothing '
        '(unchanged behaviour)', () {
      final job = FlowShopInput(1, 1, farDue, 1, start, [const Tuple2(1, 1)],
          {1: const Duration(minutes: 30)});

      final withoutInitial = FlowShop(
        start,
        workingSchedule,
        [job],
        {1: start},
        'SPT',
        stateSetupMatrix: setupMatrix,
        jobStates: jobStates,
      ).output.single;

      expect(withoutInitial.setupSegmentsByMachine[1] ?? const [], isEmpty);
    });
  });
}
