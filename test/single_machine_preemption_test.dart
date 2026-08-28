// Validates that SingleMachine (the first algorithm wired to the shared
// PreemptionEngine) actually produces a segmented, preempted schedule end
// to end — not just that the engine works in isolation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';

void main() {
  test('a job spanning a scheduled maintenance window is split and resumed', () {
    const workingSchedule =
        Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 19, minute: 0));

    final job = SingleMachineInput(
      1,
      const Duration(hours: 2),
      DateTime(2026, 1, 8), // dueDate, irrelevant here
      1,
      DateTime(2026, 1, 7, 14, 0), // Wednesday 14:00
    );

    final machine = SingleMachine(
      1,
      DateTime(2026, 1, 7, 14, 0),
      workingSchedule,
      [job],
      'FIFO',
      machineInactivities: [
        MachineInactivityEntity(
          machineId: 1,
          name: 'Mantenimiento semanal',
          weekdays: const {Weekday.wednesday},
          startTime: const Duration(hours: 15),
          duration: const Duration(hours: 1),
        ),
      ],
    );

    expect(machine.output, hasLength(1));
    final out = machine.output.single;

    expect(out.segments, hasLength(2));
    expect(out.segments[0].end, DateTime(2026, 1, 7, 15, 0));
    expect(out.segments[1].start, DateTime(2026, 1, 7, 16, 0));
    expect(out.endDate, DateTime(2026, 1, 7, 17, 0));
    expect(
      out.segments.fold(Duration.zero, (sum, s) => sum + s.duration),
      const Duration(hours: 2),
    );
  });

  test('continueCapacity is minutes of continuous use, not a job count', () {
    const workingSchedule =
        Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

    // A single 3h job with a 2h continuous-use cap must be split by itself
    // (previously continueCapacity only counted whole jobs, so a lone long
    // job was never interrupted no matter how long it ran).
    final job = SingleMachineInput(
      1,
      const Duration(hours: 3),
      DateTime(2026, 1, 6),
      1,
      DateTime(2026, 1, 5, 8, 0),
    );

    final machine = SingleMachine(
      1,
      DateTime(2026, 1, 5, 8, 0),
      workingSchedule,
      [job],
      'FIFO',
      continueCapacity: 120, // 2 hours, in minutes
      restTime: const Duration(minutes: 30),
    );

    final out = machine.output.single;
    expect(out.segments, hasLength(2));
    expect(out.segments[0].duration, const Duration(hours: 2));
    expect(out.segments[1].start, out.segments[0].end.add(const Duration(minutes: 30)));
  });
}
