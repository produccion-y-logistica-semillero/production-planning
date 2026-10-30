// Idle time per machine and station, and tardiness per job and station.
//
// The old idle figure was horizon × machines − busy, which counted nights and
// maintenance as idle. The breakdown separates what a machine's horizon
// really was: processing, setup, rest inside operations, time it could not
// work (off-shift, maintenance) and the real idle time.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

const shift = Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0));

/// Monday 5 January 2026.
DateTime mon(int h, [int m = 0]) => DateTime(2026, 1, 5, h, m);
DateTime tue(int h, [int m = 0]) => DateTime(2026, 1, 6, h, m);

PlanningTaskEntity task(
  int jobId,
  List<ProcessingSegment> segments, {
  List<ProcessingSegment> setup = const [],
}) =>
    PlanningTaskEntity(
      sequenceId: 1,
      sequenceName: 'Ruta',
      displayName: 'Job $jobId',
      taskId: jobId * 10,
      numberProcess: 1,
      startDate: (setup.isNotEmpty ? setup : segments).first.start,
      endDate: segments.last.end,
      retarded: false,
      orderId: 1,
      jobId: jobId,
      machineName: 'M',
      segments: segments,
      setupSegments: setup,
    );

ProcessingSegment seg(DateTime a, DateTime b) => ProcessingSegment(a, b);

void main() {
  test('maintenance is unavailable time, not idle time', () {
    // 08:00–10:00 job 1, maintenance 12:00–13:00, setup 13:00–13:30 and
    // job 2 13:30–16:00. Horizon 08:00–16:00 = 8 h.
    final machine = PlanningMachineEntity(
      1,
      'Torno 1',
      [
        task(1, [seg(mon(8), mon(10))]),
        task(2, [seg(mon(13, 30), mon(16))], setup: [seg(mon(13), mon(13, 30))]),
      ],
      stationName: 'Torneado',
      scheduledInactivities: [
        const MachineInactivityEntity(
          machineId: 1,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 12),
          duration: Duration(hours: 1),
        ),
      ],
    );
    final m = getMetricts(
      [machine],
      [
        Tuple5(1, mon(8), mon(10), mon(17), 1),
        Tuple5(2, mon(8), mon(16), mon(17), 1),
      ],
      workingSchedule: shift,
    );
    final u = m.machineUsage.single;
    expect(u.horizon, const Duration(hours: 8));
    expect(u.processing, const Duration(hours: 4, minutes: 30));
    expect(u.setup, const Duration(minutes: 30));
    expect(u.unavailable, const Duration(hours: 1));
    expect(u.rest, Duration.zero);
    // 10:00–12:00: available, without work.
    expect(u.idle, const Duration(hours: 2));
    expect(m.stationUsage.single.stationName, 'Torneado');
    expect(m.stationUsage.single.idle, const Duration(hours: 2));
  });

  test('the night inside an interrupted operation is off-shift, not idle', () {
    // Job 1 runs Mon 15:00–17:00 and resumes Tue 08:00–09:00.
    final machine = PlanningMachineEntity(
      1,
      'Horno',
      [task(1, [seg(mon(15), mon(17)), seg(tue(8), tue(9))])],
      stationName: 'Hornos',
    );
    final u = getMetricts(
      [machine],
      [Tuple5(1, mon(15), tue(9), tue(17), 1)],
      workingSchedule: shift,
    ).machineUsage.single;
    expect(u.horizon, const Duration(hours: 18));
    expect(u.processing, const Duration(hours: 3));
    expect(u.unavailable, const Duration(hours: 15));
    expect(u.rest, Duration.zero);
    expect(u.idle, Duration.zero);
  });

  test('a pause inside the shift is the continuous-use rest', () {
    final machine = PlanningMachineEntity(
      1,
      'Prensa',
      [task(1, [seg(mon(8), mon(10)), seg(mon(10, 30), mon(12))])],
      stationName: 'Prensas',
    );
    final u = getMetricts(
      [machine],
      [Tuple5(1, mon(8), mon(12), mon(17), 1)],
      workingSchedule: shift,
    ).machineUsage.single;
    expect(u.rest, const Duration(minutes: 30));
    expect(u.idle, Duration.zero);
    expect(u.utilization, closeTo(3.5 / 4, 1e-9));
  });

  test('tardiness per job and per station where each job finished', () {
    final cut = PlanningMachineEntity(
      1,
      'Corte 1',
      [task(1, [seg(mon(8), mon(9))]), task(2, [seg(mon(9), mon(10))])],
      stationName: 'Corte',
    );
    final paint = PlanningMachineEntity(
      2,
      'Pintura 1',
      [task(1, [seg(mon(10), mon(12))])],
      stationName: 'Pintura',
    );
    final m = getMetricts(
      [cut, paint],
      [
        // Job 1 ends in Pintura at 12:00, due 11:00 → 1 h late.
        Tuple5(1, mon(8), mon(12), mon(11), 2),
        // Job 2 ends in Corte at 10:00, due 11:00 → on time.
        Tuple5(2, mon(8), mon(10), mon(11), 1),
      ],
      workingSchedule: shift,
    );
    final job1 = m.jobDeliveries.firstWhere((d) => d.jobId == 1);
    expect(job1.lastStation, 'Pintura');
    expect(job1.tardiness, const Duration(hours: 1));
    final job2 = m.jobDeliveries.firstWhere((d) => d.jobId == 2);
    expect(job2.isLate, isFalse);
    expect(job2.earliness, const Duration(hours: 1));

    final pintura = m.stationTardiness.firstWhere((s) => s.stationName == 'Pintura');
    expect(pintura.lateJobs, 1);
    expect(pintura.totalTardiness, const Duration(hours: 1));
    final corte = m.stationTardiness.firstWhere((s) => s.stationName == 'Corte');
    expect(corte.lateJobs, 0);
  });
}
