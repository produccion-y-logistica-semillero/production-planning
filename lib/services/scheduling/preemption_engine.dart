// lib/services/scheduling/preemption_engine.dart
//
// Shared primitive for REAL preemption: splitting a job's processing time
// into multiple segments (with pauses in between) whenever it would
// otherwise run through a work-shift boundary, a scheduled maintenance
// window, or the machine's continuous-use rest cap. Progress already made
// in earlier segments is preserved — the job resumes exactly where it left
// off, it does not restart or lose elapsed time.
//
// This replaces the old pattern (duplicated ~5 times across the algorithm
// files) of pushing a job's END time past interruptions while collapsing
// everything into a single (start, end) pair — which hid the pause from the
// Gantt chart and made busy-time metrics overcount paused time as work.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';

/// One contiguous block of actual processing time.
class ProcessingSegment {
  final DateTime start;
  final DateTime end;

  const ProcessingSegment(this.start, this.end);

  Duration get duration => end.difference(start);

  @override
  String toString() => 'ProcessingSegment($start -> $end)';
}

/// The full set of segments a job's processing was split into, in order.
class SegmentedSchedule {
  final List<ProcessingSegment> segments;

  const SegmentedSchedule(this.segments)
      : assert(segments.length > 0, 'segments must not be empty');

  DateTime get startDate => segments.first.start;
  DateTime get completionTime => segments.last.end;

  Duration get totalProcessingDuration =>
      segments.fold(Duration.zero, (sum, s) => sum + s.duration);
}

class _Window {
  final DateTime start;
  final DateTime end;
  const _Window(this.start, this.end);
}

/// Computes segmented schedules for a single machine, given its working
/// hours, scheduled maintenance windows, and continuous-use rest policy.
///
/// [continuousUseCap] is the maximum continuous processing time allowed
/// before a mandatory rest of [restDuration] is inserted. Pass
/// [Duration.zero] to disable the rest policy.
class PreemptionEngine {
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  final List<MachineInactivityEntity> maintenanceWindows;
  final Duration continuousUseCap;
  final Duration restDuration;

  const PreemptionEngine({
    required this.workingSchedule,
    this.maintenanceWindows = const [],
    this.continuousUseCap = Duration.zero,
    this.restDuration = Duration.zero,
  });

  /// Splits [totalDuration] of processing starting no earlier than
  /// [earliestStart] into one or more [ProcessingSegment]s, inserting a
  /// pause wherever the work-shift end, a maintenance window, or the
  /// continuous-use cap would otherwise fall inside the job's span.
  ///
  /// [priorContinuousUsage] carries in how long the machine has already
  /// been running continuously (since its last pause) before this job
  /// starts — callers must accumulate this across the whole schedule.
  ///
  /// [interruptible] set to false means this task must run start-to-finish
  /// without being cut: instead of splitting, its start is delayed until a
  /// window opens up (after the current boundary) that fits the whole
  /// [totalDuration] uninterrupted. If [totalDuration] can never fit in a
  /// single window — longer than a full working day, or longer than the
  /// continuous-use cap — an uninterruptible task is a contradiction the
  /// caller configured, so this falls back to normal interruptible
  /// splitting for that one task rather than looping forever looking for a
  /// window that can never exist.
  SegmentedSchedule computeSegments({
    required DateTime earliestStart,
    required Duration totalDuration,
    Duration priorContinuousUsage = Duration.zero,
    bool interruptible = true,
  }) {
    DateTime current = _alignToAvailable(earliestStart);

    if (totalDuration <= Duration.zero) {
      return SegmentedSchedule([ProcessingSegment(current, current)]);
    }

    if (!interruptible && _canEverFitInOneBlock(totalDuration)) {
      return _computeSingleBlock(current, totalDuration, priorContinuousUsage);
    }

    final segments = <ProcessingSegment>[];
    Duration remaining = totalDuration;
    Duration continuousUsage = priorContinuousUsage;

    while (remaining > Duration.zero) {
      final boundary = _boundaryLimit(current, continuousUsage);
      Duration limit = boundary.limit;
      if (remaining < limit) limit = remaining;

      if (limit > Duration.zero) {
        final segmentEnd = current.add(limit);
        segments.add(ProcessingSegment(current, segmentEnd));
        current = segmentEnd;
        remaining -= limit;
        continuousUsage += limit;
      }

      if (remaining > Duration.zero) {
        current = _advancePastBoundary(current, boundary.hitRestCap);
        continuousUsage = Duration.zero;
        current = _alignToAvailable(current);
      }
    }

    return SegmentedSchedule(segments);
  }

  /// A task longer than the daily working window, or longer than the
  /// continuous-use cap, can never run start-to-finish without a pause —
  /// no start time would ever make it fit.
  bool _canEverFitInOneBlock(Duration totalDuration) {
    final dailyWindow = _workEndOn(_wed()).difference(_workStartOn(_wed()));
    if (totalDuration > dailyWindow) return false;
    if (continuousUseCap > Duration.zero && totalDuration > continuousUseCap) {
      return false;
    }
    return true;
  }

  // Any fixed reference date works here — only the time-of-day components
  // of workingSchedule matter for computing the daily window's length.
  DateTime _wed() => DateTime(2024, 1, 3, 0, 0);

