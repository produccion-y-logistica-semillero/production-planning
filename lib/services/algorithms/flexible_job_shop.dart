import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

// Clase Range para definir inicio y fin
class Range {
  final DateTime start;
  final DateTime end;

  Range(this.start, this.end);
}

class FlexibleJobInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  FlexibleJobInput(this.jobId, this.dueDate, this.priority, this.availableDate, this.taskSequence);
}

class FlexibleJobOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;

  FlexibleJobOutput(this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling);
}

class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleJobInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  List<FlexibleJobOutput> output = [];

  FlexibleFlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule,
  ) {
    switch (rule) {
      case "SPT":
        scheduleFlexibleJobShop();
        break;
      case "LPT":
        scheduleFlexibleJobShopLPT();
        break;
    }
  }

  late Map<int, int> jobOperationIndex;

  void scheduleFlexibleJobShop() {
    _schedule((a, b) => a.duration.compareTo(b.duration));
  }

  void scheduleFlexibleJobShopLPT() {
    _schedule((a, b) => b.duration.compareTo(a.duration));
  }

  void _schedule(int Function(dynamic, dynamic) comparator) {
    jobOperationIndex = {
      for (var job in inputJobs) job.jobId: 0,
    };

    Map<int, Map<int, Tuple2<int, Range>>> jobSchedulings = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, DateTime> jobAvailability = {
      for (var job in inputJobs) job.jobId: job.availableDate,
    };

    while (jobOperationIndex.values.any((i) {
      final job = inputJobs.firstWhere((j) => j.jobId == jobOperationIndex.keys.firstWhere((id) => j.jobId == id));
      return i < job.taskSequence.length;
    })) {
      List<({
        FlexibleJobInput job,
        int taskId,
        int machineId,
        Duration duration,
        DateTime earliestStart
      })> candidates = [];

      for (var job in inputJobs) {
        final opIndex = jobOperationIndex[job.jobId]!;
        if (opIndex >= job.taskSequence.length) continue;

        final task = job.taskSequence[opIndex];
        final taskId = task.value1;

        for (var entry in task.value2.entries) {
          final machineId = entry.key;
          final duration = entry.value;
          final machineAvailable = machinesAvailability[machineId] ?? startDate;
          final available = jobAvailability[job.jobId]!;

          final earliestStart = machineAvailable.isAfter(available) ? machineAvailable : available;
          final adjustedStart = _adjustForWorkingSchedule(earliestStart);

          candidates.add((
            job: job,
            taskId: taskId,
            machineId: machineId,
            duration: duration,
            earliestStart: adjustedStart
          ));
        }
      }

      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      final selected = candidates.first;
      final start = selected.earliestStart;
      final end = start.add(selected.duration);
      final adjustedEnd = _adjustEndTimeForWorkingSchedule(start, end);

      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(start, adjustedEnd));

      machinesAvailability[selected.machineId] = adjustedEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      jobOperationIndex[selected.job.jobId] =
          jobOperationIndex[selected.job.jobId]! + 1;
    }

    for (var job in inputJobs) {
      final sched = jobSchedulings[job.jobId]!;
      final start = sched.values.map((t) => t.value2.start).reduce((a, b) => a.isBefore(b) ? a : b);
      final end = sched.values.map((t) => t.value2.end).reduce((a, b) => a.isAfter(b) ? a : b);

      output.add(FlexibleJobOutput(
        job.jobId,
        job.dueDate,
        start,
        end,
        sched,
      ));
    }
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour || (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    } else if (start.hour > workingEnd.hour || (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }
    return end;
  }

  int calcularCmax(List<FlexibleJobOutput> output) {
    final startTimes = output.map((job) => job.startDate).toList();
    final endTimes = output.map((job) => job.endTime).toList();

    final earliestStart = startTimes.reduce((a, b) => a.isBefore(b) ? a : b);
    final latestEnd = endTimes.reduce((a, b) => a.isAfter(b) ? a : b);

    final duration = latestEnd.difference(earliestStart);
    return duration.inHours;
  }
}

// ---------- MAIN ----------
void main() {
  final start = DateTime(2025, 1, 1, 8);
  const workingHours = Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0));

  final jobs = [
    FlexibleJobInput(
      1,
      start.add(const Duration(days: 1)),
      1,
      start,
      [
        const Tuple2(1, {1: const Duration(hours: 3), 2: const Duration(hours: 3)}),
        const Tuple2(2, {3: const Duration(hours: 3), 4: const Duration(hours: 3)}),
        const Tuple2(3, {5: const Duration(hours: 2), 6: const Duration(hours: 2)}),
      ],
    ),
    FlexibleJobInput(
      2,
      start.add(const Duration(days: 1)),
      1,
      start,
      [
        const Tuple2(1, {1: const Duration(hours: 1), 2: const Duration(hours: 1)}),
        const Tuple2(2, {5: const Duration(hours: 5), 6: const Duration(hours: 5)}),
        const Tuple2(3, {3: const Duration(hours: 3), 4: const Duration(hours: 3)}),
      ],
    ),
    FlexibleJobInput(
      3,
      start.add(const Duration(days: 1)),
      1,
      start,
      [
        const Tuple2(1, {3: const Duration(hours: 3), 4: const Duration(hours: 3)}),
        const Tuple2(2, {1: const Duration(hours: 2), 2: const Duration(hours: 2)}),
        const Tuple2(3, {5: const Duration(hours: 3), 6: const Duration(hours: 3)}),
      ],
    ),
  ];

  final machinesAvailability = {
    1: start,
    2: start,
    3: start,
    4: start,
    5: start,
    6: start,
  };

  final scheduler = FlexibleFlowShop(start, workingHours, jobs, machinesAvailability, "LPT");

  for (var output in scheduler.output) {
    print('Job ${output.jobId}');
    output.scheduling.forEach((taskId, entry) {
      print(
        '  Task $taskId -> Machine ${entry.value1}, '
        'Start: ${entry.value2.start}, End: ${entry.value2.end}',
      );
    });
    print('  Job Start: ${output.startDate}, End: ${output.endTime}\n');
  }

  final cmax = scheduler.calcularCmax(scheduler.output);
  print('Cmax: $cmax horas');
}