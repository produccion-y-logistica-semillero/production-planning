// One interruption flag governs a task's setup AND its processing
// (PreemptionEngine.computeSetupAndProcessing):
//
//   * interruptible     → setup and processing may each be split by a shift
//                         end, maintenance window or rest cap (resumable job,
//                         separable setup);
//   * not interruptible → setup + processing are ONE contiguous block: no
//                         cut inside either, and no gap between them
//                         (attached / non-separable setup on a non-resumable
//                         job — Allahverdi et al. 2008; Lee 1996).
//
// Before this, setup was always splittable and a non-interruptible task's
// processing could wait for the next shift AFTER its setup had already run
// the evening before, leaving the machine "set up" overnight.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

void main() {
  const engine = PreemptionEngine(workingSchedule: workingSchedule);
  // Monday 20:30 — 1.5h of shift left.
  final t = DateTime(2026, 1, 5, 20, 30);

  group('PreemptionEngine.computeSetupAndProcessing', () {
    test('not interruptible: setup + processing wait for one window, no gap',
        () {
      final placed = engine.computeSetupAndProcessing(
        earliestStart: t,
        setupDuration: const Duration(hours: 1),
        processingDuration: const Duration(hours: 1),
        interruptible: false,
      );

      expect(placed.setupSegments, hasLength(1));
      expect(placed.setupSegments.single.start, DateTime(2026, 1, 6, 6, 0));
      expect(placed.setupSegments.single.end, DateTime(2026, 1, 6, 7, 0));
      expect(placed.processing.segments, hasLength(1));
      expect(placed.processing.startDate, placed.setupSegments.single.end,
          reason: 'processing starts the instant setup ends');
      expect(placed.end, DateTime(2026, 1, 6, 8, 0));
    });

    test('interruptible: unchanged — setup now, processing split at shift end',
        () {
      final placed = engine.computeSetupAndProcessing(
        earliestStart: t,
        setupDuration: const Duration(hours: 1),
        processingDuration: const Duration(hours: 1),
      );

      expect(placed.setupSegments.single.start, t);
      expect(placed.processing.segments, hasLength(2));
      expect(placed.processing.segments.first.start,
          DateTime(2026, 1, 5, 21, 30));
      expect(placed.end, DateTime(2026, 1, 6, 6, 30));
    });

    test('a block that can never fit degrades to the separable treatment', () {
      // 10h + 10h > the 16h shift: no window will ever hold both.
      final placed = engine.computeSetupAndProcessing(
        earliestStart: DateTime(2026, 1, 5, 6, 0),
        setupDuration: const Duration(hours: 10),
        processingDuration: const Duration(hours: 10),
        interruptible: false,
      );
      expect(placed.setupSegments.first.start, DateTime(2026, 1, 5, 6, 0));
      expect(placed.processing.segments, hasLength(1),
          reason: 'processing alone still fits in one block');
    });

    test('no setup: identical to computeSegments', () {
      final placed = engine.computeSetupAndProcessing(
        earliestStart: t,
        setupDuration: Duration.zero,
        processingDuration: const Duration(hours: 2),
        interruptible: false,
      );
      final plain = engine.computeSegments(
        earliestStart: t,
        totalDuration: const Duration(hours: 2),
        interruptible: false,
      );
      expect(placed.setupSegments, isEmpty);
      expect(placed.processing.startDate, plain.startDate);
      expect(placed.end, plain.completionTime);
    });
  });

  group('Single Machine end to end', () {
    SingleMachine run({required bool interruptible}) => SingleMachine(
          1,
          t,
          workingSchedule,
          [
            SingleMachineInput(
                1, const Duration(hours: 1), DateTime(2026, 1, 9), 1, t,
                jobState: 'B', interruptible: interruptible),
          ],
          'FIFO',
          stateSetupMatrix: {
            1: {
              'A': {'B': 60}
            }
          },
          initialMachineState: {1: 'A'},
        );

    test('non-interruptible job: its setup moves with it to the next shift',
        () {
      final out = run(interruptible: false).output.single;
      expect(out.setupSegments.single.start, DateTime(2026, 1, 6, 6, 0));
      expect(out.segments.single.start, out.setupSegments.single.end);
    });

    test('interruptible job: setup runs tonight, processing resumes tomorrow',
        () {
      final out = run(interruptible: true).output.single;
      expect(out.setupSegments.single.start, t);
      expect(out.segments, hasLength(2));
    });
  });
}
