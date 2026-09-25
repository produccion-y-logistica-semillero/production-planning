// Flexible Flow Shop's *_ADAPTADO/MS/CR/ATCS rules dispatch STAGE BY STAGE
// (FlexibleFlowShop._runDynamicStagewise), not by ranking whole routes the
// way Flow Shop still does. This is the standard treatment of a hybrid
// flow shop in the literature — Ruiz & Vázquez-Rodríguez (2010); Pinedo,
// *Scheduling*, ch. 4 — because a station with several parallel machines
// does not keep one global machine-to-machine order the way a strict
// permutation flow shop does.
//
// These tests pin down what that switch actually buys:
//   1. a station with several machines spreads its jobs across them;
//   2. the processing order at one station can differ from the order at
//      the one before it — impossible under whole-route ranking;
//   3. the calendar (maintenance) is still respected, and an
//      uninterruptible task still refuses to be split;
//   4. the dispatch is deterministic and schedules every operation once;
//   5. MS/CR still weigh a job's remaining work against its due date.
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';

const workingSchedule =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));

/// Monday
final start = DateTime(2026, 1, 5, 6, 0);
final farDue = DateTime(2026, 1, 30);

FlexibleFlowInput job(
  int id,
  List<Tuple2<int, Map<int, Duration>>> taskSequence, {
  DateTime? due,
  DateTime? release,
  Map<int, bool> interruptibleByTask = const {},
}) =>
    FlexibleFlowInput(
      id,
      due ?? farDue,
      1,
      release ?? start,
      taskSequence,
      interruptibleByTask: interruptibleByTask,
    );

