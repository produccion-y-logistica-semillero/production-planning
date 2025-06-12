import 'package:dartz/dartz.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';

Metrics getMetricts(List<PlanningMachineEntity> machines, List<Tuple3<DateTime, DateTime, DateTime>> jobsDates) {
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
    );
  }

  // average processing time
  final totalProcessingTime = jobsDates
      .map((tuple) => tuple.value2.difference(tuple.value1))
      .fold(Duration.zero, (a, b) => a + b);
  final averageProcessingTime =
      Duration(minutes: totalProcessingTime.inMinutes ~/ jobsDates.length);

  // average delay
  final totalDelayTime = jobsDates
      .map((dates) =>
          dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .fold(Duration.zero, (a, b) => a + b);
  final averageDelay =
      Duration(minutes: totalDelayTime.inMinutes ~/ jobsDates.length);

  // max delay
  final maxDelay = jobsDates
      .map((dates) =>
          dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .fold(Duration.zero, (a, b) => a.inMinutes > b.inMinutes ? a : b);

  // average lateness (can be negative)
  final totalLatenessTime = jobsDates
      .map((dates) => dates.value2.difference(dates.value3))
      .fold(Duration.zero, (a, b) => a + b);
  final averageLateness =
      Duration(minutes: totalLatenessTime.inMinutes ~/ jobsDates.length);

  // late jobs
  final delayedJobs = jobsDates
      .where((dates) => dates.value2.isAfter(dates.value3))
      .length;

  return Metrics(
    idle: idle,
    totalJobs: jobsDates.length,
    maxDelay: maxDelay,
    avarageProcessingTime: averageProcessingTime,
    avarageDelayTime: averageDelay,
    avarageLatenessTime: averageLateness,
    delayedJobs: delayedJobs,
  );
}

extension on List<PlanningTaskEntity> {
  void orderByStartDate() {
    sort((a, b) => a.startDate.compareTo(b.startDate));
  }
}
