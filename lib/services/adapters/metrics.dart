import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';


Metrics getMetricts(List<PlanningMachineEntity> machines,
    List<Tuple4<DateTime, DateTime, DateTime, int>> jobsDates) {

  for (var machine in machines) {
    machine.tasks.orderByStartDate();
  }

  // IDLE METRIC
  Duration totalIdle = Duration.zero;
  for (final machine in machines) {
    DateTime? previousEnd;
    for (final task in machine.tasks) {
      if (previousEnd == null) {
        previousEnd = task.endDate;
      } else {
        final currentIdle = task.startDate.difference(previousEnd);
        totalIdle += currentIdle;
        previousEnd = task.endDate;
      }
    }
  }

  final Duration idle = machines.isEmpty
      ? Duration.zero
      : Duration(minutes: totalIdle.inMinutes ~/ machines.length);

  // Si no hay trabajos, retornamos métricas vacías seguras
  if (jobsDates.isEmpty) {
    return Metrics(
      idle: idle,
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

  // average processing time
  final totalProcessingTime = jobsDates
      .map((tuple) => tuple.value2.difference(tuple.value1))
      .fold(Duration.zero, (a, b) => a + b);
  final averageProcessingTime =
      Duration(minutes: totalProcessingTime.inMinutes ~/ jobsDates.length);

  // average tardiness
  final totalTardiness = jobsDates
      .map((dates) => dates.value2.isAfter(dates.value3)
          ? dates.value2.difference(dates.value3)
          : Duration.zero)
      .fold(Duration.zero, (a, b) => a + b);
  final averageTardiness =
      Duration(minutes: totalTardiness.inMinutes ~/ jobsDates.length);

  // max tardiness
  final maxTardiness = jobsDates
      .map((dates) => dates.value2.isAfter(dates.value3)
          ? dates.value2.difference(dates.value3)
          : Duration.zero)
      .fold(Duration.zero, (a, b) => a.inMinutes > b.inMinutes ? a : b);

  // average lateness (can be negative)
  final totalLatenessTime = jobsDates
      .map((dates) => dates.value2.difference(dates.value3))
      .fold(Duration.zero, (a, b) => a + b);
  final averageLateness =
      Duration(minutes: totalLatenessTime.inMinutes ~/ jobsDates.length);

  // max lateness
  final maxLateness = jobsDates
      .map((dates) => dates.value2.difference(dates.value3))
      .fold(Duration.zero, (a, b) => a.inMinutes > b.inMinutes ? a : b);

  // late jobs
  final delayedJobs =
      jobsDates.where((dates) => dates.value2.isAfter(dates.value3)).length;

  // total weighted tardiness: sum of max(delay,0) * priority
  int totalWeightedTardinessMinutes = 0;
  for (final dates in jobsDates) {
    final delay = dates.value2.isAfter(dates.value3)
        ? dates.value2.difference(dates.value3)
        : Duration.zero;
    final priority = dates.value4;
    totalWeightedTardinessMinutes += delay.inMinutes * priority;
  }
  final totalWeightedTardiness =
      Duration(minutes: totalWeightedTardinessMinutes);

  // makespan: difference between earliest release and latest delivery
  DateTime earliestRelease =
      jobsDates.map((t) => t.value1).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime latestEnd =
      jobsDates.map((t) => t.value2).reduce((a, b) => a.isAfter(b) ? a : b);
  final makespan = latestEnd.difference(earliestRelease);

  // total flow: sum of (end - start) per job
  final totalFlow = totalProcessingTime;

  return Metrics(
    idle: idle,
    totalJobs: jobsDates.length,
    maxDelay: maxTardiness,
    avarageProcessingTime: averageProcessingTime,
    avarageDelayTime: averageTardiness,
    avarageLatenessTime: averageLateness,
    delayedJobs: delayedJobs,
    makespan: makespan,
    totalFlow: totalFlow,
    totalTardiness: totalTardiness,
    maxTardiness: maxTardiness,
    totalWeightedTardiness: totalWeightedTardiness,
    maxLateness: maxLateness,
  );
}

extension on List<PlanningTaskEntity> {
  void orderByStartDate() {
    sort((a, b) => a.startDate.compareTo(b.startDate));
  }
}
