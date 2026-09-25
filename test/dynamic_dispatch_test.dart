// Unit tests for the release gate and the criteria that drive every
// *_ADAPTADO rule. These exercise dynamic_dispatch.dart in isolation, with a
// trivial stand-in job type, so a failure here points at the dispatch core
// rather than at any one environment's scheduler.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

/// Minimal stand-in for a scheduling input.
class _Job {
  final int id;
  final DateTime release;
  final DateTime due;
  final Duration span;
  final int priority;

  const _Job({
    required this.id,
    required this.release,
    required this.due,
    required this.span,
    this.priority = 1,
  });
}

/// Prices a [_Job] as if its span were fixed — enough to test ordering and
/// gating without dragging a whole environment in.
DispatchCandidate<_Job>? _evaluate(_Job job, DateTime at) => DispatchCandidate(
      job: job,
      start: at,
      end: at.add(job.span),
      span: job.span,
      dueDate: job.due,
      releaseDate: job.release,
      priority: job.priority,
      jobId: job.id,
    );

void main() {
  // Monday
  final t0 = DateTime(2026, 1, 5, 8, 0);
  final due = DateTime(2026, 1, 9);

  group('release gate', () {
    test('a job released later cannot win, however good its criterion', () {
      // Job 2 is by far the shortest, but it is not released yet.
      final pending = [
        _Job(
          id: 1,
          release: t0,
          due: due,
          span: const Duration(hours: 5),
        ),
        _Job(
          id: 2,
          release: t0.add(const Duration(hours: 3)),
          due: due,
          span: const Duration(minutes: 10),
        ),
      ];

      final picked = selectNext<_Job>(
        pending: pending,
        decisionTime: t0,
        releaseTime: (j) => j.release,
        evaluate: _evaluate,
        criterion: DispatchCriterion.spt,
      );

      expect(picked, isNotNull);
      expect(picked!.jobId, 1);
    });

    test('the same job does win once the clock has passed its release', () {
      final pending = [
        _Job(id: 1, release: t0, due: due, span: const Duration(hours: 5)),
        _Job(
          id: 2,
          release: t0.add(const Duration(hours: 3)),
          due: due,
          span: const Duration(minutes: 10),
        ),
      ];

      final picked = selectNext<_Job>(
        pending: pending,
        decisionTime: t0.add(const Duration(hours: 4)),
        releaseTime: (j) => j.release,
        evaluate: _evaluate,
        criterion: DispatchCriterion.spt,
      );

      expect(picked!.jobId, 2);
    });

    test('nothing released yet returns null, and earliestRelease says when',
        () {
      final pending = [
        _Job(
          id: 1,
          release: t0.add(const Duration(hours: 6)),
          due: due,
          span: const Duration(hours: 1),
        ),
        _Job(
          id: 2,
          release: t0.add(const Duration(hours: 2)),
          due: due,
          span: const Duration(hours: 1),
        ),
      ];

      final picked = selectNext<_Job>(
        pending: pending,
        decisionTime: t0,
        releaseTime: (j) => j.release,
        evaluate: _evaluate,
        criterion: DispatchCriterion.spt,
      );

      expect(picked, isNull);
      // This is what stops the dispatch loop from spinning: the caller jumps
      // the clock to the next release instead of asking again at the same
      // instant forever.
      expect(
        earliestRelease(pending, (j) => j.release),
        t0.add(const Duration(hours: 2)),
      );
    });

    test('an empty pending list yields null from both helpers', () {
      expect(
        selectNext<_Job>(
          pending: const [],
          decisionTime: t0,
          releaseTime: (j) => j.release,
          evaluate: _evaluate,
          criterion: DispatchCriterion.spt,
        ),
        isNull,
      );
      expect(earliestRelease<_Job>(const [], (j) => j.release), isNull);
    });
  });

  group('criteria', () {
    final short = _Job(
      id: 1,
      release: t0,
      due: DateTime(2026, 1, 20),
      span: const Duration(hours: 1),
      priority: 1,
    );
    final long = _Job(
      id: 2,
      release: t0.add(const Duration(minutes: 1)),
      due: DateTime(2026, 1, 6),
      span: const Duration(hours: 8),
      priority: 20,
    );

    DispatchCandidate<_Job>? pick(DispatchCriterion criterion) => selectNext(
          pending: [short, long],
          decisionTime: t0.add(const Duration(hours: 1)),
          releaseTime: (j) => j.release,
          evaluate: _evaluate,
          criterion: criterion,
        );

    test('SPT takes the shortest effective span', () {
      expect(pick(DispatchCriterion.spt)!.jobId, short.id);
    });

    test('LPT takes the longest effective span', () {
      expect(pick(DispatchCriterion.lpt)!.jobId, long.id);
    });

    test('EDD takes the earliest due date, not the shortest job', () {
      expect(pick(DispatchCriterion.edd)!.jobId, long.id);
    });

    test('FIFO takes the earliest release, not the shortest job', () {
      expect(pick(DispatchCriterion.fifo)!.jobId, short.id);
    });

    test('WSPT weighs priority against the effective span', () {
      // 20/480 = 0.042 for the long job vs 1/60 = 0.017 for the short one.
      expect(pick(DispatchCriterion.wspt)!.jobId, long.id);
    });

    test('WSPT does not divide by zero on a zero-length span', () {
      final instant = _Job(
        id: 3,
        release: t0,
        due: due,
        span: Duration.zero,
        priority: 5,
      );
      final picked = selectNext<_Job>(
        pending: [short, instant],
        decisionTime: t0,
        releaseTime: (j) => j.release,
        evaluate: _evaluate,
        criterion: DispatchCriterion.wspt,
      );
      expect(picked!.jobId, instant.id);
    });
  });

  group('robustness', () {
    test('a candidate whose simulation is impossible is skipped, not fatal',
        () {
      final ok = _Job(id: 1, release: t0, due: due, span: const Duration(hours: 4));
      final broken =
          _Job(id: 2, release: t0, due: due, span: const Duration(hours: 1));

      final picked = selectNext<_Job>(
        pending: [broken, ok],
        decisionTime: t0,
        releaseTime: (j) => j.release,
        criterion: DispatchCriterion.spt,
        evaluate: (job, at) {
          if (job.id == 2) {
            throw const SchedulingHorizonException(
              'La jornada no admite este trabajo',
              Duration(hours: 1),
            );
          }
          return _evaluate(job, at);
        },
      );

      // The broken job had the shorter span and would otherwise have won.
      expect(picked!.jobId, ok.id);
    });

    test('when every released candidate is impossible the exception surfaces',
        () {
      // Returning null here would read as "nothing is ready yet" and the
      // caller would loop; the configuration error has to reach the user.
      expect(
        () => selectNext<_Job>(
          pending: [
            _Job(id: 1, release: t0, due: due, span: const Duration(hours: 1)),
          ],
          decisionTime: t0,
          releaseTime: (j) => j.release,
          criterion: DispatchCriterion.spt,
          evaluate: (job, at) => throw const SchedulingHorizonException(
            'La jornada no admite este trabajo',
            Duration(hours: 1),
          ),
        ),
        throwsA(isA<SchedulingHorizonException>()),
      );
    });

    test('ties are broken deterministically by job id', () {
      // Identical in every respect the criteria look at. Dart's List.sort is
      // not stable, so without the explicit jobId tie-break the winner could
      // differ between runs.
      final a = _Job(id: 7, release: t0, due: due, span: const Duration(hours: 2));
      final b = _Job(id: 3, release: t0, due: due, span: const Duration(hours: 2));

      for (final order in [
        [a, b],
        [b, a]
      ]) {
        final picked = selectNext<_Job>(
          pending: order,
          decisionTime: t0,
          releaseTime: (j) => j.release,
          evaluate: _evaluate,
          criterion: DispatchCriterion.spt,
        );
        expect(picked!.jobId, 3);
      }
    });
  });
}
