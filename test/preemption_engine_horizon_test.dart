// Regression tests for the two ways the scheduler used to hang forever
// instead of producing a schedule (both reproduced before the fix, both
// killed only by an external timeout — the synchronous loops never even
// let flutter_test's own Timeout fire):
//
//   1. A NON-INTERRUPTIBLE job that fits inside the shift but not inside
//      any maintenance-free stretch of it. `_canEverFitInOneBlock` only
//      compared against the full shift and the continuous-use cap, so it
//      handed the job to the single-block search, which walked forward day
//      after day looking for a gap that never existed.
//   2. Maintenance covering the whole shift, which trapped
//      `_alignToAvailable` between "past today's end" and "inside a window"
//      forever — this one hung even for INTERRUPTIBLE jobs.
//
// Both must now terminate: (1) by degrading to normal splitting, (2) by
// throwing SchedulingHorizonException for the caller to surface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

void main() {
  const shift =
      Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0));

  // Daily 12:00-13:00 maintenance: the 9h shift only ever offers 4h in a row.
  final middayMaintenance = MachineInactivityEntity(
    machineId: 1,
    name: 'Mantenimiento diario',
    weekdays: Weekday.values.toSet(),
    startTime: const Duration(hours: 12),
    duration: const Duration(hours: 1),
  );

  group('largestContiguousWindow', () {
    test('is the whole shift when there is no maintenance', () {
      const engine = PreemptionEngine(workingSchedule: shift);
      expect(engine.largestContiguousWindow(), const Duration(hours: 9));
    });

    test('is the longest maintenance-free stretch, not the shift', () {
      final engine = PreemptionEngine(
        workingSchedule: shift,
        maintenanceWindows: [middayMaintenance],
      );
      expect(engine.largestContiguousWindow(), const Duration(hours: 4));
    });

    test('picks the best weekday when maintenance is not daily', () {
      const engine = PreemptionEngine(
        workingSchedule: shift,
        maintenanceWindows: [
          MachineInactivityEntity(
            machineId: 1,
            name: 'Solo lunes',
            weekdays: {Weekday.monday},
            startTime: Duration(hours: 12),
            duration: Duration(hours: 1),
          ),
        ],
      );
      // Tuesday through Sunday are untouched, so a full shift is available.
      expect(engine.largestContiguousWindow(), const Duration(hours: 9));
    });

    test('is zero when maintenance covers the entire shift every day', () {
      final engine = PreemptionEngine(
        workingSchedule: shift,
        maintenanceWindows: [
          MachineInactivityEntity(
            machineId: 1,
            name: 'Paro total',
            weekdays: Weekday.values.toSet(),
            startTime: const Duration(hours: 7),
            duration: const Duration(hours: 11), // 07:00 -> 18:00
          ),
        ],
      );
      expect(engine.largestContiguousWindow(), Duration.zero);
    });

    test('handles overlapping maintenance windows', () {
      final engine = PreemptionEngine(
        workingSchedule: shift,
        maintenanceWindows: [
          MachineInactivityEntity(
            machineId: 1,
            name: 'A',
            weekdays: Weekday.values.toSet(),
            startTime: const Duration(hours: 10),
            duration: const Duration(hours: 2), // 10:00 -> 12:00
          ),
          MachineInactivityEntity(
            machineId: 1,
            name: 'B',
            weekdays: Weekday.values.toSet(),
            startTime: const Duration(hours: 11),
            duration: const Duration(hours: 2), // 11:00 -> 13:00
          ),
        ],
      );
      // Merged block 10:00-13:00 leaves 08:00-10:00 (2h) and 13:00-17:00 (4h).
      expect(engine.largestContiguousWindow(), const Duration(hours: 4));
    });
  });

  group('non-interruptible job that no gap can hold', () {
    final engine = PreemptionEngine(
      workingSchedule: shift,
      maintenanceWindows: [middayMaintenance],
    );

    test('degrades to splitting instead of searching forever', () {
      final result = engine.computeSegments(
        earliestStart: DateTime(2024, 10, 21, 8, 0), // Monday
        totalDuration: const Duration(minutes: 300), // 5h > the 4h gap
        interruptible: false,
      );

      // 08:00-12:00 (4h), maintenance, 13:00-14:00 (1h).
      expect(result.segments, hasLength(2));
      expect(result.segments[0].start, DateTime(2024, 10, 21, 8, 0));
      expect(result.segments[0].end, DateTime(2024, 10, 21, 12, 0));
      expect(result.segments[1].start, DateTime(2024, 10, 21, 13, 0));
      expect(result.segments[1].end, DateTime(2024, 10, 21, 14, 0));
      expect(result.totalProcessingDuration, const Duration(minutes: 300));
    });

    test('still honours non-interruptibility when a gap DOES fit', () {
      // 2h fits in the 13:00-17:00 gap, so starting at 11:00 the job must be
      // delayed to 13:00 and run in one piece — not split across the window.
      final result = engine.computeSegments(
        earliestStart: DateTime(2024, 10, 21, 11, 0),
        totalDuration: const Duration(hours: 2),
        interruptible: false,
      );

      expect(result.segments, hasLength(1));
      expect(result.segments.single.start, DateTime(2024, 10, 21, 13, 0));
      expect(result.segments.single.end, DateTime(2024, 10, 21, 15, 0));
    });

    test('the same job splits in place when it is interruptible', () {
      final result = engine.computeSegments(
        earliestStart: DateTime(2024, 10, 21, 11, 0),
        totalDuration: const Duration(hours: 2),
        interruptible: true,
      );

      expect(result.segments, hasLength(2));
      expect(result.segments[0].start, DateTime(2024, 10, 21, 11, 0));
      expect(result.segments[0].end, DateTime(2024, 10, 21, 12, 0));
      expect(result.segments[1].start, DateTime(2024, 10, 21, 13, 0));
      expect(result.segments[1].end, DateTime(2024, 10, 21, 14, 0));
    });

    test('a job longer than the continuous-use cap still splits', () {
      const capped = PreemptionEngine(
        workingSchedule: shift,
        continuousUseCap: Duration(minutes: 60),
        restDuration: Duration(minutes: 15),
      );

      final result = capped.computeSegments(
        earliestStart: DateTime(2024, 10, 21, 8, 0),
        totalDuration: const Duration(minutes: 120),
        interruptible: false,
      );

      expect(result.segments, hasLength(2));
      expect(result.segments[0].end, DateTime(2024, 10, 21, 9, 0));
      expect(result.segments[1].start, DateTime(2024, 10, 21, 9, 15));
      expect(result.segments[1].end, DateTime(2024, 10, 21, 10, 15));
    });
  });

  group('calendars that admit no schedule at all', () {
    test('maintenance covering the whole shift throws, even if interruptible',
        () {
      final engine = PreemptionEngine(
        workingSchedule: shift,
        maintenanceWindows: [
          MachineInactivityEntity(
            machineId: 1,
            name: 'Paro total',
            weekdays: Weekday.values.toSet(),
            startTime: const Duration(hours: 7),
            duration: const Duration(hours: 11), // 07:00 -> 18:00
          ),
        ],
      );

      expect(
        () => engine.computeSegments(
          earliestStart: DateTime(2024, 10, 21, 8, 0),
          totalDuration: const Duration(minutes: 30),
        ),
        throwsA(isA<SchedulingHorizonException>()),
      );
    });

    test('an empty shift throws instead of spinning', () {
      const engine = PreemptionEngine(
        workingSchedule:
            Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 8, minute: 0)),
      );

      expect(
        () => engine.computeSegments(
          earliestStart: DateTime(2024, 10, 21, 8, 0),
          totalDuration: const Duration(minutes: 30),
        ),
        throwsA(isA<SchedulingHorizonException>()),
      );
    });

    test('an inverted overnight shift throws instead of spinning', () {
      // The engine does not model shifts crossing midnight; it must say so
      // rather than loop.
      const engine = PreemptionEngine(
        workingSchedule: Tuple2(
            TimeOfDay(hour: 22, minute: 0), TimeOfDay(hour: 6, minute: 0)),
      );

      expect(
        () => engine.computeSegments(
          earliestStart: DateTime(2024, 10, 21, 23, 0),
          totalDuration: const Duration(minutes: 30),
        ),
        throwsA(isA<SchedulingHorizonException>()),
      );
    });

    test('the thrown reason is user-facing, not a stack trace', () {
      const engine = PreemptionEngine(
        workingSchedule:
            Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 8, minute: 0)),
      );

      try {
        engine.computeSegments(
          earliestStart: DateTime(2024, 10, 21, 8, 0),
          totalDuration: const Duration(minutes: 30),
        );
        fail('should have thrown');
      } on SchedulingHorizonException catch (e) {
        expect(e.reason, contains('jornada'));
        expect(e.reason, isNotEmpty);
      }
    });
  });
}
