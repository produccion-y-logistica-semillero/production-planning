// Validates that OpenShop is wired to the shared PreemptionEngine end to end.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/open_shop.dart';

void main() {
  test('a task spanning a scheduled maintenance window is split and resumed', () {
    const workingSchedule =
        Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 19, minute: 0));
    final start = DateTime(2026, 1, 7, 14, 0); // Wednesday

    final job = OpenShopInput(
      1, // jobId
      1, // dbJobId
      1, // sequenceId
      DateTime(2026, 1, 8),
      1,
      start,
      [
        Tuple2(1, {1: const Duration(hours: 2)}), // task 1, only machine 1
      ],
    );

    final scheduler = OpenShop(
      start,
      workingSchedule,
      [job],
      {1: start},
      'FIFO',
      machineInactivities: {
        1: [
          MachineInactivityEntity(
            machineId: 1,
            name: 'Mantenimiento',
            weekdays: const {Weekday.wednesday},
            startTime: const Duration(hours: 15),
            duration: const Duration(hours: 1),
          ),
        ],
      },
    );

    expect(scheduler.output, hasLength(1));
    final segments = scheduler.output.single.segmentsByTask[1]!;
    final range = scheduler.output.single.scheduling[1]!.value2;

    expect(segments, hasLength(2));
    expect(segments[0].end, DateTime(2026, 1, 7, 15, 0));
    expect(segments[1].start, DateTime(2026, 1, 7, 16, 0));
    expect(range.endDate, DateTime(2026, 1, 7, 17, 0));
  });
}
