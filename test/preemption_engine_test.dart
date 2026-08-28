// Verifies the three interruption sources described by the project lead:
//   1. Jornada de trabajo (work-shift window)
//   2. Descanso por uso continuo (continuous-use rest cap)
//   3. Mantenimiento programado (scheduled maintenance window)
// all correctly PAUSE a job mid-processing and RESUME it afterward,
// preserving the elapsed processing time instead of just blocking new jobs
// from starting during the interruption.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

void main() {
  const workingSchedule =
      Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 19, minute: 0));

  test('work-shift boundary pauses and resumes a job the next working day', () {
    final engine = const PreemptionEngine(workingSchedule: workingSchedule);

    // Starts at 17:00 within a 6am-7pm shift, needs 5h -> only 2h available
    // today before 19:00, so it must pause and resume at 06:00 next day.
    final start = DateTime(2026, 1, 5, 17, 0); // Monday
    final result = engine.computeSegments(
      earliestStart: start,
      totalDuration: const Duration(hours: 5),
    );

    expect(result.segments, hasLength(2));
    expect(result.segments[0].start, start);
    expect(result.segments[0].end, DateTime(2026, 1, 5, 19, 0));
    expect(result.segments[0].duration, const Duration(hours: 2));

    expect(result.segments[1].start, DateTime(2026, 1, 6, 6, 0));
    expect(result.segments[1].end, DateTime(2026, 1, 6, 9, 0));
    expect(result.segments[1].duration, const Duration(hours: 3));

    // Total processed time must equal the requested duration exactly —
    // no work was lost or duplicated across the pause.
    expect(result.totalProcessingDuration, const Duration(hours: 5));
  });

  test('continuous-use cap pauses for the configured rest and resumes', () {
    final engine = const PreemptionEngine(
      workingSchedule: workingSchedule,
      continuousUseCap: Duration(hours: 3),
      restDuration: Duration(hours: 1),
    );

    // Machine already ran 2h continuously (prior job) before this one starts.
    // This job needs 3h more; after 1h it hits the 3h cap and must rest 1h.
    final start = DateTime(2026, 1, 5, 8, 0);
    final result = engine.computeSegments(
      earliestStart: start,
      totalDuration: const Duration(hours: 3),
      priorContinuousUsage: const Duration(hours: 2),
    );

    expect(result.segments, hasLength(2));
    expect(result.segments[0].start, start);
    expect(result.segments[0].end, DateTime(2026, 1, 5, 9, 0));
    expect(result.segments[0].duration, const Duration(hours: 1));

    // 1h rest inserted starting at 09:00 -> resumes at 10:00.
    expect(result.segments[1].start, DateTime(2026, 1, 5, 10, 0));
    expect(result.segments[1].end, DateTime(2026, 1, 5, 12, 0));
    expect(result.segments[1].duration, const Duration(hours: 2));

    expect(result.totalProcessingDuration, const Duration(hours: 3));
  });

  test('scheduled maintenance window pauses and resumes a job on the same day', () {
    final engine = PreemptionEngine(
      workingSchedule: workingSchedule,
      maintenanceWindows: [
        MachineInactivityEntity(
          machineId: 1,
          name: 'Mantenimiento semanal',
          weekdays: const {Weekday.wednesday},
          startTime: const Duration(hours: 15), // 3pm
          duration: const Duration(hours: 1), // until 4pm
        ),
      ],
    );

    // Wednesday 2026-01-07, job starts 14:00 needing 2h -> hits the 15:00
    // maintenance window after 1h, pauses until 16:00, resumes for 1h more.
    final start = DateTime(2026, 1, 7, 14, 0); // Wednesday
    final result = engine.computeSegments(
      earliestStart: start,
      totalDuration: const Duration(hours: 2),
    );

    expect(result.segments, hasLength(2));
    expect(result.segments[0].start, start);
    expect(result.segments[0].end, DateTime(2026, 1, 7, 15, 0));

    expect(result.segments[1].start, DateTime(2026, 1, 7, 16, 0));
    expect(result.segments[1].end, DateTime(2026, 1, 7, 17, 0));

    expect(result.totalProcessingDuration, const Duration(hours: 2));
  });

  test('a job that fits entirely within one segment is not split', () {
    final engine = const PreemptionEngine(workingSchedule: workingSchedule);
    final start = DateTime(2026, 1, 5, 8, 0);
    final result = engine.computeSegments(
      earliestStart: start,
      totalDuration: const Duration(hours: 2),
    );

    expect(result.segments, hasLength(1));
    expect(result.segments.single.start, start);
    expect(result.segments.single.end, DateTime(2026, 1, 5, 10, 0));
  });
}
