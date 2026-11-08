import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/genetic_params.dart';
import 'package:production_planning/entities/schedule_objective.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';
import 'package:production_planning/services/scheduling/user_sequence.dart';

const _shift =
    Tuple2(TimeOfDay(hour: 6, minute: 0), TimeOfDay(hour: 22, minute: 0));
final _start = DateTime(2026, 9, 7, 6, 0); // Monday

FlowShopInput _fsJob(int id, int a, int b, {DateTime? due}) => FlowShopInput(
      id,
      1,
      due ?? DateTime(2026, 9, 30),
      1,
      _start,
      const [Tuple2(1, 1), Tuple2(2, 2)],
      {1: Duration(minutes: a), 2: Duration(minutes: b)},
    );

List<int> _fsOrder(FlowShop fs) {
  final out = [...fs.output]..sort((x, y) => x.startDate.compareTo(y.startDate));
  return out.map((o) => o.jobId).toList();
}

double _tardinessMinutes(SingleMachine m) => m.output.fold(
    0.0,
    (s, o) => s +
        (o.endDate.isAfter(o.dueDate)
            ? o.endDate.difference(o.dueDate).inMinutes
            : 0));

void main() {
  group('secuencia del usuario', () {
    test('orderByUserSequence puts unlisted jobs last, by release', () {
      final jobs = [1, 2, 3, 4];
      final ordered =
          orderByUserSequence(jobs, [3, 1], (j) => j, (j) => _start);
      expect(ordered, [3, 1, 2, 4]);
    });

    test('flow shop schedules exactly the permutation typed by the user', () {
      final fs = FlowShop(
        _start,
        _shift,
        [_fsJob(1, 30, 30), _fsJob(2, 30, 30), _fsJob(3, 30, 30)],
        {1: _start, 2: _start},
        'SECUENCIA_USUARIO',
        userSequence: const [3, 1, 2],
      );
      expect(_fsOrder(fs), [3, 1, 2]);
    });

    test('single machine schedules exactly the order typed by the user', () {
      final jobs = [
        for (final id in [1, 2, 3])
          SingleMachineInput(
              id, const Duration(minutes: 20), DateTime(2026, 9, 30), 1, _start),
      ];
      final m = SingleMachine(1, _start, _shift, jobs, 'SECUENCIA_USUARIO',
          userSequence: const [2, 3, 1]);
      final out = [...m.output]
        ..sort((x, y) => x.startDate.compareTo(y.startDate));
      expect(out.map((o) => o.jobId), [2, 3, 1]);
    });
  });

  test('Johnson keeps its own sequence instead of re-sorting by job id', () {
    // Set I (a <= b): job 2. Set II by b descending: job 3, job 1.
    final fs = FlowShop(
      _start,
      _shift,
      [_fsJob(1, 50, 20), _fsJob(2, 10, 60), _fsJob(3, 90, 70)],
      {1: _start, 2: _start},
      'JOHNSON',
    );
    expect(_fsOrder(fs), [2, 3, 1]);
  });

  group('algoritmo genetico', () {
    test('parameters survive the isolate payload', () {
      const p = GeneticParams(
        populationSize: 12,
        maxGenerations: 7,
        mutationRate: 0.25,
        objective: ScheduleObjective.totalTardiness,
      );
      final back = GeneticParams.fromMap(p.toMap());
      expect(back.populationSize, 12);
      expect(back.maxGenerations, 7);
      expect(back.mutationRate, 0.25);
      expect(back.objective, ScheduleObjective.totalTardiness);
    });

    test('minimising total tardiness is never worse than EDD (a seed)', () {
      List<SingleMachineInput> jobs() => [
            SingleMachineInput(1, const Duration(minutes: 90),
                DateTime(2026, 9, 7, 9, 0), 1, _start),
            SingleMachineInput(2, const Duration(minutes: 30),
                DateTime(2026, 9, 7, 7, 0), 1, _start),
            SingleMachineInput(3, const Duration(minutes: 60),
                DateTime(2026, 9, 7, 8, 30), 1, _start),
            SingleMachineInput(4, const Duration(minutes: 45),
                DateTime(2026, 9, 7, 7, 30), 1, _start),
          ];
      final edd = SingleMachine(1, _start, _shift, jobs(), 'EDD');
      final ga = SingleMachine(1, _start, _shift, jobs(), 'GENETICS',
          geneticParams: const GeneticParams(
              populationSize: 10,
              maxGenerations: 20,
              objective: ScheduleObjective.totalTardiness));
      expect(ga.output, hasLength(4));
      expect(_tardinessMinutes(ga), lessThanOrEqualTo(_tardinessMinutes(edd)));
    });
  });
}