  /// Searches forward from [start] for the earliest instant at which the
  /// whole [totalDuration] fits before the next boundary, returning it as a
  /// single uninterrupted segment.
  SegmentedSchedule _computeSingleBlock(
    DateTime start,
    Duration totalDuration,
    Duration priorContinuousUsage,
  ) {
    DateTime current = start;
    Duration continuousUsage = priorContinuousUsage;

    // Bounded by construction: _canEverFitInOneBlock guarantees a fitting
    // window exists, and each iteration strictly advances past a boundary
    // (day, maintenance window, or rest cap), so this terminates.
    while (true) {
      final boundary = _boundaryLimit(current, continuousUsage);
      if (boundary.limit >= totalDuration) {
        return SegmentedSchedule(
            [ProcessingSegment(current, current.add(totalDuration))]);
      }
      current = _advancePastBoundary(current, boundary.hitRestCap);
      continuousUsage = Duration.zero;
      current = _alignToAvailable(current);
    }
  }

  /// How much processing time can happen at [current] before the nearest
  /// boundary (end of working day, next maintenance window today, or the
  /// continuous-use rest cap), and whether the rest cap was the binding
  /// constraint (needed to pick the right pause in [_advancePastBoundary]).
  ({Duration limit, bool hitRestCap}) _boundaryLimit(
    DateTime current,
    Duration continuousUsage,
  ) {
    final workEnd = _workEndOn(current);
    Duration limit = workEnd.difference(current);

    final nextMaintenance = _nextMaintenanceStart(current, workEnd);
    if (nextMaintenance != null) {
      final untilMaintenance = nextMaintenance.difference(current);
      if (untilMaintenance < limit) limit = untilMaintenance;
    }

    bool hitRestCap = false;
    if (continuousUseCap > Duration.zero) {
      var untilRestCap = continuousUseCap - continuousUsage;
      if (untilRestCap < Duration.zero) untilRestCap = Duration.zero;
      if (untilRestCap <= limit) {
        limit = untilRestCap;
        hitRestCap = true;
      }
    }

    return (limit: limit, hitRestCap: hitRestCap);
  }

  // ── boundary helpers ──────────────────────────────────────────────────────

  DateTime _workStartOn(DateTime dt) => DateTime(
        dt.year,
        dt.month,
        dt.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );

  DateTime _workEndOn(DateTime dt) => DateTime(
        dt.year,
        dt.month,
        dt.day,
        workingSchedule.value2.hour,
        workingSchedule.value2.minute,
      );

  List<_Window> _windowsForDay(DateTime day) {
    final weekday = day.weekday; // DateTime.weekday: 1=Mon..7=Sun
    final dayStart = DateTime(day.year, day.month, day.day);
    final result = <_Window>[];
    for (final inactivity in maintenanceWindows) {
      final matches =
          inactivity.weekdays.map((wd) => wd.index + 1).contains(weekday);
      if (!matches) continue;
      final start = dayStart.add(inactivity.startTime);
      final end = start.add(inactivity.duration);
      result.add(_Window(start, end));
    }
    return result;
  }

  DateTime? _activeMaintenanceWindowEnd(DateTime dt) {
    for (final w in _windowsForDay(dt)) {
      if (!dt.isBefore(w.start) && dt.isBefore(w.end)) return w.end;
    }
    return null;
  }

  DateTime? _nextMaintenanceStart(DateTime current, DateTime workEnd) {
    DateTime? nearest;
    for (final w in _windowsForDay(current)) {
      if (w.start.isAfter(current) && w.start.isBefore(workEnd)) {
        if (nearest == null || w.start.isBefore(nearest)) nearest = w.start;
      }
    }
    return nearest;
  }

  /// Pushes [dt] forward to the next instant the machine is actually
  /// available: inside working hours and not inside a maintenance window.
  DateTime _alignToAvailable(DateTime dt) {
    DateTime result = dt;
    while (true) {
      final dayStart = _workStartOn(result);
      final dayEnd = _workEndOn(result);

      if (result.isBefore(dayStart)) {
        result = dayStart;
        continue;
      }
      if (!result.isBefore(dayEnd)) {
        result = _workStartOn(result.add(const Duration(days: 1)));
        continue;
      }
      final windowEnd = _activeMaintenanceWindowEnd(result);
      if (windowEnd != null) {
        result = windowEnd;
        continue;
      }
      return result;
    }
  }

  /// Advances [current] past whichever boundary it is sitting on: end of
  /// the working day, a maintenance window, or the continuous-use rest cap
  /// (checked in that priority order, since a tie is resolved by whichever
  /// interruption is "bigger").
  DateTime _advancePastBoundary(DateTime current, bool hitRestCap) {
    final workEnd = _workEndOn(current);
    if (!current.isBefore(workEnd)) {
      return _workStartOn(current.add(const Duration(days: 1)));
    }

    final windowEnd = _activeMaintenanceWindowEnd(current);
    if (windowEnd != null) {
      return windowEnd;
    }

    if (hitRestCap && restDuration > Duration.zero) {
      return current.add(restDuration);
    }

    // Safety net: should not normally be reached (guarantees progress).
    return current.add(const Duration(minutes: 1));
  }
}
