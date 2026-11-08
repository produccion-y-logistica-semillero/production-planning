// lib/services/scheduling/machine_sequence_plan.dart
//
// A schedule fixed by the user as machine sequences (and, where the route is
// a decision, as the route of each job).
//
//   Route    [DECISION]  J1: M1, M2        (machine visited at each operation)
//   Sequence [DECISION]  M1: J1, J2, J3    (order each machine processes jobs)
//
// A machine sequence is a list of JOBS: the k-th time a job appears in a
// machine's list is the k-th operation of that job on that machine (a job can
// repeat a machine: recirculation). This file turns the two tables into
//   * the operation each list position stands for (queues),
//   * the machine of every operation (machineOf), and
//   * for jobs with a user route, the order of their operations (visitOrder),
// and refuses plans that cannot be executed: wrong counts, unknown machines,
// or a deadlock (a cycle between the job's own order and the machine queues).
//
// Pure functions, no I/O: the dialog validates with the same code the
// schedulers run, so what the dialog accepts is what gets scheduled.
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_entity.dart';

/// What the user typed: machine -> job ids in processing order, and, for
/// environments where the route is a decision, job id -> machine ids visited
/// in order (one entry per operation).
class MachinePlan {
  final Map<int, List<int>> machineSequences;
  final Map<int, List<int>>? routes;
  const MachinePlan({required this.machineSequences, this.routes});
}

/// One operation as the plan builder sees it.
class SeqOperation {
  final int jobId;
  final int taskId;

  /// Position of the task in the job's route as stored (0-based).
  final int index;

  /// Machines the operation can run on.
  final Set<int> machines;

  /// Tasks of the same job that must finish before this one starts.
  final Set<int> predecessors;

  const SeqOperation({
    required this.jobId,
    required this.taskId,
    required this.index,
    required this.machines,
    required this.predecessors,
  });
}

class MachineSequenceException implements Exception {
  final String message;

  /// (jobId, taskId) of the operations involved, when there are some (a
  /// deadlock lists the ones that wait for each other).
  final List<(int, int)> involved;
  const MachineSequenceException(this.message, [this.involved = const []]);

  @override
  String toString() => message;
}

class MachineSequencePlan {
  /// machineId -> operations in the order the machine must process them.
  final Map<int, List<(int, int)>> queues;

  /// (jobId, taskId) -> machine.
  final Map<(int, int), int> machineOf;

  /// jobId -> taskIds in the order the user's route visits them. Only for
  /// jobs that came with a user route.
  final Map<int, List<int>> visitOrder;

  const MachineSequencePlan({
    required this.queues,
    required this.machineOf,
    required this.visitOrder,
  });
}

/// Operations of [jobs] for the plan builder and the dialog.
///
/// [chainWhenNoDependencies]: a job whose route has no arrows follows the
/// order its tasks are stored in (job shop, flow shop) — false for open
/// shop, where such a job has no order.
List<SeqOperation> seqOperationsFromJobs(
  List<JobEntity> jobs,
  Map<int, List<MachineEntity>> machinesByType, {
  required bool chainWhenNoDependencies,
}) {
  final out = <SeqOperation>[];
  for (final job in jobs) {
    final tasks = job.sequence?.tasks ?? const [];
    final deps = job.sequence?.dependencies ?? const [];
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final Set<int> preds;
      if (deps.isEmpty) {
        preds = (chainWhenNoDependencies && i > 0) ? {tasks[i - 1].id!} : {};
      } else {
        preds = {
          for (final d in deps)
            if (d.successor_id == task.id) d.predecessor_id,
        };
      }
      out.add(SeqOperation(
        jobId: job.jobId!,
        taskId: task.id!,
        index: i,
        machines: {
          for (final m in machinesByType[task.machineTypeId] ?? const [])
            m.id!,
        },
        predecessors: preds,
      ));
    }
  }
  return out;
}

