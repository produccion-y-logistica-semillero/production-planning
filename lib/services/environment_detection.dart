// lib/services/environment_detection.dart
//
// Classifies a production order into one of the scheduling environments the
// platform knows, from the routes of its jobs and how many machines each
// station has. Pure: no database, no async — OrdersService.getOrderEnvironment
// gathers the data and calls [classifyOrderEnvironment].
//
// Environment names are the `environments.name` values in the database.

import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';

const String kSingleMachine = 'SINGLE MACHINE';
const String kParallelMachines = 'PARALLEL MACHINES';
const String kFlowShop = 'FLOW SHOP';
const String kFlexibleFlowShop = 'FLEXIBLE FLOW SHOP';
const String kJobShop = 'JOB SHOP';
const String kFlexibleJobShop = 'FLEXIBLE JOB SHOP';
const String kOpenShop = 'OPEN SHOP';
const String kFlexibleOpenShop = 'FLEXIBLE OPEN SHOP';
const String kRecurrente = 'RECURRENTE';
const String kFlexibleRecurrente = 'FLEXIBLE RECURRENTE';

/// One job's route: its tasks (id → station, i.e. machine type) in the order
/// the sequence lists them, and its precedence arrows (predecessor →
/// successor).
class JobRoute {
  final List<({int taskId, int machineTypeId})> tasks;
  final List<({int predecessor, int successor})> precedences;

  const JobRoute({required this.tasks, this.precedences = const []});

  factory JobRoute.fromSequence(SequenceEntity sequence) => JobRoute(
        tasks: [
          for (final task in sequence.tasks ?? const <TaskEntity>[])
            if (task.id != null)
              (taskId: task.id!, machineTypeId: task.machineTypeId),
        ],
        precedences: [
          for (final dep in sequence.dependencies ?? const [])
            (predecessor: dep.predecessor_id, successor: dep.successor_id),
        ],
      );
}

/// The shape of one job's precedence graph.
enum RouteShape {
  /// A single task.
  single,

  /// Several tasks and no precedence at all: they can be done in any order.
  free,

  /// One path through every task: each task has at most one predecessor and
  /// one successor, and following the arrows visits them all.
  chain,

  /// Anything else: a task needing two or more predecessors (A and B enable
  /// C), a task enabling two or more (A enables B and C), or tasks left out
  /// of the arrows.
  graph,
}

/// The precedence arrows of [route] that are meaningful: both ends are tasks
/// of the job and they are different tasks. Duplicates are dropped.
Set<({int predecessor, int successor})> validPrecedences(JobRoute route) {
  final ids = route.tasks.map((t) => t.taskId).toSet();
  return {
    for (final p in route.precedences)
      if (p.predecessor != p.successor &&
          ids.contains(p.predecessor) &&
          ids.contains(p.successor))
        p,
  };
}

RouteShape routeShape(JobRoute route) {
  final int n = route.tasks.length;
  if (n <= 1) return RouteShape.single;
  final edges = validPrecedences(route);
  if (edges.isEmpty) return RouteShape.free;
  if (edges.length != n - 1) return RouteShape.graph;

  final Map<int, int> inDegree = {};
  final Map<int, int> outDegree = {};
  for (final e in edges) {
    inDegree[e.successor] = (inDegree[e.successor] ?? 0) + 1;
    outDegree[e.predecessor] = (outDegree[e.predecessor] ?? 0) + 1;
  }
  if (inDegree.values.any((d) => d > 1) ||
      outDegree.values.any((d) => d > 1)) {
    return RouteShape.graph;
  }
  // n − 1 arrows, no task with two in or two out: a set of paths. It is one
  // path covering every task exactly when the topological walk reaches all
  // of them (a cycle would stop it short).
  final order = topologicalTaskOrder(route);
  return order.length == n ? RouteShape.chain : RouteShape.graph;
}

/// The tasks of [route] in precedence order (Kahn's algorithm). Among tasks
/// that are ready at the same time, the one listed first in the sequence
/// goes first, so a route without arrows comes back in list order.
///
/// Tasks caught in a cycle are left out; callers that need every task check
/// the length.
List<int> topologicalTaskOrder(JobRoute route) {
  final ids = [for (final t in route.tasks) t.taskId];
  final edges = validPrecedences(route);
  final Map<int, int> pending = {for (final id in ids) id: 0};
  final Map<int, List<int>> successors = {};
  for (final e in edges) {
    pending[e.successor] = pending[e.successor]! + 1;
    successors.putIfAbsent(e.predecessor, () => []).add(e.successor);
  }

  final result = <int>[];
  final done = <int>{};
  while (true) {
    int? next;
    for (final id in ids) {
      if (!done.contains(id) && pending[id] == 0) {
        next = id;
        break;
      }
    }
    if (next == null) break;
    done.add(next);
    result.add(next);
    for (final s in successors[next] ?? const <int>[]) {
      pending[s] = pending[s]! - 1;
    }
  }
  return result;
}

