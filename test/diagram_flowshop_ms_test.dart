// Throwaway diagnostic (not app data — no DB involved) to compute the exact
// segments the real FlowShop/PreemptionEngine produce for a 2-machine Flow
// Shop under the MS (Minimum Slack) rule with all 3 interruption types
// active, so the Excalidraw example is faithful to actual app behavior.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';

void main() {
  test('compute exact flow-shop MS segments with all interruptions', () {
    final workingSchedule =
        const Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 19, minute: 0));

    // Wednesday 2026-09-09, 06:00 start.
    final start = DateTime(2026, 9, 9, 6, 0);

    const m1 = 1;
    const m2 = 2;

    final maintenance = <int, List<MachineInactivityEntity>>{
      m2: [
        const MachineInactivityEntity(
          machineId: m2,
          name: 'Mantenimiento semanal',
          weekdays: {Weekday.wednesday},
          startTime: Duration(hours: 15),
          duration: Duration(hours: 1),
        ),
      ],
    };

    final continueCapacity = {m1: 120, m2: 120}; // minutes
    final restTime = {
      m1: const Duration(minutes: 30),
      m2: const Duration(minutes: 30),
    };

    // taskId 1 = station M1, taskId 2 = station M2, for every job.
    final job1 = FlowShopInput(
      1, // jobId
      1, // sequenceId
      DateTime(2026, 9, 9, 18, 0), // dueDate (tight -> low slack -> goes first)
      1, // priority
      start, // availableDate
      const [Tuple2(1, m1), Tuple2(2, m2)],
      {1: const Duration(minutes: 150), 2: const Duration(hours: 6, minutes: 30)},
    );
    final job2 = FlowShopInput(
      2,
      1,
      DateTime(2026, 9, 12, 18, 0), // dueDate (looser -> higher slack -> goes second)
      1,
      start,
      const [Tuple2(1, m1), Tuple2(2, m2)],
      {1: const Duration(minutes: 60), 2: const Duration(minutes: 90)},
    );

    final flowShop = FlowShop(
      start,
      workingSchedule,
      [job1, job2],
      {m1: start, m2: start},
      'MINSLACK', // the "MS" rule as exposed to Flow Shop users is named MINSLACK in the algorithm switch
      machineInactivities: maintenance,
      machineContinueCapacity: continueCapacity,
      machineRestTime: restTime,
    );

    print('=== Orden elegido por MS ===');
    for (final out in flowShop.output) {
      print('Job ${out.jobId}: start=${out.startDate} end=${out.endTime}');
    }

    for (final out in flowShop.output) {
      print('\n--- Job ${out.jobId} ---');
      for (final machineId in [m1, m2]) {
        final setup = out.setupSegmentsByMachine[machineId] ?? const [];
        final segs = out.segmentsByMachine[machineId] ?? const [];
        print('  Máquina $machineId:');
        for (final s in setup) {
          print('    [SETUP]  ${_fmt(s.start)} -> ${_fmt(s.end)} (${s.duration.inMinutes} min)');
        }
        for (final s in segs) {
          print('    [PROC ]  ${_fmt(s.start)} -> ${_fmt(s.end)} (${s.duration.inMinutes} min)');
        }
      }
    }
  });
}

String _fmt(DateTime d) =>
    '${d.weekday == 3 ? "Mié" : d.weekday == 4 ? "Jue" : "?"} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
