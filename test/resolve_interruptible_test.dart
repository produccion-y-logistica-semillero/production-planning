// The per-job preemption override is what lets two jobs of the same order —
// even two jobs running the same sequence — differ in whether they may be
// split. It is stored per (job, machine) in `job_preemption` and read back
// here; the sequence's own `allow_preemption` is only the fallback.
//
// These tests pin the precedence, because the order-creation UI now seeds an
// entry for every candidate machine and a regression would silently change
// what every existing job does.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/shared/utils/task_time_utils.dart';

void main() {
  TaskEntity task({required bool allowPreemption}) => TaskEntity(
        id: 1,
        processingUnits: const Duration(hours: 2),
        description: 'Planchado',
        machineTypeId: 9,
        machineName: 'Planchado',
        allowPreemption: allowPreemption,
      );

  JobEntity job({Map<int, int>? matrix}) => JobEntity(
        1,
        null,
        'Lote A',
        DateTime(2024, 10, 25),
        1,
        DateTime(2024, 10, 20, 8, 0),
        preemptionMatrix: matrix,
      );

  test('falls back to the sequence flag when the job has no override', () {
    expect(resolveInterruptible(job(), task(allowPreemption: true), 14), isTrue);
    expect(
        resolveInterruptible(job(), task(allowPreemption: false), 14), isFalse);
  });

  test('the job override wins over the sequence flag, in both directions', () {
    // Sequence says "no", this job says "yes".
    expect(
      resolveInterruptible(
          job(matrix: {14: 1}), task(allowPreemption: false), 14),
      isTrue,
    );
    // Sequence says "yes", this job says "no".
    expect(
      resolveInterruptible(
          job(matrix: {14: 0}), task(allowPreemption: true), 14),
      isFalse,
    );
  });

  test('the override is per machine, not per job', () {
    final j = job(matrix: {14: 0, 15: 1});
    final t = task(allowPreemption: true);

    expect(resolveInterruptible(j, t, 14), isFalse);
    expect(resolveInterruptible(j, t, 15), isTrue);
    // A machine with no entry still falls back to the sequence flag — which
    // is why the UI seeds every candidate machine instead of only the
    // selected one.
    expect(resolveInterruptible(j, t, 16), isTrue);
  });

  test('two jobs on the same sequence can differ', () {
    final t = task(allowPreemption: false);
    final interruptible = job(matrix: {14: 1});
    final rigid = job(matrix: {14: 0});

    expect(resolveInterruptible(interruptible, t, 14), isTrue);
    expect(resolveInterruptible(rigid, t, 14), isFalse);
  });
}
