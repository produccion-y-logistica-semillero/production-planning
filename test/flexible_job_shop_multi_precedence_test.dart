// Verifies that FlexibleJobShop (the DAG-capable Non-Delay scheduler used by
// both the "JOB SHOP" and "FLEXIBLE JOB SHOP" environments) correctly
// enforces multiple-predecessor ("precedencia recurrente") relations: a task
// with 2+ predecessors within the same job must not start until ALL of its
// predecessors have finished — i.e. at or after the LATEST predecessor
// completion time, not just any one of them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';

void main() {
  test(
      'a task with two predecessors starts after the later of the two finishes',
      () {
    final start = DateTime(2026, 1, 5, 8, 0); // Monday 08:00
    const workingSchedule =
        Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

    // Task A (id 1) -> machine 1, 2h
    // Task B (id 2) -> machine 2, 3h
    // Task C (id 3) -> machine 3, 1h, depends on BOTH A and B
    final job = FlexibleJobInput(
      1, // jobId
      1, // dbJobId
      1, // sequenceId
      start.add(const Duration(days: 2)), // dueDate
      1, // priority
      start, // availableDate
      [
        const Tuple2(1, {1: Duration(hours: 2)}),
        const Tuple2(2, {2: Duration(hours: 3)}),
        const Tuple2(3, {3: Duration(hours: 1)}),
      ],
      dependencies: [
        TaskDependencyEntity(successor_id: 3, predecessor_id: 1, sequenceId: 1),
        TaskDependencyEntity(successor_id: 3, predecessor_id: 2, sequenceId: 1),
      ],
    );

    final machinesAvailability = {1: start, 2: start, 3: start};

    final scheduler = FlexibleJobShop(
      start,
      workingSchedule,
      [job],
      machinesAvailability,
      'FIFO',
    );

    expect(scheduler.output, hasLength(1));
    final scheduling = scheduler.output.first.scheduling;

    final taskAEnd = scheduling[1]!.value2.end;
    final taskBEnd = scheduling[2]!.value2.end;
    final taskCStart = scheduling[3]!.value2.start;

    final latestPredecessorEnd =
        taskAEnd.isAfter(taskBEnd) ? taskAEnd : taskBEnd;

    expect(
      taskCStart.isBefore(latestPredecessorEnd),
      isFalse,
      reason: 'Task C must not start before both of its predecessors '
          '(A ends $taskAEnd, B ends $taskBEnd) have finished, '
          'but it started at $taskCStart',
    );
  });
}
