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

/// Thrown when the machine's calendar admits no schedule at all for the
/// requested work, so searching forward would never terminate: a shift that
/// never opens, maintenance covering every working hour of every day, or a
/// search that ran past [PreemptionEngine.maxHorizonDays].
///
/// Callers must map this to a user-visible failure. Never let it reach the
/// UI as a raw exception, and never "handle" it by retrying — the answer
/// does not change on a second attempt, the configuration has to.
class SchedulingHorizonException implements Exception {
  /// User-facing explanation (Spanish — it is surfaced in the app, not only
  /// in logs).
  final String reason;

  /// The processing time that could not be placed.
  final Duration totalDuration;

  const SchedulingHorizonException(this.reason, this.totalDuration);

  @override
  String toString() => 'SchedulingHorizonException: $reason '
      '(duración solicitada: ${totalDuration.inMinutes} min)';
}

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
  /// Hard cap on how far forward any search may walk before declaring the
  /// configuration unschedulable. Every loop in this class that advances
  /// day by day is bounded by it, so a pathological calendar surfaces as a
  /// [SchedulingHorizonException] instead of freezing the isolate — which
  /// for five of the seven environments is the UI isolate, i.e. the whole
  /// app.
  static const int maxHorizonDays = 366;

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
  /// single window — longer than the machine's longest uninterrupted
  /// stretch, or longer than the continuous-use cap — an uninterruptible
  /// task is a contradiction the caller configured, so this falls back to
  /// normal interruptible splitting for that one task rather than looping
  /// forever looking for a window that can never exist.
  ///
  /// Throws [SchedulingHorizonException] when the machine has no usable
  /// time at all within [maxHorizonDays].
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

    return _computeSplitSegments(current, totalDuration, priorContinuousUsage);
  }

  /// The normal path: consume [totalDuration] boundary by boundary,
  /// emitting one segment per uninterrupted stretch.
  SegmentedSchedule _computeSplitSegments(
    DateTime start,
    Duration totalDuration,
    Duration priorContinuousUsage,
  ) {
    final segments = <ProcessingSegment>[];
    Duration remaining = totalDuration;
    Duration continuousUsage = priorContinuousUsage;
    DateTime current = start;
    final DateTime horizon = start.add(const Duration(days: maxHorizonDays));

    while (remaining > Duration.zero) {
      if (current.isAfter(horizon)) {
        // Every iteration advances past a boundary, so reaching this means
        // the calendar hands out time in slices too thin to ever finish.
        throw SchedulingHorizonException(
          'La máquina no ofrece suficiente tiempo disponible para completar '
          'el trabajo dentro de un año de calendario. Revisa la jornada '
          'laboral, los mantenimientos programados y el descanso por uso '
          'continuo.',
          totalDuration,
        );
      }

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

  /// A task longer than the machine's longest uninterrupted stretch, or
  /// longer than the continuous-use cap, can never run start-to-finish
  /// without a pause — no start time would ever make it fit.
  ///
  /// The "longest stretch" has to account for maintenance, not just the
  /// length of the shift: a 9h shift with a daily 12:00-13:00 maintenance
  /// only ever offers 4h in a row, so a 5h uninterruptible task is exactly
  /// as impossible as a 10h one.
  bool _canEverFitInOneBlock(Duration totalDuration) {
    if (continuousUseCap > Duration.zero && totalDuration > continuousUseCap) {
      return false;
    }
    return totalDuration <= largestContiguousWindow();
  }

  /// The longest uninterrupted stretch of working time this machine offers
  /// on its best weekday: the shift minus whatever maintenance carves out
  /// of it. [Duration.zero] means the machine is never available and no
  /// schedule can exist for it.
  ///
  /// Public because the order-creation UI uses it to warn before a job is
  /// marked non-interruptible with a duration that could never fit.
  Duration largestContiguousWindow() {
    Duration best = Duration.zero;
    // 2024-01-01 is a Monday, so seven consecutive days cover every weekday
    // exactly once — maintenance windows are configured per weekday.
    final DateTime monday = DateTime(2024, 1, 1);
    for (int i = 0; i < 7; i++) {
      final gap = _largestGapOn(monday.add(Duration(days: i)));
      if (gap > best) best = gap;
    }
    return best;
  }

  /// Longest maintenance-free stretch inside [day]'s working shift.
  Duration _largestGapOn(DateTime day) {
    final dayStart = _workStartOn(day);
    final dayEnd = _workEndOn(day);
    // An empty or inverted shift (e.g. an overnight 22:00-06:00 range, which
    // this engine does not model) offers nothing.
    if (!dayStart.isBefore(dayEnd)) return Duration.zero;

    final windows = _windowsForDay(day)
      ..sort((a, b) => a.start.compareTo(b.start));

    Duration best = Duration.zero;
    DateTime cursor = dayStart;
    for (final w in windows) {
      // Ignore windows falling entirely outside the shift.
      if (!w.end.isAfter(dayStart) || !w.start.isBefore(dayEnd)) continue;

      final gapEnd = w.start.isBefore(dayEnd) ? w.start : dayEnd;
      if (gapEnd.isAfter(cursor)) {
        final gap = gapEnd.difference(cursor);
        if (gap > best) best = gap;
      }
      // Windows may overlap, so the cursor only ever moves forward.
      if (w.end.isAfter(cursor)) {
        cursor = w.end.isAfter(dayEnd) ? dayEnd : w.end;
      }
    }

    if (dayEnd.isAfter(cursor)) {
      final gap = dayEnd.difference(cursor);
      if (gap > best) best = gap;
    }
    return best;
  }

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
    final DateTime horizon = start.add(const Duration(days: maxHorizonDays));

    while (!current.isAfter(horizon)) {
      final boundary = _boundaryLimit(current, continuousUsage);
      if (boundary.limit >= totalDuration) {
        return SegmentedSchedule(
            [ProcessingSegment(current, current.add(totalDuration))]);
      }
      // Walk up to the boundary before stepping over it: _advancePastBoundary
      // only recognises a boundary it is standing on, so calling it from an
      // instant before the next maintenance window would fall through to the
      // one-minute safety net and inch forward instead of jumping.
      current = _advancePastBoundary(
          current.add(boundary.limit), boundary.hitRestCap);
      continuousUsage = Duration.zero;
      current = _alignToAvailable(current);
    }

    // _canEverFitInOneBlock already rejects the shapes we know can never
    // fit, so this is only reachable if the calendar varies in some way it
    // did not anticipate. Degrade to splitting — a Gantt with an extra
    // pause beats an app that stops responding.
    return _computeSplitSegments(start, totalDuration, priorContinuousUsage);
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
  ///
  /// Throws [SchedulingHorizonException] if no such instant exists within
  /// [maxHorizonDays] — a shift that never opens, or maintenance covering
  /// every working hour of every weekday. Without this bound the loop spins
  /// forever, which is what made an all-day maintenance window hang the app
  /// even for interruptible jobs.
  DateTime _alignToAvailable(DateTime dt) {
    DateTime result = dt;
    int daysAdvanced = 0;

    while (true) {
      final dayStart = _workStartOn(result);
      final dayEnd = _workEndOn(result);

      if (result.isBefore(dayStart)) {
        result = dayStart;
        continue;
      }
      if (!result.isBefore(dayEnd)) {
        result = _workStartOn(result.add(const Duration(days: 1)));
        if (++daysAdvanced > maxHorizonDays) {
          throw const SchedulingHorizonException(
            'La máquina no tiene ningún horario disponible: la jornada '
            'laboral está vacía o los mantenimientos programados cubren '
            'todos los días. Ajusta la jornada o los mantenimientos para '
            'poder programar la orden.',
            Duration.zero,
          );
        }
        continue;
      }
      // Each window skip strictly advances `result`, and a day holds
      // finitely many windows, so only day advances need counting.
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
