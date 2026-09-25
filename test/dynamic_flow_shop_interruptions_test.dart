// Flow Shop keeps ranking whole ROUTES (see flexible_flow_shop.dart's
// _runDynamicStagewise doc comment for why a strict permutation flow shop —
// one machine per stage — is the case where that is still the textbook
// treatment: Pinedo, *Scheduling*, ch. 4; Ruiz & Maroto 2006). These tests
// cover what the plan asked to check on that path specifically: a
// maintenance window on a machine that is neither first nor last in the
// route, a task that refuses to be split, and MS/CR ordering a route by
// slack/critical ratio once a due date is tight.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

void main() {
  group('Flow Shop — interruptions along the route', () {
    test('maintenance on the middle machine of a 3-machine route is '
        'respected, not just on the first or last one', () {
      // Route: machine 1 → machine 2 (maintenance 07:00–08:00) → machine 3.
      final maintenance = [
        const MachineInactivityEntity(
          machineId: 2,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 7),
          duration: Duration(hours: 1),
        ),
      ];

      final job = FlowShopInput(
        1,
        1,
        farDue,
        1,
        start,
        [const Tuple2(1, 1), const Tuple2(2, 2), const Tuple2(3, 3)],
        {
          1: const Duration(minutes: 30),
          2: const Duration(hours: 2),
          3: const Duration(minutes: 30),
        },
      );

      final shop = FlowShop(
        start,
        workingSchedule,
        [job],
        {1: start, 2: start, 3: start},
        'SPT_ADAPTADO',
        machineInactivities: {2: maintenance},
      );

      final out = shop.output.single;
      final segmentsM2 = out.segmentsByMachine[2]!;
      expect(segmentsM2.length, greaterThan(1),
          reason: 'the 2h task on machine 2 should be split around the '
              'maintenance window');
      final maintStart = DateTime(2026, 1, 5, 7, 0);
      final maintEnd = DateTime(2026, 1, 5, 8, 0);
      for (final s in segmentsM2) {
        final overlaps = s.start.isBefore(maintEnd) && s.end.isAfter(maintStart);
        expect(overlaps, isFalse,
            reason: 'no segment on machine 2 should run through maintenance');
      }
      // Machine 3 cannot start before machine 2's work — including the
      // maintenance delay — actually finishes.
      final m2End = out.machinesScheduling[2]!.value2.end;
      final m3Start = out.machinesScheduling[3]!.value2.start;
      expect(m3Start.isBefore(m2End), isFalse);
    });

    test('a non-interruptible task on the route waits for one contiguous '
        'block instead of being split', () {
      final maintenance = [
        const MachineInactivityEntity(
          machineId: 1,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 7),
          duration: Duration(hours: 1),
        ),
      ];

      // 1h20 on machine 1 does not fit in the 1h gap before maintenance
      // (06:00–07:00).
      final job = FlowShopInput(
        1,
        1,
        farDue,
        1,
        start,
        [const Tuple2(1, 1), const Tuple2(2, 2)],
        {
          1: const Duration(hours: 1, minutes: 20),
          2: const Duration(minutes: 30),
        },
        interruptibleByTask: const {1: false},
      );

      final shop = FlowShop(
        start,
        workingSchedule,
        [job],
        {1: start, 2: start},
        'SPT_ADAPTADO',
        machineInactivities: {1: maintenance},
      );

      final out = shop.output.single;
      final segmentsM1 = out.segmentsByMachine[1]!;
      expect(segmentsM1, hasLength(1),
          reason: 'a non-interruptible task must run as a single block');
      expect(
        segmentsM1.single.start.isBefore(DateTime(2026, 1, 5, 8, 0)),
        isFalse,
        reason: 'it should wait until after maintenance rather than start '
            'at 06:00 and get cut in two',
      );
    });

    test('MS and CR send the job with the tighter route down the line '
        'first, not the job with the shorter first machine', () {
      // Both jobs take the same time on machine 1, so a static SPT-style
      // tie falls back to job id. Job 1's SECOND machine is much longer and
      // its due date is tight, which is what MS/CR must react to — nothing
      // about machine 1 by itself favours it.
      final due = start.add(const Duration(hours: 8));
      FlowShopInput job(int id, Duration onM2) => FlowShopInput(
            id,
            id,
            due,
            1,
            start,
            [const Tuple2(1, 1), const Tuple2(2, 2)],
            {1: const Duration(minutes: 30), 2: onM2},
          );

      final jobs = [
        job(1, const Duration(hours: 5)),
        job(2, const Duration(minutes: 10)),
      ];

      for (final rule in ['MS', 'CR']) {
        final shop = FlowShop(
          start,
          workingSchedule,
          List.of(jobs),
          {1: start, 2: start},
          rule,
        );
        final firstScheduled = shop.output.first.jobId;
        expect(firstScheduled, 1,
            reason: '$rule should schedule job 1 (the tighter one) first');
      }
    });
  });
}
