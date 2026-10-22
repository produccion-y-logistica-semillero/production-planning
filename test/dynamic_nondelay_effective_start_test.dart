// Dynamic rules are a NON-DELAY schedule generator on EFFECTIVE start times
// (Giffler & Thompson 1960, non-delay variant): at each decision only the
// jobs/operations that can really start earliest — after the preemption
// engine has accounted for shift ends, maintenance, rest caps and the wait
// for a window that fits a non-interruptible block — compete, and the rule
// chooses among those.
//
// These tests pin down the answers to the question that motivated it:
//   * if the job the rule prefers cannot start at t because of an
//     interruption, the next candidate that CAN start at t takes the
//     machine instead of leaving it idle;
//   * if no candidate can start at t, the clock jumps to the earliest
//     effective start.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

void main() {
  group('Single Machine — non-delay on effective start', () {
    test(
        'EDD favourite cannot fit before the shift ends: another job uses the '
        'remaining shift instead of the machine idling', () {
      // Monday 19:00, three hours of shift left.
      final t = DateTime(2026, 1, 5, 19, 0);
      // A: earliest due date, 5h, NOT interruptible → cannot start before
      // Tuesday 06:00. B: later due date, 1h, can run now.
      final a = SingleMachineInput(
          1, const Duration(hours: 5), DateTime(2026, 1, 6, 12), 1, t,
          interruptible: false);
      final b = SingleMachineInput(
          2, const Duration(hours: 1), DateTime(2026, 1, 20), 1, t);

      final machine =
          SingleMachine(1, t, workingSchedule, [a, b], 'EDD_ADAPTADO');

      final byId = {for (final o in machine.output) o.jobId: o};
      expect(byId[2]!.startDate, t,
          reason: 'B can start at t, so it takes the machine');
      expect(byId[1]!.startDate, DateTime(2026, 1, 6, 6, 0),
          reason: 'A still runs as one block, at the next shift');
      expect(byId[1]!.segments, hasLength(1));
      expect(machine.output.first.jobId, 2);
    });

    test('nobody can start at t: the clock jumps to the earliest effective start',
        () {
      // Monday 21:00: one hour of shift left, and both jobs are 2h and
      // non-interruptible — neither can start before Tuesday 06:00.
      final t = DateTime(2026, 1, 5, 21, 0);
      final a = SingleMachineInput(
          1, const Duration(hours: 2), DateTime(2026, 1, 9), 1, t,
          interruptible: false);
      final b = SingleMachineInput(
          2, const Duration(hours: 2), DateTime(2026, 1, 8), 1, t,
          interruptible: false);

      final machine =
          SingleMachine(1, t, workingSchedule, [a, b], 'EDD_ADAPTADO');

      // t* = Tuesday 06:00 for both, so EDD decides: B first.
      expect(machine.output.first.jobId, 2);
      expect(machine.output.first.startDate, DateTime(2026, 1, 6, 6, 0));
      expect(machine.output.last.startDate, DateTime(2026, 1, 6, 8, 0));
    });
  });

  group('Flexible Flow Shop — ranks on effective start, not nominal', () {
    test(
        'a maintenance window that delays the rule\'s favourite lets the job '
        'that can run now go first', () {
      final start = DateTime(2026, 1, 5, 6, 0); // Monday
      // Machine 10 has maintenance Monday 07:00-08:00.
      final maintenance = {
        10: [
          const MachineInactivityEntity(
            machineId: 10,
            name: 'Mantenimiento',
            weekdays: {Weekday.monday},
            startTime: Duration(hours: 7),
            duration: Duration(hours: 1),
          ),
        ],
      };
      // Job 1: EDD favourite, 3h, NOT interruptible → effective start 08:00.
      // Job 2: later due date, 2h, interruptible → can start at 06:00.
      // Both share the same NOMINAL start (06:00); before the fix the rule
      // broke that tie in favour of job 1 and the machine idled 06:00-07:00.
      final jobs = [
        FlexibleFlowInput(1, DateTime(2026, 1, 5, 12), 1, start, [
          Tuple2(1, {10: const Duration(hours: 3)}),
        ], interruptibleByTask: {1: false}),
        FlexibleFlowInput(2, DateTime(2026, 1, 20), 1, start, [
          Tuple2(1, {10: const Duration(hours: 2)}),
        ]),
      ];

      final shop = FlexibleFlowShop(
        start,
        workingSchedule,
        jobs,
        {10: start},
        'EDD_ADAPTADO',
        machineInactivities: maintenance,
      );

      final byId = {for (final o in shop.output) o.jobId: o};
      expect(byId[2]!.scheduling[1]!.value2.start, start);
      // Job 2 runs 06-07 and 08-09; job 1 then gets its 3h block 09-12.
      expect(byId[1]!.scheduling[1]!.value2.start, DateTime(2026, 1, 5, 9, 0));
      expect(byId[1]!.segmentsByStation[1], hasLength(1));
    });
  });
}
