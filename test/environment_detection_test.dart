// classifyOrderEnvironment decides which algorithm schedules an order. These
// tests pin each of the ten environments and the cases the previous
// detection got wrong:
//   * routes compared in the order tasks were CREATED instead of the order
//     the arrows give;
//   * recurrent precedences (A and B enable C) reported as Job Shop;
//   * branching and loose tasks treated as Flow / Job Shop;
//   * free jobs with tasks listed in different orders falling into OPEN SHOP
//     even with parallel machines;
//   * the "one free job makes the whole order open" rule never applying.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/services/environment_detection.dart';

/// A route from (taskId, station) pairs in LIST order and arrows.
JobRoute route(List<(int, int)> tasks, [List<(int, int)> arrows = const []]) =>
    JobRoute(
      tasks: [for (final t in tasks) (taskId: t.$1, machineTypeId: t.$2)],
      precedences: [
        for (final a in arrows) (predecessor: a.$1, successor: a.$2),
      ],
    );

/// Stations 1..5 with one machine each, except those in [parallel].
Map<int, int> machines({Set<int> parallel = const {}}) =>
    {for (int s = 1; s <= 5; s++) s: parallel.contains(s) ? 2 : 1};

void main() {
  group('route shape', () {
    test('single, free, chain and graph', () {
      expect(routeShape(route([(1, 1)])), RouteShape.single);
      expect(routeShape(route([(1, 1), (2, 2)])), RouteShape.free);
      expect(routeShape(route([(1, 1), (2, 2), (3, 3)], [(1, 2), (2, 3)])),
          RouteShape.chain);
      // A and B enable C.
      expect(routeShape(route([(1, 1), (2, 2), (3, 3)], [(1, 3), (2, 3)])),
          RouteShape.graph);
      // A enables B and C.
      expect(routeShape(route([(1, 1), (2, 2), (3, 3)], [(1, 2), (1, 3)])),
          RouteShape.graph);
      // A → B, D loose.
      expect(routeShape(route([(1, 1), (2, 2), (4, 4)], [(1, 2)])),
          RouteShape.graph);
    });

    test('arrows to tasks outside the job and self-arrows are ignored', () {
      expect(routeShape(route([(1, 1), (2, 2)], [(1, 1), (7, 2)])),
          RouteShape.free);
    });

    test('a chain is read in arrow order, not list order', () {
      // Created C, A, B; arrows A → B → C.
      final r = route([(3, 3), (1, 1), (2, 2)], [(1, 2), (2, 3)]);
      expect(topologicalTaskOrder(r), [1, 2, 3]);
    });

    test('orderedTasks never drops a task', () {
      TaskEntity t(int id) => TaskEntity(
          id: id,
          processingUnits: const Duration(hours: 1),
          description: '',
          machineTypeId: id,
          machineName: 'M$id');
      final sequence = SequenceEntity(1, [t(3), t(1), t(2)], 'Ruta', [
        TaskDependencyEntity(successor_id: 2, predecessor_id: 1, sequenceId: 1),
        TaskDependencyEntity(successor_id: 3, predecessor_id: 2, sequenceId: 1),
      ]);
      expect(orderedTasks(sequence).map((t) => t.id), [1, 2, 3]);
    });
  });

  group('the ten environments', () {
    test('Single Machine / Parallel Machines', () {
      final jobs = [route([(1, 1)]), route([(2, 1)])];
      expect(classifyOrderEnvironment(jobs, machines()), kSingleMachine);
      expect(classifyOrderEnvironment(jobs, machines(parallel: {1})),
          kParallelMachines);
    });

    test('Flow Shop / Flexible Flow Shop', () {
      final jobs = [
        route([(1, 1), (2, 2)], [(1, 2)]),
        route([(3, 1), (4, 2)], [(3, 4)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kFlowShop);
      expect(classifyOrderEnvironment(jobs, machines(parallel: {2})),
          kFlexibleFlowShop);
    });

    test('Job Shop / Flexible Job Shop', () {
      final jobs = [
        route([(1, 1), (2, 2)], [(1, 2)]),
        route([(3, 2), (4, 1)], [(3, 4)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kJobShop);
      expect(classifyOrderEnvironment(jobs, machines(parallel: {1})),
          kFlexibleJobShop);
    });

    test('Open Shop / Flexible Open Shop', () {
      final jobs = [
        route([(1, 1), (2, 2)]),
        route([(3, 1), (4, 2)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kOpenShop);
      expect(classifyOrderEnvironment(jobs, machines(parallel: {1})),
          kFlexibleOpenShop);
    });

    test('Recurrente / Flexible Recurrente: A and B enable C', () {
      final jobs = [
        route([(1, 1), (2, 2), (3, 3)], [(1, 3), (2, 3)]),
        route([(4, 1), (5, 2), (6, 3)], [(4, 6), (5, 6)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kRecurrente);
      expect(classifyOrderEnvironment(jobs, machines(parallel: {3})),
          kFlexibleRecurrente);
    });
  });

  group('cases the previous detection got wrong', () {
    test('a chain drawn in another order is still a Flow Shop', () {
      final jobs = [
        route([(1, 1), (2, 2), (3, 3)], [(1, 2), (2, 3)]),
        // Same route 1 → 2 → 3, tasks created in the order 3, 1, 2.
        route([(6, 3), (4, 1), (5, 2)], [(4, 5), (5, 6)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kFlowShop);
    });

    test('free jobs listed in different orders, with parallel machines, '
        'are a Flexible Open Shop', () {
      final jobs = [
        route([(1, 1), (2, 2)]),
        route([(4, 2), (3, 1)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines(parallel: {2})),
          kFlexibleOpenShop);
    });

    test('branching and loose tasks are Recurrente', () {
      expect(
        classifyOrderEnvironment([
          route([(1, 1), (2, 2), (3, 3)], [(1, 2), (1, 3)]),
        ], machines()),
        kRecurrente,
      );
      expect(
        classifyOrderEnvironment([
          route([(1, 1), (2, 2), (3, 3)], [(1, 2)]),
        ], machines()),
        kRecurrente,
      );
    });

    test('a route that visits a station twice is a Job Shop', () {
      final jobs = [
        route([(1, 1), (2, 2), (3, 1)], [(1, 2), (2, 3)]),
        route([(4, 1), (5, 2), (6, 1)], [(4, 5), (5, 6)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kJobShop);
    });

    test('one free job makes the whole order open', () {
      final jobs = [
        route([(1, 1), (2, 2)], [(1, 2)]),
        route([(3, 1), (4, 2)]),
      ];
      expect(classifyOrderEnvironment(jobs, machines()), kOpenShop);
    });

    test('single-task jobs on different stations are an Open Shop', () {
      expect(
        classifyOrderEnvironment(
            [route([(1, 1)]), route([(2, 2)])], machines()),
        kOpenShop,
      );
    });

    test('a station with no machine is an error, not "flexible"', () {
      expect(
        () => classifyOrderEnvironment([route([(1, 1)])], {1: 0}),
        throwsA(isA<StationWithoutMachinesException>()),
      );
    });
  });
}