/// Builds the plan or throws a [MachineSequenceException] saying what is
/// wrong with it.
MachineSequencePlan buildMachineSequencePlan({
  required List<SeqOperation> ops,
  required Map<int, List<int>> machineSequences,
  Map<int, List<int>>? userRoutes,
}) {
  final byJob = <int, List<SeqOperation>>{};
  for (final o in ops) {
    byJob.putIfAbsent(o.jobId, () => []).add(o);
  }
  for (final l in byJob.values) {
    l.sort((a, b) => a.index.compareTo(b.index));
  }
  final knownMachines = {for (final o in ops) ...o.machines};

  // How many times each job appears on each machine.
  final slots = <int, Map<int, int>>{};
  machineSequences.forEach((machine, jobs) {
    if (!knownMachines.contains(machine)) {
      throw MachineSequenceException('La máquina $machine no existe en el '
          'programa.');
    }
    for (final j in jobs) {
      if (!byJob.containsKey(j)) {
        throw MachineSequenceException('El job $j de la secuencia de la '
            'máquina $machine no pertenece al programa.');
      }
      final perMachine = slots.putIfAbsent(j, () => {});
      perMachine[machine] = (perMachine[machine] ?? 0) + 1;
    }
  });

  final machineOf = <(int, int), int>{};
  final visitOrder = <int, List<int>>{};

  for (final entry in byJob.entries) {
    final job = entry.key;
    final tasks = entry.value;
    final remaining = Map<int, int>.of(slots[job] ?? const {});
    final total = remaining.values.fold<int>(0, (a, b) => a + b);
    if (total != tasks.length) {
      throw MachineSequenceException('El job $job aparece $total veces en las '
          'secuencias de las máquinas pero tiene ${tasks.length} '
          'operaciones: debe aparecer una vez por operación.');
    }

    final route = userRoutes?[job];
    if (route != null) {
      if (route.length != tasks.length) {
        throw MachineSequenceException('La ruta del job $job tiene '
            '${route.length} operaciones y el job tiene ${tasks.length}.');
      }
      final visits = <int, int>{};
      for (final m in route) {
        visits[m] = (visits[m] ?? 0) + 1;
      }
      for (final m in {...visits.keys, ...remaining.keys}) {
        if ((visits[m] ?? 0) != (remaining[m] ?? 0)) {
          throw MachineSequenceException('La ruta del job $job pasa '
              '${visits[m] ?? 0} veces por la máquina $m pero las '
              'secuencias lo ponen ${remaining[m] ?? 0} veces.');
        }
      }
      final order = _matchVisits(tasks, route);
      if (order == null) {
        throw MachineSequenceException('La ruta del job $job visita '
            'máquinas donde sus operaciones no pueden correr.');
      }
      visitOrder[job] = [for (final t in order) t.taskId];
      for (int k = 0; k < order.length; k++) {
        machineOf[(job, order[k].taskId)] = route[k];
      }
    } else {
      final assigned = _assignTasks(tasks, remaining);
      if (assigned == null) {
        throw MachineSequenceException('Las máquinas del job $job no '
            'coinciden con las que necesitan sus operaciones.');
      }
      for (int i = 0; i < tasks.length; i++) {
        machineOf[(job, tasks[i].taskId)] = assigned[i];
      }
    }
  }

  // The k-th appearance of a job on a machine is that job's k-th operation
  // there: by the order the user's route visits them, else by stored order.
  int positionOf(int job, int taskId, int storedIndex) {
    final v = visitOrder[job];
    return v == null ? storedIndex : v.indexOf(taskId);
  }

  final queues = <int, List<(int, int)>>{};
  machineSequences.forEach((machine, jobs) {
    final seen = <int, int>{};
    final queue = <(int, int)>[];
    for (final j in jobs) {
      final k = seen[j] = (seen[j] ?? 0) + 1;
      final onMachine = [
        for (final o in byJob[j]!)
          if (machineOf[(j, o.taskId)] == machine) o,
      ]..sort((a, b) => positionOf(j, a.taskId, a.index)
          .compareTo(positionOf(j, b.taskId, b.index)));
      queue.add((j, onMachine[k - 1].taskId));
    }
    queues[machine] = queue;
  });

  final plan = MachineSequencePlan(
    queues: queues,
    machineOf: machineOf,
    visitOrder: visitOrder,
  );
  _rejectDeadlock(ops, plan);
  return plan;
}