void main() {
  group('Flexible Flow Shop — stage-wise dispatch', () {
    test('a two-machine station spreads its jobs across both machines', () {
      // Station 1 has two identical machines (10, 11); every job takes the
      // same 1h there, so nothing but the loop's own load-balancing decides
      // which machine each job lands on.
      final jobs = List.generate(
        4,
        (i) => job(i + 1, [
          Tuple2(1, {10: const Duration(hours: 1), 11: const Duration(hours: 1)}),
        ]),
      );

      final shop = FlexibleFlowShop(
        start,
        workingSchedule,
        jobs,
        {10: start, 11: start},
        'SPT_ADAPTADO',
      );

      expect(shop.output, hasLength(4));
      final machinesUsed =
          shop.output.map((o) => o.scheduling[1]!.value1).toSet();
      expect(machinesUsed, {10, 11},
          reason: 'both machines of the station should get work, not just '
              'one of them');
    });

    test('the processing order at station 2 can reverse station 1\'s order',
        () {
      // Single machine per station (the same shape Flow Shop uses), so the
      // only thing that can make the two stations disagree on order is the
      // per-station dispatch itself.
      //
      // Job A is quick at station 1 (10min) but very slow at station 2 (3h):
      // it moves through station 1 first and then ties up station 2 for a
      // long time. While it does, jobs B and C both clear station 1 — B
      // first, then C. By the time station 2 frees up, both are queued
      // there; SPT_ADAPTADO prefers C's 10-minute station-2 operation over
      // B's 2-hour one, so C overtakes B even though B arrived first. A
      // whole-route ranking cannot produce this: once route order is fixed,
      // one machine per stage keeps that same order at every stage.
      final jobs = [
        job(1, [
          Tuple2(1, {10: const Duration(minutes: 10)}),
          Tuple2(2, {20: const Duration(hours: 3)}),
        ]),
        job(2, [
          Tuple2(1, {10: const Duration(minutes: 10)}),
          Tuple2(2, {20: const Duration(hours: 2)}),
        ]),
        job(3, [
          Tuple2(1, {10: const Duration(minutes: 10)}),
          Tuple2(2, {20: const Duration(minutes: 10)}),
        ]),
      ];

      final shop = FlexibleFlowShop(
        start,
        workingSchedule,
        jobs,
        {10: start, 20: start},
        'SPT_ADAPTADO',
      );

      DateTime station1Start(int jobId) => shop.output
          .firstWhere((o) => o.jobId == jobId)
          .scheduling[1]!
          .value2
          .start;
      DateTime station2Start(int jobId) => shop.output
          .firstWhere((o) => o.jobId == jobId)
          .scheduling[2]!
          .value2
          .start;

      final station1Order = [1, 2, 3]..sort(
          (a, b) => station1Start(a).compareTo(station1Start(b)));
      final station2Order = [1, 2, 3]..sort(
          (a, b) => station2Start(a).compareTo(station2Start(b)));

      expect(station1Order, [1, 2, 3]);
      expect(station2Order, [1, 3, 2],
          reason: 'job 3 should overtake job 2 at station 2');
    });

    test('a maintenance window still splits an interruptible operation', () {
      final maintenance = [
        const MachineInactivityEntity(
          machineId: 10,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 7), // 07:00 (absolute time of day)
          duration: Duration(hours: 1), // until 08:00
        ),
      ];

      final jobs = [
        job(1, [
          Tuple2(1, {10: const Duration(hours: 2)}),
        ], interruptibleByTask: const {1: true}),
      ];

      final shop = FlexibleFlowShop(
        start,
        workingSchedule,
        jobs,
        {10: start},
        'SPT_ADAPTADO',
        machineInactivities: {10: maintenance},
      );

      final segments = shop.output.single.segmentsByStation[1]!;
      expect(segments.length, greaterThan(1),
          reason: 'the maintenance window should split the operation');
      for (final s in segments) {
        final overlapsMaintenance = s.start.isBefore(DateTime(2026, 1, 5, 8, 0)) &&
            s.end.isAfter(DateTime(2026, 1, 5, 7, 0));
        expect(overlapsMaintenance, isFalse,
            reason: 'no segment should run through the maintenance window');
      }
    });

    test('an uninterruptible operation waits instead of being split', () {
      final maintenance = [
        const MachineInactivityEntity(
          machineId: 10,
          name: 'Mantenimiento',
          weekdays: {Weekday.monday},
          startTime: Duration(hours: 7), // 07:00 (absolute time of day)
          duration: Duration(hours: 1), // until 08:00
        ),
      ];

      // 1h20 does not fit in the 1h gap before maintenance (06:00–07:00),
      // so a non-interruptible job must wait until 08:00 and run as one
      // block, rather than starting at 06:00 and being cut in two.
      final jobs = [
        job(1, [
          Tuple2(1, {10: const Duration(hours: 1, minutes: 20)}),
        ], interruptibleByTask: const {1: false}),
      ];

      final shop = FlexibleFlowShop(
        start,
        workingSchedule,
        jobs,
        {10: start},
        'SPT_ADAPTADO',
        machineInactivities: {10: maintenance},
      );

      final segments = shop.output.single.segmentsByStation[1]!;
      expect(segments, hasLength(1),
          reason: 'a non-interruptible task must run as a single block');
      expect(segments.single.start.isBefore(DateTime(2026, 1, 5, 8, 0)), isFalse);
    });

    test('every dynamic rule is deterministic and schedules each op once', () {
      List<FlexibleFlowInput> buildJobs() => [
            job(1, [
              Tuple2(1, {10: const Duration(minutes: 30)}),
              Tuple2(2, {20: const Duration(hours: 1)}),
            ]),
            job(2, [
              Tuple2(1, {10: const Duration(hours: 1)}),
              Tuple2(2, {20: const Duration(minutes: 30)}),
            ]),
            job(3, [
              Tuple2(1, {10: const Duration(hours: 2)}),
              Tuple2(2, {20: const Duration(minutes: 15)}),
            ]),
          ];

      for (final rule in [
        'SPT_ADAPTADO',
        'LPT_ADAPTADO',
        'EDD_ADAPTADO',
        'FIFO_ADAPTADO',
        'WSPT_ADAPTADO',
        'MS',
        'CR',
        'ATCS',
      ]) {
        FlexibleFlowShop run() => FlexibleFlowShop(
              start,
              workingSchedule,
              buildJobs(),
              {10: start, 20: start},
              rule,
            );

        final first = run();
        final second = run();

        expect(first.output, hasLength(3), reason: rule);
        for (final out in first.output) {
          expect(out.scheduling.keys.toSet(), {1, 2}, reason: rule);
        }
        expect(first.output.map((o) => o.jobId).toSet(), {1, 2, 3},
            reason: rule);

        final firstTimes = {
          for (final o in first.output)
            o.jobId: o.scheduling.map(
                (k, v) => MapEntry(k, Tuple2(v.value1, v.value2.start))),
        };
        final secondTimes = {
          for (final o in second.output)
            o.jobId: o.scheduling.map(
                (k, v) => MapEntry(k, Tuple2(v.value1, v.value2.start))),
        };
        expect(firstTimes.length, secondTimes.length, reason: rule);
        for (final jobId in firstTimes.keys) {
          final a = firstTimes[jobId]!;
          final b = secondTimes[jobId]!;
          for (final stationId in a.keys) {
            expect(a[stationId]!.value1, b[stationId]!.value1, reason: rule);
            expect(a[stationId]!.value2, b[stationId]!.value2, reason: rule);
          }
        }
      }
    });

    test('MS and CR both prefer the job with less slack once remaining '
        'work is counted in', () {
      // Equal station-1 durations, so a plain SPT-style tie would fall back
      // to job id. Job 1's station-2 leg is much longer, which eats its
      // slack and its critical ratio — MS and CR must send it through
      // station 1 first even though nothing about station 1 itself favours
      // it.
      final due = start.add(const Duration(hours: 8));
      final jobs = [
        job(1, [
          Tuple2(1, {10: const Duration(minutes: 30)}),
          Tuple2(2, {20: const Duration(hours: 5)}),
        ], due: due),
        job(2, [
          Tuple2(1, {10: const Duration(minutes: 30)}),
          Tuple2(2, {20: const Duration(minutes: 10)}),
        ], due: due),
      ];

      for (final rule in ['MS', 'CR']) {
        final shop = FlexibleFlowShop(
          start,
          workingSchedule,
          jobs,
          {10: start, 20: start},
          rule,
        );
        final station1Start = shop.output
            .firstWhere((o) => o.jobId == 1)
            .scheduling[1]!
            .value2
            .start;
        final station1StartOther = shop.output
            .firstWhere((o) => o.jobId == 2)
            .scheduling[1]!
            .value2
            .start;
        expect(station1Start.isBefore(station1StartOther) ||
            station1Start.isAtSameMomentAs(start),
            isTrue,
            reason: '$rule should start job 1 (the tighter one) first, '
                'got job1=$station1Start job2=$station1StartOther');
        expect(station1Start.isAfter(station1StartOther), isFalse,
            reason: rule);
      }
    });
  });
}
