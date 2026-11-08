// Strict per-machine sequences and user routes (rule SECUENCIA_USUARIO with
// machineSequences / userRoutes).
//
// The first test is the example of the reference sheet:
//   Route:     J1 = M1,M2   J2 = M2,M1   J3 = M1,M2
//   Sequence:  M1 = J1,J2,J3   M2 = J2,J1,J3
// with every operation lasting 60 min from Monday 06:00, worked by hand:
//   M1: J1 06-07, J2 07-08, J3 08-09     M2: J2 06-07, J1 07-08, J3 09-10
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/services/scheduling/machine_plan_text.dart';
import 'package:production_planning/services/scheduling/machine_sequence_plan.dart';

const _shift =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));
final _start = DateTime(2026, 9, 7, 6, 0); // Monday
final _due = DateTime(2026, 9, 30);
const _hour = Duration(minutes: 60);

DateTime _at(int h) => DateTime(2026, 9, 7, h, 0);

/// Job shop job: tasks `jobId * 10 + k` in route order, one machine each.
FlexibleJobInput _job(int id, List<int> machines) => FlexibleJobInput(
      id,
      id,
      1,
      _due,
      1,
      _start,
      [
        for (int k = 0; k < machines.length; k++)
          Tuple2(id * 10 + k + 1, {machines[k]: _hour}),
      ],
    );

OpenShopInput _openJob(int id) => OpenShopInput(
      id,
      id,
      1,
      _due,
      1,
      _start,
      [
        Tuple2(id * 10 + 1, {1: _hour}),
        Tuple2(id * 10 + 2, {2: _hour}),
      ],
    );

FlexibleJobShop _jobShop(
        List<FlexibleJobInput> jobs, Map<int, List<int>> sequences) =>
    FlexibleJobShop(
      _start,
      _shift,
      jobs,
      {1: _start, 2: _start},
      'SECUENCIA_USUARIO',
      machineSequences: sequences,
    );

DateTime _startOf(FlexibleJobShop s, int job, int task) => s.output
    .firstWhere((o) => o.jobId == job)
    .scheduling[task]!
    .value2
    .start;