/// [tasks] of [sequence] in precedence order — see [topologicalTaskOrder].
/// Tasks the order cannot place (a cycle) are appended in list order, so no
/// task is ever dropped.
List<TaskEntity> orderedTasks(SequenceEntity sequence) {
  final tasks = sequence.tasks ?? const <TaskEntity>[];
  final order = topologicalTaskOrder(JobRoute.fromSequence(sequence));
  final byId = {for (final t in tasks) t.id: t};
  final result = <TaskEntity>[
    for (final id in order)
      if (byId[id] != null) byId[id]!,
  ];
  for (final t in tasks) {
    if (!result.contains(t)) result.add(t);
  }
  return result;
}

/// Thrown when an order cannot be classified because a station it uses has
/// no machine registered.
class StationWithoutMachinesException implements Exception {
  final int machineTypeId;
  const StationWithoutMachinesException(this.machineTypeId);
  @override
  String toString() =>
      'La estación (tipo de máquina $machineTypeId) no tiene máquinas.';
}

/// Classifies an order.
///
/// [machineCountByType] gives, for every station the routes use, how many
/// machines it has. The order is FLEXIBLE when any of them has more than one.
///
/// Per job, the route is [RouteShape.single], [RouteShape.free],
/// [RouteShape.chain] or [RouteShape.graph]. Then, from the most to the
/// least specific:
///
///  1. any FREE job → Open Shop. Agreed rule: a job without an imposed order
///     makes the whole order an open shop; jobs that do have arrows keep them
///     inside the algorithm.
///  2. any GRAPH job → Recurrente (precedence graph: assembly, branching).
///  3. every job a single task: one station → Single Machine / Parallel
///     Machines; several stations → Open Shop (each job is one operation).
///  4. every job a chain (single tasks count as chains of one): the same
///     station sequence for all and no station visited twice → Flow Shop;
///     otherwise Job Shop (which also covers re-entrant routes, A → B → A).
String classifyOrderEnvironment(
  List<JobRoute> routes,
  Map<int, int> machineCountByType,
) {
  if (routes.isEmpty) {
    throw ArgumentError('La orden no tiene trabajos.');
  }

  final stations = {
    for (final r in routes)
      for (final t in r.tasks) t.machineTypeId,
  };
  for (final s in stations) {
    if ((machineCountByType[s] ?? 0) <= 0) {
      throw StationWithoutMachinesException(s);
    }
  }
  final bool flexible = stations.any((s) => machineCountByType[s]! > 1);
  String pick(String classic, String flex) => flexible ? flex : classic;

  final shapes = routes.map(routeShape).toList();

  if (shapes.contains(RouteShape.free)) {
    return pick(kOpenShop, kFlexibleOpenShop);
  }
  if (shapes.contains(RouteShape.graph)) {
    return pick(kRecurrente, kFlexibleRecurrente);
  }
  if (shapes.every((s) => s == RouteShape.single)) {
    return stations.length == 1
        ? pick(kSingleMachine, kParallelMachines)
        : pick(kOpenShop, kFlexibleOpenShop);
  }

  // Every job is a chain. Compare the station sequences in arrow order.
  List<int> stationsInOrder(JobRoute r) {
    final typeOf = {for (final t in r.tasks) t.taskId: t.machineTypeId};
    return [for (final id in topologicalTaskOrder(r)) typeOf[id]!];
  }

  final first = stationsInOrder(routes.first);
  bool sameRoute(List<int> other) {
    if (other.length != first.length) return false;
    for (int i = 0; i < first.length; i++) {
      if (other[i] != first[i]) return false;
    }
    return true;
  }

  final bool reentrant = first.toSet().length != first.length;
  final bool allSame =
      routes.skip(1).every((r) => sameRoute(stationsInOrder(r)));
  if (allSame && !reentrant) {
    return pick(kFlowShop, kFlexibleFlowShop);
  }
  return pick(kJobShop, kFlexibleJobShop);
}
