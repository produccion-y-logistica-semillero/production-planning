import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/services/scheduling/schedule_calendar_utils.dart';

/// Result of placing one task (setup + processing) on a machine.
class MachineTaskScheduleResult {
  final DateTime taskStart;
  final DateTime taskEnd;
  final DateTime machineAvailable;
  final int machineProcessedCount;

  const MachineTaskScheduleResult({
    required this.taskStart,
    required this.taskEnd,
    required this.machineAvailable,
    required this.machineProcessedCount,
  });
}

MachineTaskScheduleResult scheduleMachineTask({
  required ScheduleCalendarUtils calendar,
  required int machineId,
  required DateTime earliestStart,
  required Duration setupDuration,
  required Duration processingDuration,
  required JobInterruptionPolicy policy,
  required int continueCapacity,
  required Duration? restTime,
  required int machineProcessedCount,
}) {
  final workStart = calendar.adjustForWorkingSchedule(
    earliestStart,
    allowWorkHoursInterrupt: policy.allowWorkHoursInterrupt,
  );

  final taskStart = calendar.adjustEndTimeWithInactivities(
    machineId,
    workStart,
    workStart.add(setupDuration),
    policy,
  );

  final taskEnd = calendar.adjustEndTimeWithInactivities(
    machineId,
    taskStart,
    taskStart.add(processingDuration),
    policy,
  );

  var finalAvailability = taskEnd;
  var count = machineProcessedCount + 1;

  if (continueCapacity > 0 && restTime != null && count >= continueCapacity) {
    if (policy.allowRestInterrupt) {
      finalAvailability = taskEnd.add(restTime);
    }
    count = 0;
  }

  return MachineTaskScheduleResult(
    taskStart: taskStart,
    taskEnd: taskEnd,
    machineAvailable: finalAvailability,
    machineProcessedCount: count,
  );
}

Duration machineRestDuration(double restPercentage) {
  if (restPercentage == 100 || restPercentage <= 0) {
    return const Duration(hours: 1);
  }
  final ratio = restPercentage / 100.0;
  return Duration(
    milliseconds: (const Duration(hours: 1).inMilliseconds * ratio).round(),
  );
}
