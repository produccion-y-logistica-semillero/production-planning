// Per-machine, per-station and per-job breakdown of a schedule.
//
// Idle time used to be one number: horizon × machines − busy time, which
// counts nights and maintenance as "idle". Here every machine's horizon
// (first start to last end of the schedule) is split into what it really
// was: processing, setup, rest pauses inside operations, time the machine
// could not work anyway (off-shift, maintenance) and the real idle time —
// available, but without work.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/metrics_breakdown.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

typedef _Interval = ({DateTime start, DateTime end});

/// Total length of the union of [intervals].
Duration _measure(List<_Interval> intervals) {
  final sorted = intervals.where((i) => i.end.isAfter(i.start)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  Duration total = Duration.zero;
  DateTime? curStart, curEnd;
  for (final i in sorted) {
    if (curEnd == null || i.start.isAfter(curEnd)) {
      if (curEnd != null) total += curEnd.difference(curStart!);
      curStart = i.start;
      curEnd = i.end;
    } else if (i.end.isAfter(curEnd)) {
      curEnd = i.end;
    }
  }
  if (curEnd != null) total += curEnd.difference(curStart!);
  return total;
}

/// The parts of [a] not covered by [b], as intervals.
List<_Interval> _subtract(List<_Interval> a, List<_Interval> b) {
  final cuts = b.where((i) => i.end.isAfter(i.start)).toList()
    ..sort((x, y) => x.start.compareTo(y.start));
  final out = <_Interval>[];
  for (final piece in a) {
    var pieces = [piece];
    for (final c in cuts) {
      final next = <_Interval>[];
      for (final p in pieces) {
        if (!c.start.isBefore(p.end) || !c.end.isAfter(p.start)) {
          next.add(p);
          continue;
        }
        if (c.start.isAfter(p.start)) next.add((start: p.start, end: c.start));
        if (c.end.isBefore(p.end)) next.add((start: c.end, end: p.end));
      }
      pieces = next;
    }
    out.addAll(pieces);
  }
  return out;
}

_Interval? _clip(_Interval i, DateTime from, DateTime to) {
  final s = i.start.isBefore(from) ? from : i.start;
  final e = i.end.isAfter(to) ? to : i.end;
  return e.isAfter(s) ? (start: s, end: e) : null;
}

/// Off-shift and maintenance windows of a machine within [from, to].
List<_Interval> _unavailableWindows(
  DateTime from,
  DateTime to,
  Tuple2<TimeOfDay, TimeOfDay> shift,
  List<MachineInactivityEntity> maintenance,
) {
  final out = <_Interval>[];
  DateTime day = DateTime(from.year, from.month, from.day - 1);
  final last = DateTime(to.year, to.month, to.day + 1);
  while (!day.isAfter(last)) {
    final shiftStart = day.add(Duration(
        hours: shift.value1.hour, minutes: shift.value1.minute));
    final shiftEnd = day.add(
        Duration(hours: shift.value2.hour, minutes: shift.value2.minute));
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    // Before the shift and after it, until midnight.
    for (final gap in [
      (start: day, end: shiftStart),
      (start: shiftEnd, end: nextDay),
    ]) {
      final c = _clip(gap, from, to);
      if (c != null) out.add(c);
    }
    for (final m in maintenance) {
      if (!m.weekdays.contains(Weekday.values[day.weekday - 1])) continue;
      final s = day.add(m.startTime);
      final c = _clip((start: s, end: s.add(m.duration)), from, to);
      if (c != null) out.add(c);
    }
    day = nextDay;
  }
  return out;
}

Duration _sum(Iterable<ProcessingSegment> segments) =>
    segments.fold(Duration.zero, (sum, s) => sum + s.duration);

/// How every machine spent the schedule's horizon [from, to].
List<MachineUsage> machineUsage(
  List<PlanningMachineEntity> machines, {
  required DateTime from,
  required DateTime to,
  required Tuple2<TimeOfDay, TimeOfDay> shift,
}) {
  final horizon = to.difference(from);
  final result = <MachineUsage>[];
  for (final machine in machines) {
    final busy = <_Interval>[];
    final restGaps = <_Interval>[];
    Duration processing = Duration.zero;
    Duration setup = Duration.zero;
    for (final task in machine.tasks) {
      processing += _sum(task.segments);
      setup += _sum(task.setupSegments);
      final parts = [...task.setupSegments, ...task.segments]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (int k = 0; k < parts.length; k++) {
        busy.add((start: parts[k].start, end: parts[k].end));
        if (k > 0 && parts[k].start.isAfter(parts[k - 1].end)) {
          restGaps.add((start: parts[k - 1].end, end: parts[k].start));
        }
      }
    }
    final unavailableRaw =
        _unavailableWindows(from, to, shift, machine.scheduledInactivities);
    // A window the machine worked through anyway does not count as lost.
    final unavailable = _measure(_subtract(unavailableRaw, busy));
    // Pauses inside an operation that are not off-shift or maintenance:
    // the rest the continuous-use cap forces.
    final rest = _measure(_subtract(restGaps, unavailableRaw));
    final working = processing + setup;
    var idle = horizon - working - unavailable - rest;
    if (idle.isNegative) idle = Duration.zero;
    result.add(MachineUsage(
      machineId: machine.machineId,
      machineName: machine.machineName,
      stationName: machine.stationName ?? 'Sin estación',
      processing: processing,
      setup: setup,
      rest: rest,
      unavailable: unavailable,
      idle: idle,
      horizon: horizon,
    ));
  }
  return result;
}

/// Machines added up per station, in the order stations first appear.
List<StationUsage> stationUsage(List<MachineUsage> machines) {
  final byStation = <String, List<MachineUsage>>{};
  for (final m in machines) {
    byStation.putIfAbsent(m.stationName, () => []).add(m);
  }
  Duration sum(List<MachineUsage> ms, Duration Function(MachineUsage) f) =>
      ms.fold(Duration.zero, (s, m) => s + f(m));
  return [
    for (final e in byStation.entries)
      StationUsage(
        stationName: e.key,
        machines: e.value.length,
        processing: sum(e.value, (m) => m.processing),
        setup: sum(e.value, (m) => m.setup),
        rest: sum(e.value, (m) => m.rest),
        unavailable: sum(e.value, (m) => m.unavailable),
        idle: sum(e.value, (m) => m.idle),
        horizon: sum(e.value, (m) => m.horizon),
      ),
  ];
}

/// Due-date performance of every job. [jobsDates] holds (job id, release,
/// end, due date, priority) as the adapters pass them to getMetricts.
List<JobDelivery> jobDeliveries(
  List<PlanningMachineEntity> machines,
  List<Tuple5<int, DateTime, DateTime, DateTime, int>> jobsDates,
) {
  final lastByJob = <int, ({DateTime end, String station, String name})>{};
  for (final machine in machines) {
    for (final task in machine.tasks) {
      final current = lastByJob[task.jobId];
      if (current == null || task.endDate.isAfter(current.end)) {
        lastByJob[task.jobId] = (
          end: task.endDate,
          station: machine.stationName ?? 'Sin estación',
          name: task.displayName.isEmpty
              ? 'Job ${task.jobId}'
              : task.displayName,
        );
      }
    }
  }
  return [
    for (final t in jobsDates)
      JobDelivery(
        jobId: t.value1,
        jobName: lastByJob[t.value1]?.name ?? 'Job ${t.value1}',
        lastStation: lastByJob[t.value1]?.station ?? 'Sin estación',
        dueDate: t.value4,
        completion: lastByJob[t.value1]?.end ?? t.value3,
        priority: t.value5,
      ),
  ];
}

/// Tardiness grouped by the station where each job finished.
List<StationTardiness> stationTardiness(List<JobDelivery> deliveries) {
  final byStation = <String, List<JobDelivery>>{};
  for (final d in deliveries) {
    byStation.putIfAbsent(d.lastStation, () => []).add(d);
  }
  return [
    for (final e in byStation.entries)
      StationTardiness(
        stationName: e.key,
        jobs: e.value.length,
        lateJobs: e.value.where((d) => d.isLate).length,
        totalTardiness:
            e.value.fold(Duration.zero, (s, d) => s + d.tardiness),
        maxTardiness: e.value.fold(
            Duration.zero, (m, d) => d.tardiness > m ? d.tardiness : m),
      ),
  ];
}
