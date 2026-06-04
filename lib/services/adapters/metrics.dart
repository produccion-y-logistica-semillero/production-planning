import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';


Metrics getMetricts(List<PlanningMachineEntity> machines,
    List<Tuple5<int, DateTime, DateTime, DateTime, int>> jobsDates) {

  for (var machine in machines) {
    machine.tasks.orderByStartDate();
  }

  final Map<int, Duration> processingTimeByJob = {};
  final Map<int, DateTime> completionByJob = {};
  Duration totalBusyTime = Duration.zero;
  DateTime? earliestTaskStart;
  DateTime? latestTaskEnd;

  for (final machine in machines) {
    for (final task in machine.tasks) {
      final taskDuration = task.endDate.difference(task.startDate);
      totalBusyTime += taskDuration;

      final jobId = task.jobId;
      processingTimeByJob[jobId] =
          (processingTimeByJob[jobId] ?? Duration.zero) + taskDuration;

      final jobEnd = completionByJob[jobId];
      if (jobEnd == null || task.endDate.isAfter(jobEnd)) {
        completionByJob[jobId] = task.endDate;
      }

      earliestTaskStart = earliestTaskStart == null || task.startDate.isBefore(earliestTaskStart)
          ? task.startDate
          : earliestTaskStart;
      latestTaskEnd = latestTaskEnd == null || task.endDate.isAfter(latestTaskEnd)
          ? task.endDate
          : latestTaskEnd;
    }
  }

  final int jobCount = jobsDates.length;
  if (jobCount == 0) {
    return Metrics(
      idle: Duration.zero,
      totalJobs: 0,
      maxDelay: Duration.zero,
      avarageProcessingTime: Duration.zero,
      avarageDelayTime: Duration.zero,
      avarageLatenessTime: Duration.zero,
      delayedJobs: 0,
      makespan: Duration.zero,
      totalFlow: Duration.zero,
      totalTardiness: Duration.zero,
      maxTardiness: Duration.zero,
      totalWeightedTardiness: Duration.zero,
      maxLateness: Duration.zero,
    );
  }

  final Duration makespan = (earliestTaskStart != null && latestTaskEnd != null)
      ? latestTaskEnd.difference(earliestTaskStart)
      : Duration.zero;

  final Duration totalMachineHorizon = Duration(
    microseconds: makespan.inMicroseconds * machines.length,
  );
  final Duration idle = totalMachineHorizon - totalBusyTime;

  Duration totalProcessingTime = Duration.zero;
  Duration totalFlowTime = Duration.zero;
  Duration totalTardiness = Duration.zero;
  Duration totalLateness = Duration.zero;
  Duration maxTardiness = Duration.zero;
  Duration maxLateness = Duration.zero;
  int delayedJobs = 0;
  int totalWeightedTardinessMicros = 0;

  for (final tuple in jobsDates) {
    final jobId = tuple.value1;
    final availableDate = tuple.value2;
    final dueDate = tuple.value4;
    final priority = tuple.value5;
    final completionDate = completionByJob[jobId] ?? availableDate;

    final processingTime = processingTimeByJob[jobId] ?? Duration.zero;
    totalProcessingTime += processingTime;

    final flowTime = completionDate.difference(availableDate);
    totalFlowTime += flowTime;

    final lateness = completionDate.difference(dueDate);
    totalLateness += lateness;

    final tardiness = lateness.isNegative ? Duration.zero : lateness;
    totalTardiness += tardiness;
    if (tardiness > maxTardiness) {
      maxTardiness = tardiness;
    }
    if (lateness > maxLateness) {
      maxLateness = lateness;
    }
    if (!tardiness.isNegative && tardiness > Duration.zero) {
      delayedJobs += 1;
    }

    totalWeightedTardinessMicros += priority * tardiness.inMicroseconds;
  }

  final Duration averageProcessingTime = Duration(
    microseconds: totalProcessingTime.inMicroseconds ~/ jobCount,
  );
  final Duration averageTardiness = Duration(
    microseconds: totalTardiness.inMicroseconds ~/ jobCount,
  );
  final Duration averageLateness = Duration(
    microseconds: totalLateness.inMicroseconds ~/ jobCount,
  );

  return Metrics(
    idle: idle.isNegative ? Duration.zero : idle,
    totalJobs: jobCount,
    maxDelay: maxTardiness,
    avarageProcessingTime: averageProcessingTime,
    avarageDelayTime: averageTardiness,
    avarageLatenessTime: averageLateness,
    delayedJobs: delayedJobs,
    makespan: makespan,
    totalFlow: totalFlowTime,
    totalTardiness: totalTardiness,
    maxTardiness: maxTardiness,
    totalWeightedTardiness:
        Duration(microseconds: totalWeightedTardinessMicros),
    maxLateness: maxLateness,
  );
}

extension on List<PlanningTaskEntity> {
  void orderByStartDate() {
    sort((a, b) => a.startDate.compareTo(b.startDate));
  }
}
