import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/shared/types/rnage.dart';

/// Shared calendar logic for scheduling algorithms (work hours + inactivities).
class ScheduleCalendarUtils {
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  final Map<int, List<MachineInactivityEntity>> machineInactivities;

  const ScheduleCalendarUtils({
    required this.workingSchedule,
    this.machineInactivities = const {},
  });

  List<Range> getInactivitiesForDay(int machineId, DateTime day) {
    final inactivities = machineInactivities[machineId] ?? [];
    final weekday = day.weekday;
    final List<Range> dayInactivities = [];

    for (final inactivity in inactivities) {
      final inactivityWeekdays =
          inactivity.weekdays.map((wd) => wd.index + 1).toSet();

      if (inactivityWeekdays.contains(weekday)) {
        final startHour = inactivity.startTime.inHours;
        final startMinute = inactivity.startTime.inMinutes % 60;

        final inactivityStart = DateTime(
          day.year,
          day.month,
          day.day,
          startHour,
          startMinute,
        );

        final inactivityEnd = inactivityStart.add(inactivity.duration);
        dayInactivities.add(Range(inactivityStart, inactivityEnd));
      }
    }

    return dayInactivities;
  }

  DateTime adjustForWorkingSchedule(
    DateTime start, {
    required bool allowWorkHoursInterrupt,
  }) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour,
          workingStart.minute);
    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour,
          workingStart.minute);
    }
    return start;
  }

  /// When [allowWorkHoursInterrupt] is false, work that would cross closing time
  /// waits until the next opening instead of counting overnight as processing.
  DateTime adjustEndTimeForWorkingSchedule(
    DateTime start,
    DateTime end, {
    required bool allowWorkHoursInterrupt,
  }) {
    if (allowWorkHoursInterrupt) {
      TimeOfDay workingEnd = workingSchedule.value2;
      DateTime endOfDay = DateTime(
        start.year,
        start.month,
        start.day,
        workingEnd.hour,
        workingEnd.minute,
      );

      if (end.isAfter(endOfDay)) {
        Duration remainingTime = end.difference(endOfDay);
        return DateTime(
          start.year,
          start.month,
          start.day + 1,
          workingSchedule.value1.hour,
          workingSchedule.value1.minute,
        ).add(remainingTime);
      }
      return end;
    }

    DateTime current = adjustForWorkingSchedule(
      start,
      allowWorkHoursInterrupt: false,
    );
    Duration remaining = end.difference(start);
    if (remaining <= Duration.zero) return current;

    while (remaining > Duration.zero) {
      final dayEnd = DateTime(
        current.year,
        current.month,
        current.day,
        workingSchedule.value2.hour,
        workingSchedule.value2.minute,
      );
      final availableToday = dayEnd.difference(current);
      if (availableToday > Duration.zero && remaining <= availableToday) {
        return current.add(remaining);
      }
      if (availableToday > Duration.zero) {
        remaining -= availableToday;
      }
      current = DateTime(
        current.year,
        current.month,
        current.day + 1,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    }
    return current;
  }

  DateTime adjustEndTimeWithInactivities(
    int machineId,
    DateTime start,
    DateTime end,
    JobInterruptionPolicy policy,
  ) {
    DateTime current = start;
    Duration remaining = end.difference(start);
    final allowScheduled = policy.allowScheduledInterrupt;
    final allowWorkHours = policy.allowWorkHoursInterrupt;

    while (remaining > Duration.zero) {
      current = adjustForWorkingSchedule(
        current,
        allowWorkHoursInterrupt: allowWorkHours,
      );

      final dayInactivities =
          allowScheduled ? getInactivitiesForDay(machineId, current) : [];

      final dayEnd = DateTime(
        current.year,
        current.month,
        current.day,
        workingSchedule.value2.hour,
        workingSchedule.value2.minute,
      );

      DateTime nextAvailable = current;
      for (final inactivity in dayInactivities) {
        if (nextAvailable.isBefore(inactivity.end) &&
            inactivity.start.isBefore(dayEnd)) {
          if (nextAvailable.isBefore(inactivity.start)) {
            final availableBeforeInactivity =
                inactivity.start.difference(nextAvailable);

            if (remaining <= availableBeforeInactivity) {
              return nextAvailable.add(remaining);
            } else {
              remaining -= availableBeforeInactivity;
              nextAvailable = inactivity.end;
            }
          } else {
            if (nextAvailable.isBefore(inactivity.end)) {
              nextAvailable = inactivity.end;
            }
          }
        }
      }

      if (!allowScheduled) {
        for (final inactivity in getInactivitiesForDay(machineId, current)) {
          if (nextAvailable.isBefore(inactivity.end) &&
              inactivity.start.isBefore(dayEnd) &&
              nextAvailable.isBefore(inactivity.start)) {
            final gap = inactivity.start.difference(nextAvailable);
            if (remaining <= gap) {
              return nextAvailable.add(remaining);
            }
            remaining -= gap;
            nextAvailable = inactivity.end;
          } else if (!nextAvailable.isBefore(inactivity.start) &&
              nextAvailable.isBefore(inactivity.end)) {
            nextAvailable = inactivity.end;
          }
        }
      }

      final availableToday = dayEnd.difference(nextAvailable);

      if (availableToday > Duration.zero && remaining <= availableToday) {
        return nextAvailable.add(remaining);
      } else {
        if (availableToday > Duration.zero) {
          remaining -= availableToday;
        }
        current = current.add(const Duration(days: 1));
      }
    }

    return current;
  }

  /// Applies work-hour and scheduled-inactivity adjustments to a task window.
  DateTime computeTaskEnd({
    required int machineId,
    required DateTime start,
    required Duration processingDuration,
    required JobInterruptionPolicy policy,
  }) {
    final naiveEnd = start.add(processingDuration);
    if (policy.allowScheduledInterrupt) {
      return adjustEndTimeWithInactivities(machineId, start, naiveEnd, policy);
    }
    return adjustEndTimeForWorkingSchedule(
      start,
      naiveEnd,
      allowWorkHoursInterrupt: policy.allowWorkHoursInterrupt,
    );
  }
}

Map<int, JobInterruptionPolicy> parseJobInterruptionPolicies(
  dynamic raw,
) {
  if (raw == null) return {};
  final result = <int, JobInterruptionPolicy>{};
  for (final entry in (raw as Map<dynamic, dynamic>).entries) {
    final jobId =
        entry.key is int ? entry.key as int : int.parse(entry.key.toString());
    final map = Map<String, dynamic>.from(entry.value as Map);
    result[jobId] = JobInterruptionPolicy(
      allowRestInterrupt: (map['allowRest'] as int? ?? 0) == 1,
      allowScheduledInterrupt: (map['allowScheduled'] as int? ?? 1) == 1,
      allowWorkHoursInterrupt: (map['allowWorkHours'] as int? ?? 1) == 1,
    );
  }
  return result;
}

Map<String, dynamic> serializeJobInterruptionPolicies(
  Map<int, JobInterruptionPolicy> policies,
) {
  return policies.map((jobId, policy) => MapEntry(jobId.toString(), {
        'allowRest': policy.allowRestInterrupt ? 1 : 0,
        'allowScheduled': policy.allowScheduledInterrupt ? 1 : 0,
        'allowWorkHours': policy.allowWorkHoursInterrupt ? 1 : 0,
      }));
}