/// Visits (machines in route order) -> the task each one stands for, in visit
/// order; null if no assignment exists. Tasks are tried in stored order so a
/// repeated machine keeps the stored order.
List<SeqOperation>? _matchVisits(List<SeqOperation> tasks, List<int> route) {
  final used = List<bool>.filled(tasks.length, false);
  final picked = <SeqOperation>[];
  bool go(int k) {
    if (k == route.length) return true;
    for (int i = 0; i < tasks.length; i++) {
      if (used[i] || !tasks[i].machines.contains(route[k])) continue;
      used[i] = true;
      picked.add(tasks[i]);
      if (go(k + 1)) return true;
      picked.removeLast();
      used[i] = false;
    }
    return false;
  }

  return go(0) ? picked : null;
}

/// Machine of each task (in stored order) so that every machine is used
/// exactly as many times as the job appears on it; null if impossible.
List<int>? _assignTasks(List<SeqOperation> tasks, Map<int, int> remaining) {
  final left = Map<int, int>.of(remaining);
  final result = <int>[];
  bool go(int i) {
    if (i == tasks.length) return true;
    final candidates = tasks[i].machines.toList()..sort();
    for (final m in candidates) {
      if ((left[m] ?? 0) <= 0) continue;
      left[m] = left[m]! - 1;
      result.add(m);
      if (go(i + 1)) return true;
      result.removeLast();
      left[m] = left[m]! + 1;
    }
    return false;
  }

  return go(0) ? result : null;
}

/// Throws if the job-order arcs plus the machine-queue arcs contain a cycle:
/// each operation in the cycle waits for another one that waits for it.
void _rejectDeadlock(List<SeqOperation> ops, MachineSequencePlan plan) {
  final succ = <(int, int), List<(int, int)>>{};
  final indeg = <(int, int), int>{};
  for (final o in ops) {
    indeg[(o.jobId, o.taskId)] = 0;
  }
  void arc((int, int) from, (int, int) to) {
    if (!indeg.containsKey(from) || !indeg.containsKey(to)) return;
    succ.putIfAbsent(from, () => []).add(to);
    indeg[to] = indeg[to]! + 1;
  }

  for (final o in ops) {
    for (final p in o.predecessors) {
      arc((o.jobId, p), (o.jobId, o.taskId));
    }
  }
  plan.visitOrder.forEach((job, order) {
    for (int k = 0; k + 1 < order.length; k++) {
      arc((job, order[k]), (job, order[k + 1]));
    }
  });
  for (final queue in plan.queues.values) {
    for (int k = 0; k + 1 < queue.length; k++) {
      arc(queue[k], queue[k + 1]);
    }
  }

  final ready = [
    for (final e in indeg.entries)
      if (e.value == 0) e.key,
  ];
  int visited = 0;
  while (ready.isNotEmpty) {
    final n = ready.removeLast();
    visited++;
    for (final s in succ[n] ?? const <(int, int)>[]) {
      indeg[s] = indeg[s]! - 1;
      if (indeg[s] == 0) ready.add(s);
    }
  }
  if (visited != indeg.length) {
    final stuck = [
      for (final e in indeg.entries)
        if (e.value > 0) e.key,
    ];
    throw MachineSequenceException(
        'Interbloqueo: con estas secuencias y rutas hay operaciones que se '
        'esperan unas a otras y ninguna puede empezar. Cambie el orden de '
        'alguna máquina.',
        stuck);
  }
}
