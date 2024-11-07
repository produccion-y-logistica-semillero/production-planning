import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/flow_shop.dart';

void main() {
  test('FlowShop should correctly apply Johnson\'s rule for valid input', () {
    DateTime startDate = DateTime(2024, 8, 30, 8, 0);
    Tuple2<TimeOfDay, TimeOfDay> workingSchedule = const Tuple2(
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 17, minute: 0),
    );

    List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [
      Tuple4(1, DateTime(2024, 8, 30, 17, 0), 1, DateTime(2024, 8, 30, 8, 0)),
      Tuple4(2, DateTime(2024, 8, 30, 17, 0), 2, DateTime(2024, 8, 30, 8, 30)),
      Tuple4(3, DateTime(2024, 8, 30, 17, 0), 3, DateTime(2024, 8, 30, 9, 0)),
      Tuple4(4, DateTime(2024, 8, 30, 17, 0), 4, DateTime(2024, 8, 30, 9, 30)),
      Tuple4(5, DateTime(2024, 8, 30, 17, 0), 5, DateTime(2024, 8, 30, 10, 0)),
      Tuple4(6, DateTime(2024, 8, 30, 17, 0), 6, DateTime(2024, 8, 30, 10, 30)),
      Tuple4(7, DateTime(2024, 8, 30, 17, 0), 7, DateTime(2024, 8, 30, 11, 0)),
    ];

    List<List<Duration>> timeMatrix = [
      [const Duration(hours: 6), const Duration(hours: 3)],
      [const Duration(hours: 2), const Duration(hours: 9)],
      [const Duration(hours: 4), const Duration(hours: 3)],
      [const Duration(hours: 1), const Duration(hours: 8)],
      [const Duration(hours: 7), const Duration(hours: 1)],
      [const Duration(hours: 4), const Duration(hours: 5)],
      [const Duration(hours: 7), const Duration(hours: 6)],
    ];

    // Act: Create an instance of FlowShop and invoke the Johnson's rule
    FlowShop flowShop = FlowShop(
      startDate,
      workingSchedule,
      inputJobs,
      timeMatrix,
      "JHONSON",
    );

    // Assert: Check the output is as expected
    expect(flowShop.output.isNotEmpty, true);
  });

  test('FlowShop should throw an exception for invalid input', () {
    // Invalid timeMatrix with missing durations
    DateTime startDate = DateTime(2024, 8, 30, 8, 0);
    Tuple2<TimeOfDay, TimeOfDay> workingSchedule = const Tuple2(
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 17, minute: 0),
    );

    List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [
      Tuple4(1, DateTime(2024, 8, 30, 17, 0), 1, DateTime(2024, 8, 30, 8, 0)),
    ];

    List<List<Duration>> timeMatrix = [
      [
        const Duration(hours: 2, minutes: 30)
      ], // Only one machine duration provided
    ];

    // Act - Assert: Expect an exception to be thrown
    expect(
      () => FlowShop(
          startDate, workingSchedule, inputJobs, timeMatrix, "JHONSON"),
      throwsException,
    );
  });
}