void main() {
  test('job shop respects exactly the sequence of every machine', () {
    final s = _jobShop(
      [_job(1, [1, 2]), _job(2, [2, 1]), _job(3, [1, 2])],
      {1: [1, 2, 3], 2: [2, 1, 3]},
    );
    expect(_startOf(s, 1, 11), _at(6)); // J1 on M1
    expect(_startOf(s, 2, 21), _at(6)); // J2 on M2
    expect(_startOf(s, 1, 12), _at(7)); // J1 on M2 after J2
    expect(_startOf(s, 2, 22), _at(7)); // J2 on M1 after J1
    expect(_startOf(s, 3, 31), _at(8)); // J3 on M1 after J2
    expect(_startOf(s, 3, 32), _at(9)); // J3 on M2 after its own M1
    final ends = {for (final o in s.output) o.jobId: o.endTime};
    expect(ends[1], _at(8));
    expect(ends[2], _at(8));
    expect(ends[3], _at(10));
  });

  test('a machine waits for its next job instead of taking another', () {
    // M1 must do J2 before J1, although J1 is ready first and M1 would
    // otherwise be idle: J2 only reaches M1 after its hour on M2.
    final s = _jobShop(
      [_job(1, [1]), _job(2, [2, 1])],
      {1: [2, 1], 2: [2]},
    );
    expect(_startOf(s, 2, 22), _at(7));
    expect(_startOf(s, 1, 11), _at(8));
  });

  test('a deadlock between the machine sequences is refused', () {
    // J1 = M1,M2 and J2 = M2,M1. M1 = J2,J1 and M2 = J1,J2: J2 waits for
    // its M2 operation (second on M2), which waits for J1's M1 operation
    // (second on M1), which waits for J2 on M1. Nobody can start.
    expect(
      () => _jobShop(
        [_job(1, [1, 2]), _job(2, [2, 1])],
        {1: [2, 1], 2: [1, 2]},
      ),
      throwsA(isA<MachineSequenceException>()
          .having((e) => e.message, 'message', contains('Interbloqueo'))),
    );
  });

  test('a job must appear once per operation', () {
    expect(
      () => _jobShop(
        [_job(1, [1, 2]), _job(2, [2, 1])],
        {1: [1, 2], 2: [2]}, // J1 is missing on M2
      ),
      throwsA(isA<MachineSequenceException>()
          .having((e) => e.message, 'message', contains('job 1'))),
    );
  });

  test('a job can repeat a machine (recirculation)', () {
    // J1 = M1,M2,M1. Its two M1 operations are the 1st and 2nd time it
    // appears in M1's list: M1 = J1, J2, J1.
    final s = _jobShop(
      [_job(1, [1, 2, 1]), _job(2, [1])],
      {1: [1, 2, 1], 2: [1]},
    );
    expect(_startOf(s, 1, 11), _at(6));
    expect(_startOf(s, 2, 21), _at(7));
    expect(_startOf(s, 1, 12), _at(7)); // M2, right after the first M1
    expect(_startOf(s, 1, 13), _at(8)); // second M1 after J2 and its M2
  });

  test('open shop: the user route decides the order of operations', () {
    // Both operations of a job are free (no arrows). J1's route visits M2
    // first, J2's visits M1 first.
    final s = OpenShop(
      _start,
      _shift,
      [_openJob(1), _openJob(2)],
      {1: _start, 2: _start},
      'SECUENCIA_USUARIO',
      machineSequences: {1: [2, 1], 2: [1, 2]},
      userRoutes: {1: [2, 1], 2: [1, 2]},
    );
    final j1 = s.output.firstWhere((o) => o.jobId == 1).scheduling;
    final j2 = s.output.firstWhere((o) => o.jobId == 2).scheduling;
    expect(j1[12]!.value2.start, _at(6)); // J1 on M2 first
    expect(j1[11]!.value2.start, _at(7)); // then on M1
    expect(j2[21]!.value2.start, _at(6)); // J2 on M1 first
    expect(j2[22]!.value2.start, _at(7)); // then on M2
  });

  test('open shop: a route that contradicts the machine queues deadlocks', () {
    // J1 visits M1 then M2; J2 visits M2 then M1. M1 = J2,J1 and M2 = J1,J2
    // make each job's second stop wait for the other job's second stop.
    expect(
      () => OpenShop(
        _start,
        _shift,
        [_openJob(1), _openJob(2)],
        {1: _start, 2: _start},
        'SECUENCIA_USUARIO',
        machineSequences: {1: [2, 1], 2: [1, 2]},
        userRoutes: {1: [1, 2], 2: [2, 1]},
      ),
      throwsA(isA<MachineSequenceException>()),
    );
  });

  test('pasted Excel tables are read like the reference sheet', () {
    const pasted = '6. Ruta [DECISION] - escribe la maquina que visita cada job\n'
        'Job\tOp 1\tOp 2\n'
        'J1\tM1\tM2\n'
        'J2\tM2\tM1\n'
        'J3\tM1\tM2\n'
        '\n'
        '7. Secuencia por maquina [DECISION]\n'
        'Maquina\tPos 1\tPos 2\tPos 3\tPos 4\n'
        'M1\tJ1\tJ2\tJ3\t\n'
        'M2\tJ2\tJ1\tJ3\t\n';
    final plan = parsePastedMachinePlan(pasted);
    expect(plan.routes, {
      'J1': ['M1', 'M2'],
      'J2': ['M2', 'M1'],
      'J3': ['M1', 'M2'],
    });
    expect(plan.sequences, {
      'M1': ['J1', 'J2', 'J3'],
      'M2': ['J2', 'J1', 'J3'],
    });
    expect(parsePastedMachinePlan('solo un titulo').isEmpty, isTrue);
  });

  test('a route that does not match the machine lists is refused', () {
    final ops = [
      for (final j in [1, 2])
        for (int k = 0; k < 2; k++)
          SeqOperation(
            jobId: j,
            taskId: j * 10 + k + 1,
            index: k,
            machines: {k + 1},
            predecessors: const {},
          ),
    ];
    expect(
      () => buildMachineSequencePlan(
        ops: ops,
        machineSequences: {1: [1, 2], 2: [1, 2]},
        userRoutes: {1: [1, 1], 2: [1, 2]}, // J1 visits M1 twice
      ),
      throwsA(isA<MachineSequenceException>()),
    );
  });
}
