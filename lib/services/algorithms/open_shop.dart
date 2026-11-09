import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/tabu_objective.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/genetic_engine.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/services/scheduling/schedule_objective_value.dart';
import 'package:production_planning/services/scheduling/machine_sequence_plan.dart';
import 'package:production_planning/services/scheduling/user_sequence.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class OpenShopInput {
  final int jobId;
  final int dbJobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // Lista de operaciones sin orden específico: <taskId, Map<machineId, Duration>>
  final List<Tuple2<int, Map<int, Duration>>> operations;
  final List<TaskDependencyEntity> dependencies;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  OpenShopInput(
    this.jobId,
    this.dbJobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.operations, {
    this.dependencies = const [],
    this.interruptibleByTask = const {},
  });

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class OpenShopOutput {
  final int jobId;
  final int dbJobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  // Scheduling: taskId -> (machineId, Range)
  final Map<int, Tuple2<int, Range>> scheduling;

  /// Processing segments per task (taskId → segments), for tasks that were
  /// preempted mid-processing.
  final Map<int, List<ProcessingSegment>> segmentsByTask;

  /// Setup/changeover segments per task (taskId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByTask;

  OpenShopOutput(
    this.jobId,
    this.dbJobId,
    this.dueDate,
    this.startDate,
    this.endTime,
    this.scheduling, {
    Map<int, List<ProcessingSegment>>? segmentsByTask,
    this.setupSegmentsByTask = const {},
  }) : segmentsByTask = segmentsByTask ??
            scheduling.map((taskId, entry) => MapEntry(taskId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

/// Costo de un horario para la regla TABU: el valor del objetivo elegido y
/// el flujo total, que rompe los empates. Misma comparación que
/// _FlexibleJobTabuCost en flexible_job_shop.dart (allí es privada de esa
/// librería).
class _OpenShopTabuCost {
  /// Valor del objetivo elegido (minutos, o trabajos para Σ Uj).
  final int value;

  /// Flujo total Σ (Cj − rj) en minutos. Rompe los empates de [value].
  final int flow;

  const _OpenShopTabuCost(this.value, this.flow);

  int compareTo(_OpenShopTabuCost other) => value != other.value
      ? value.compareTo(other.value)
      : flow.compareTo(other.flow);

  bool operator <(_OpenShopTabuCost other) => compareTo(other) < 0;
}

/// Una operación del open shop: la tarea [taskId] del job [job]. Es la
/// unidad que mueve el TABU. A diferencia de FJSP no tiene posición en una
/// ruta: en un job libre, su lugar en la ruta lo decide su posición en π.
class _OpenShopOp {
  final OpenShopInput job;

  /// Posición del job en inputJobs.
  final int jobIndex;
  final int taskId;

  /// Máquinas elegibles (las de la estación que pide la tarea) y su tiempo.
  final Map<int, Duration> durations;

  /// Clave estable para los atributos tabú: jobId.taskId.
  final String key;

  _OpenShopOp({
    required this.job,
    required this.jobIndex,
    required this.taskId,
    required this.durations,
  }) : key = '${job.jobId}.$taskId';
}

/// Estado de las máquinas durante un _decode: lo mismo que el lazo de
/// _schedule guarda en machinesAvailability, _machineLastJob y
/// _machineContinuousUsage, pero local, para evaluar vecinos sin tocar la
/// clase. Un checkpoint es una copia de este estado.
class _OpenShopDecodeState {
  final Map<int, DateTime> machineFree;

  /// dbJobId del último job con estado (A-J) en la máquina, como
  /// _machineLastJob: de él parte el setup siguiente.
  final Map<int, int?> lastJob;
  final Map<int, Duration> usage;

  _OpenShopDecodeState(this.machineFree, this.lastJob, this.usage);

  _OpenShopDecodeState.initial(Map<int, DateTime> initialAvailability)
      : machineFree = Map<int, DateTime>.from(initialAvailability),
        lastJob = {},
        usage = {};

  _OpenShopDecodeState copy() => _OpenShopDecodeState(
        Map<int, DateTime>.from(machineFree),
        Map<int, int?>.from(lastJob),
        Map<int, Duration>.from(usage),
      );
}

/// Una operación ya decodificada en su máquina, con los datos con que se
/// precio (inicio ajustado, último job de la máquina y racha de uso): si un
/// decode posterior llega a la misma operación con los mismos datos, el
/// resultado es el mismo y se reutiliza sin volver al PreemptionEngine.
typedef _OpenShopPlacedOp = ({
  int machineId,
  DateTime start,
  int? previousJob,
  Duration priorUsage,
  List<ProcessingSegment> setupSegments,
  SegmentedSchedule schedule,
  Duration usageAfter,
});

/// Una solución del TABU Open Shop: (MA, π), sus checkpoints y lo que dejó
/// el decode.
///
/// - [pi]: todas las operaciones (por opId). El orden de una máquina es el
///   orden en que aparecen sus operaciones en π, y la ruta de un job libre
///   también. Los jobs con dependencies respetan su grafo.
/// - [ma]: opId → máquina asignada, dentro de las de su estación.
/// - [checkpoints][k]: estado de las máquinas justo antes de π[k]; sirve
///   para cualquier vecino que comparta π[0..k−1] y sus máquinas.
class _OpenShopTabuSolution {
  List<int> pi;
  List<int> ma;
  final List<_OpenShopDecodeState> checkpoints;
  final List<_OpenShopPlacedOp?> placed;
  _OpenShopDecodeState finalState;
  List<OpenShopOutput> schedule;
  _OpenShopTabuCost cost;

  _OpenShopTabuSolution.empty(int opCount)
      : pi = [],
        ma = [],
        checkpoints = [],
        placed = List<_OpenShopPlacedOp?>.filled(opCount, null),
        finalState = _OpenShopDecodeState({}, {}, {}),
        schedule = [],
        cost = const _OpenShopTabuCost(0, 0);

  _OpenShopTabuSolution._(this.pi, this.ma, this.checkpoints, this.placed,
      this.finalState, this.schedule, this.cost);

  /// Copia de las listas; los checkpoints guardados, las operaciones
  /// decodificadas y las salidas no se modifican después de crearse.
  _OpenShopTabuSolution copy() => _OpenShopTabuSolution._(
        List<int>.from(pi),
        List<int>.from(ma),
        List<_OpenShopDecodeState>.from(checkpoints),
        List<_OpenShopPlacedOp?>.from(placed),
        finalState,
        List<OpenShopOutput>.from(schedule),
        cost,
      );
}

/// Lo que no cambia durante una corrida del TABU Open Shop.
class _OpenShopTabuContext {
  final TabuObjective objective;
  final Map<int, DateTime> initialAvailability;
  final Map<int, DateTime> releaseByJob;

  /// Todas las operaciones; su índice es el opId.
  final List<_OpenShopOp> ops;

  /// opIds de cada job (por jobIndex), en el orden de job.operations.
  final List<List<int>> opsByJob;

  /// Por jobIndex: true si el job no tiene dependencies — open shop real:
  /// cualquier orden de sus operaciones, una máquina a la vez.
  final List<bool> freeJob;

  /// Precedencias directas por opId, solo de los jobs con dependencies (su
  /// DAG, mismo criterio que isTaskReady en _schedule). Las operaciones de
  /// un job libre no tienen ninguna.
  final List<List<int>> predecessors;
  final List<List<int>> successors;

  const _OpenShopTabuContext({
    required this.objective,
    required this.initialAvailability,
    required this.releaseByJob,
    required this.ops,
    required this.opsByJob,
    required this.freeJob,
    required this.predecessors,
    required this.successors,
  });
}

/// Mejor vecino de una rama: el (MA, π) resultante, desde dónde cambia y su
/// atributo tabú.
class _OpenShopTabuMove {
  final bool isIntra;
  final List<int> pi;
  final List<int> ma;

  /// i_min: primera posición de π que cambia.
  final int from;

  /// intra:(u,v) o inter:u:Ma_Mb.
  final String attribute;
  final _OpenShopTabuCost cost;

  const _OpenShopTabuMove({
    required this.isIntra,
    required this.pi,
    required this.ma,
    required this.from,
    required this.attribute,
    required this.cost,
  });
}

class OpenShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<OpenShopInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  Map<int, List<MachineInactivityEntity>> machineInactivities;
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count.
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  PreemptionEngine _engineFor(int machineId) {
    return _engineByMachine.putIfAbsent(machineId, () {
      final capacityMinutes = machineContinueCapacity[machineId] ?? 0;
      return PreemptionEngine(
        workingSchedule: workingSchedule,
        maintenanceWindows: machineInactivities[machineId] ?? const [],
        continuousUseCap: capacityMinutes > 0
            ? Duration(minutes: capacityMinutes)
            : Duration.zero,
        restDuration: machineRestTime[machineId] ?? Duration.zero,
      );
    });
  }

  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job. Used only when a machine has no prior job yet;
  /// once one has run, its own left-behind state takes over.
  final Map<int, String> initialMachineState;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};
  List<OpenShopOutput> output = [];

  /// Settings and objective of GENETICS, chosen in the algorithm picker.
  final GeneticParams geneticParams;

  /// Job ids in the order the user chose (rule SECUENCIA_USUARIO).
  final List<int>? userSequence;

  /// machineId -> job ids in the order that machine processes them (rule
  /// SECUENCIA_USUARIO, strict). When set it replaces [userSequence].
  final Map<int, List<int>>? machineSequences;

  /// jobId -> machine ids the job visits, in order (one per operation): the
  /// route is part of the user's solution in an open shop.
  final Map<int, List<int>>? userRoutes;
  /// Parámetros del TABU, desde la interfaz (TabuParamsDialog).
  final TabuParams tabuParams;

  /// Estadísticas de la última corrida TABU; null con cualquier otra regla.
  TabuRunStats? tabuStats;

  OpenShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
    this.stateSetupMatrix,
    this.jobStates,
    this.initialMachineState = const {},
    this.geneticParams = const GeneticParams(),
    this.userSequence,
    this.machineSequences,
    this.userRoutes,
    this.tabuParams = const TabuParams(),
  }) {
    _initializeMachineLastSequence();
    final r = rule.toUpperCase();
    print('OpenShop: starting scheduling rule=$r for ${inputJobs.length} jobs');
    switch (r) {
      case "FIFO":
        scheduleOpenShopFIFO();
        break;
      case "SPT":
        scheduleOpenShopSPT();
        break;
      case "LPT":
        scheduleOpenShopLPT();
        break;
      case "EDD":
        scheduleOpenShopEDD();
        break;
      case "WSPT":
        scheduleOpenShopWSPT();
        break;
      // The database grants MINSLACK (rule id 11) to Open Shop and Flexible
      // Open Shop, but only "MS" was handled — so picking Minimum Slack fell
      // through to `default:` and silently ran SPT instead. Same rule, two
      // names across environments.
      case "MINSLACK":
      case "MS":
        scheduleOpenShopMS();
        break;
      case "MWR":
        scheduleOpenShopMWR();
        break;
      case "LWR":
        scheduleOpenShopLWR();
        break;
      case "CR":
        scheduleOpenShopCR();
        break;
      case "ATCS":
        scheduleOpenShopATCS();
        break;
      // Composite priority score (1/CR + w/p). It used to be offered as
      // "GENETICS", but it is a dispatching index, not a genetic algorithm.
      case "PRIORIDAD_COMPUESTA":
        _schedule((a, b) {
          final crA = _calculateCR(a.job as OpenShopInput,
              a.duration as Duration, a.earliestStart as DateTime);
          final crB = _calculateCR(b.job as OpenShopInput,
              b.duration as Duration, b.earliestStart as DateTime);
          final durationMinutesA = (a.duration as Duration).inMinutes;
          final durationMinutesB = (b.duration as Duration).inMinutes;
          final wsptA = a.job.priority / max(1, durationMinutesA);
          final wsptB = b.job.priority / max(1, durationMinutesB);
          final scoreA = (1 / max(crA, 0.0001)) + wsptA;
          final scoreB = (1 / max(crB, 0.0001)) + wsptB;
          final cmp = scoreB.compareTo(scoreA);
          if (cmp != 0) return cmp;
          // List.sort is not stable: settle ties so runs agree.
          final byJob = (a.job.jobId as int).compareTo(b.job.jobId as int);
          if (byJob != 0) return byJob;
          return (a.taskId as int).compareTo(b.taskId as int);
        });
        break;
      case "GENETICS":
        scheduleOpenShopGenetic(settings: geneticParams);
        break;
      // The user's job order as a priority list: among the operations that
      // can start first, the job earlier in the list goes first.
      case "SECUENCIA_USUARIO":
        if (machineSequences != null) {
          scheduleOpenShopMachineSequence();
          break;
        }
        final rank = userSequenceRank(userSequence);
        _schedule((a, b) {
          final cmp = compareByUserSequence(
            rank,
            a.job.jobId as int,
            b.job.jobId as int,
            a.job.availableDate as DateTime,
            b.job.availableDate as DateTime,
          );
          if (cmp != 0) return cmp;
          return (a.taskId as int).compareTo(b.taskId as int);
        });
        break;
      case "TABU":
        tabuSearchRule(params: tabuParams);
        break;
      default:
        scheduleOpenShopSPT();
    }
    print('OpenShop: constructor finished (scheduling started/completed)');
  }

  /// Strict per-machine sequences (and, optionally, the route of each job).
  ///
  /// Each machine processes its jobs exactly in the order the user typed and
  /// each operation runs on the machine whose list it is in. A job with a
  /// user route visits its operations in that order (the route becomes a
  /// chain of precedences); a job without one keeps the freedom of an open
  /// shop job, so its order comes out of the machine sequences. A plan that
  /// cannot run (wrong counts, deadlock) throws a [MachineSequenceException].
  void scheduleOpenShopMachineSequence() {
    final plan = buildMachineSequencePlan(
      ops: [
        for (final job in inputJobs)
          for (int i = 0; i < job.operations.length; i++)
            SeqOperation(
              jobId: job.jobId,
              taskId: job.operations[i].value1,
              index: i,
              machines: job.operations[i].value2.keys.toSet(),
              predecessors: {
                for (final d in job.dependencies)
                  if (d.successor_id == job.operations[i].value1)
                    d.predecessor_id,
              },
            ),
      ],
      machineSequences: machineSequences!,
      userRoutes: userRoutes,
    );

    // The user's route is an order the job must follow: add it as arrows.
    if (plan.visitOrder.isNotEmpty) {
      inputJobs = [
        for (final job in inputJobs)
          if (plan.visitOrder[job.jobId] case final order?)
            OpenShopInput(
              job.jobId,
              job.dbJobId,
              job.sequenceId,
              job.dueDate,
              job.priority,
              job.availableDate,
              job.operations,
              dependencies: [
                ...job.dependencies,
                for (int k = 0; k + 1 < order.length; k++)
                  TaskDependencyEntity(
                    predecessor_id: order[k],
                    successor_id: order[k + 1],
                    sequenceId: job.sequenceId,
                  ),
              ],
              interruptibleByTask: job.interruptibleByTask,
            )
          else
            job,
      ];
    }

    _schedule(
      (a, b) {
        final cmp = (a.job.jobId as int).compareTo(b.job.jobId as int);
        return cmp != 0 ? cmp : (a.taskId as int).compareTo(b.taskId as int);
      },
      forcedMachine: plan.machineOf,
      machineQueues: plan.queues,
    );
  }

  /// Genetic algorithm with an operation-based chromosome (Prins, 2000;
  /// Bierwirth, 1995) plus a machine-assignment vector for Flexible Open
  /// Shop. Each chromosome is decoded with the same non-delay loop the rules
  /// use: among the operations that can start at t*, the one earlier in the
  /// chromosome goes first, on the machine its gene assigns. Fitness: the
  /// objective chosen in [settings] (makespan by default). See
  /// docs/diagnostico_genetics.md.
  void scheduleOpenShopGenetic({
    GeneticParams settings = const GeneticParams(),
  }) {
    final ops = <({OpenShopInput job, int taskId, List<int> machines})>[
      for (final job in inputJobs)
        for (final op in job.operations)
          (
            job: job,
            taskId: op.value1,
            machines: op.value2.keys.toList()..sort(),
          ),
    ];
    if (ops.isEmpty) return;
    final jobOf = [for (final op in ops) op.job.jobId];
    final machineCount = [for (final op in ops) op.machines.length];

    final availability0 = Map<int, DateTime>.of(machinesAvailability);
    final usage0 = Map<int, Duration>.of(_machineContinuousUsage);
    final lastJob0 = Map<int, int?>.of(_machineLastJob);
    final lastSequence0 = Map<int, int?>.of(_machineLastSequence);

    void decode(OperationChromosome c, {bool quiet = true}) {
      machinesAvailability
        ..clear()
        ..addAll(availability0);
      _machineContinuousUsage
        ..clear()
        ..addAll(usage0);
      _machineLastJob
        ..clear()
        ..addAll(lastJob0);
      _machineLastSequence
        ..clear()
        ..addAll(lastSequence0);
      output = [];
      final position = <(int, int), int>{};
      for (int i = 0; i < c.order.length; i++) {
        final op = ops[c.order[i]];
        position[(op.job.jobId, op.taskId)] = i;
      }
      final forced = <(int, int), int>{
        for (int i = 0; i < ops.length; i++)
          (ops[i].job.jobId, ops[i].taskId): ops[i].machines[c.machineChoice[i]],
      };
      _schedule(
        (a, b) => position[(a.job.jobId as int, a.taskId as int)]!
            .compareTo(position[(b.job.jobId as int, b.taskId as int)]!),
        forcedMachine: forced,
        quiet: quiet,
      );
    }

    double fitness(OperationChromosome c) {
      try {
        decode(c);
      } on SchedulingHorizonException {
        return double.infinity;
      }
      final done = output.fold<int>(0, (n, o) => n + o.scheduling.length);
      if (done < ops.length || output.isEmpty) return double.infinity;
      final end = completionByJob<OpenShopOutput>(
          output, (o) => o.jobId, (o) => o.endTime);
      return scheduleObjectiveValue(
        settings.objective,
        [
          for (final j in inputJobs)
            if (end[j.jobId] != null)
              JobCompletion(j.availableDate, j.dueDate, end[j.jobId]!),
        ],
        startDate,
      );
    }

    // Seed: operations in the order they were registered, each on its
    // fastest machine.
    final seed = OperationChromosome(
      List<int>.generate(ops.length, (i) => i),
      [
        for (final op in ops)
          () {
            final durations =
                op.job.operations.firstWhere((o) => o.value1 == op.taskId).value2;
            int best = 0;
            for (int k = 1; k < op.machines.length; k++) {
              if (durations[op.machines[k]]! < durations[op.machines[best]]!) {
                best = k;
              }
            }
            return best;
          }(),
      ],
    );

    final result = runGenetic<OperationChromosome>(
      seeds: [seed],
      randomIndividual: (r) => randomOperationChromosome(machineCount, r),
      fitness: fitness,
      crossover: (a, b, r) => poxCrossover(a, b, jobOf, r),
      mutate: (c, r) => operationMutation(c, machineCount, r),
      key: (c) => c.key,
      settings: settings,
    );
    decode(result.best, quiet: false);
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
  }

  DateTime _adjustForWorkingSchedule(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final currentMinutes = hour * 60 + minute;
    final startMinutes =
        workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;
    final endMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (currentMinutes < startMinutes) {
      return DateTime(
        dt.year,
        dt.month,
        dt.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    } else if (currentMinutes >= endMinutes) {
      final nextDay = dt.add(const Duration(days: 1));
      return DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    }
    return dt;
  }

  // ── Static rules ──────────────────────────────────────────────────────────
  //
  // Applied among the operations that can start (see _schedule), with the
  // operation's NOMINAL attributes as the index: its processing time on the
  // machine chosen for it, the job's due date, or when the operation joined
  // the queue. They used to build the conflict set on the nominal start and
  // let the job rule pick the machine too — LPT sent the operation to its
  // slowest machine. WSPT also divided by the raw minutes, so a zero-minute
  // operation divided by zero.

  void scheduleOpenShopFIFO() => _scheduleBy(DispatchCriterion.fifoArrival);

  void scheduleOpenShopSPT() => _scheduleBy(DispatchCriterion.sptNominal);

  void scheduleOpenShopLPT() => _scheduleBy(DispatchCriterion.lptNominal);

  void scheduleOpenShopEDD() => _scheduleBy(DispatchCriterion.edd);

  void scheduleOpenShopWSPT() => _scheduleBy(DispatchCriterion.wsptNominal);

  void scheduleOpenShopMS() => _scheduleBy(DispatchCriterion.ms);

  // LWR / MWR: nominal work the job still has — this operation plus every
  // operation not yet done (see _remainingWorkAfter). MWR is the classic
  // open-shop heuristic: start first the job with the most work left, so it
  // does not end up last on every machine. The previous MWR counted every
  // other operation of the job, including the ones already done.

  void scheduleOpenShopLWR() => _scheduleBy(DispatchCriterion.lwr);

  void scheduleOpenShopMWR() => _scheduleBy(DispatchCriterion.mwr);

  void scheduleOpenShopCR() => _scheduleBy(DispatchCriterion.cr);

  void scheduleOpenShopATCS() => _scheduleBy(DispatchCriterion.atcs);

  /// Critical ratio used only by the PRIORIDAD_COMPUESTA score, at [now] — the
  /// schedule's clock, never the wall clock.
  double _calculateCR(OpenShopInput job, Duration duration, DateTime now) {
    final cr =
        job.dueDate.difference(now).inMinutes / max(duration.inMinutes, 1);
    return cr < 0 ? 0 : cr;
  }

  // ── Dynamic literature rules (MS, CR, ATCS) ───────────────────────────────
  //
  // The literature defines all three in terms of the clock t. They used to
  // read DateTime.now() — the wall clock when the button was pressed — so
  // the same order could schedule differently from one minute to the next,
  // and against any plan dated in the past every job looked late and tied
  // at zero. They also charged the operation's NOMINAL duration, blind to
  // changeovers and interruptions.
  //
  // Now each contending operation is priced through the preemption engine
  // from the schedule's own clock — the instant it can start, which is the
  // decision point of this non-delay loop — and compared with the shared
  // criteria in dynamic_dispatch.dart. The job's other pending operations
  // are charged against its due date as nominal work still to do.

  /// Runs the non-delay loop with one of the shared criteria — static,
  /// LWR/MWR or dynamic; they differ only in the index they read.
  void _scheduleBy(DispatchCriterion criterion) {
    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParameters() : null;
    _schedule(
      (a, b) {
        final int cmp = compareCandidates<OpenShopInput>(
          criterion,
          a.dispatch as DispatchCandidate<OpenShopInput>,
          b.dispatch as DispatchCandidate<OpenShopInput>,
          // The loop only consults the rule among candidates whose
          // EFFECTIVE start coincides, so that is the shared decision time.
          decisionTime:
              (a.dispatch as DispatchCandidate<OpenShopInput>).start,
          atcs: atcs,
        );
        if (cmp != 0) return cmp;
        // Operations of one job share its jobId, the last tie-break
        // compareCandidates has; settle those too, since List.sort is not
        // stable and two runs could otherwise disagree.
        final int byTask = (a.taskId as int).compareTo(b.taskId as int);
        if (byTask != 0) return byTask;
        return (a.machineId as int).compareTo(b.machineId as int);
      },
    );
  }

  /// Prices one operation of [job] on [machineId] from [at] as a
  /// [DispatchCandidate], without committing anything.
  DispatchCandidate<OpenShopInput> _dispatchCandidate(
    OpenShopInput job,
    int taskId,
    int machineId,
    Duration duration,
    DateTime at,
    Set<int> completed,
    DateTime arrival,
  ) {
    final placed = _priceOperation(
      job: job,
      taskId: taskId,
      machineId: machineId,
      duration: duration,
      start: at,
    );
    final DateTime end = placed.schedule.completionTime;
    // Effective start: after every interruption the engine had to work
    // around (maintenance, rest cap, waiting for a window that fits a
    // non-interruptible block) — not just the shift-adjusted [at]. The
    // non-delay loop ranks on it, and the span is measured from it.
    final DateTime start = placed.setupSegments.isNotEmpty
        ? placed.setupSegments.first.start
        : placed.schedule.startDate;
    final Duration span = end.difference(start);
    return DispatchCandidate(
      job: job,
      start: start,
      end: end,
      span: span.isNegative ? Duration.zero : span,
      dueDate: job.dueDate,
      releaseDate: job.availableDate,
      priority: job.priority,
      jobId: job.jobId,
      setup: segmentsDuration(placed.setupSegments),
      remainingWork: _remainingWorkAfter(job, taskId, completed),
      processing: duration,
      arrival: arrival,
    );
  }

  /// Nominal work [job] still has after [taskId]: every other operation not
  /// yet completed, each at its mean duration over the machines that can run
  /// it.
  Duration _remainingWorkAfter(
      OpenShopInput job, int taskId, Set<int> completed) {
    Duration total = Duration.zero;
    for (final operation in job.operations) {
      if (operation.value1 == taskId || completed.contains(operation.value1)) {
        continue;
      }
      if (operation.value2.isEmpty) continue;
      total +=
          operation.value2.values.fold(Duration.zero, (sum, d) => sum + d) ~/
              operation.value2.length;
    }
    return total;
  }

  /// Changeover [machineId] needs before [job], out of the state the last
  /// job it ran left it in — or, if nothing has run on it yet, the
  /// machine's configured initial state for this order. Reads machine
  /// state only.
  Duration _setupFor(int machineId, OpenShopInput job) {
    if (stateSetupMatrix == null || jobStates == null) return Duration.zero;
    final int? previousJobId = _machineLastJob[machineId];
    String? previousState;
    if (previousJobId != null && previousJobId > 0) {
      previousState = jobStates![previousJobId]?[machineId];
    } else {
      previousState = initialMachineState[machineId];
    }
    if (previousState == null) return Duration.zero;
    final machineStates = stateSetupMatrix![machineId];
    if (machineStates == null) return Duration.zero;
    final currentState = jobStates![job.dbJobId]?[machineId];
    if (currentState == null) return Duration.zero;
    final setupMinutes = machineStates[previousState]?[currentState];
    return setupMinutes != null
        ? Duration(minutes: setupMinutes)
        : Duration.zero;
  }

  /// Schedules one operation — setup out of the machine's current state,
  /// then processing — through the preemption engine, WITHOUT committing
  /// anything. The dynamic rules price every contender with it and the loop
  /// commits the winner with it, so the two cannot disagree.
  ({
    List<ProcessingSegment> setupSegments,
    SegmentedSchedule schedule,
    Duration usageAfter,
  }) _priceOperation({
    required OpenShopInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
  }) {
    // Setup then processing through the preemption engine. The task's
    // interruption flag governs the pair: interruptible → each may be split
    // by a shift end / maintenance / rest cap; not interruptible → one
    // contiguous block, processing starting the instant setup ends.
    final placed = _engineFor(machineId).computeSetupAndProcessing(
      earliestStart: start,
      setupDuration: _setupFor(machineId, job),
      processingDuration: duration,
      priorContinuousUsage:
          _machineContinuousUsage[machineId] ?? Duration.zero,
      interruptible: job.isTaskInterruptible(taskId),
    );

    return (
      setupSegments: placed.setupSegments,
      schedule: placed.processing,
      usageAfter: placed.continuousUsageAfter,
    );
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]). A candidate here is one operation, so p̄
  /// is the mean operation time and s̄ the mean changeover between two
  /// distinct jobs on a machine they share. The makespan estimate is the
  /// larger of the busiest machine's expected load and the longest job —
  /// the shop can finish no sooner than either.
  AtcsParameters _atcsParameters() {
    final Map<int, double> load = {};
    double longestJob = 0;
    int operationCount = 0;
    for (final job in inputJobs) {
      double jobTotal = 0;
      for (final operation in job.operations) {
        final machines = operation.value2;
        if (machines.isEmpty) continue;
        final double mean = machines.values
                .fold<double>(0, (sum, d) => sum + d.inSeconds / 60.0) /
            machines.length;
        jobTotal += mean;
        operationCount++;
        // Spread the operation evenly over the machines that can run it.
        for (final machineId in machines.keys) {
          load[machineId] = (load[machineId] ?? 0) + mean / machines.length;
        }
      }
      longestJob = max(longestJob, jobTotal);
    }

    final double meanSetup = _meanSetupMinutes(load.keys);
    final int machineCount = max(load.length, 1);
    final double bottleneck = load.values.fold(0.0, (a, b) => max(a, b)) +
        operationCount * meanSetup / machineCount;
    final double workMinutes = max(bottleneck, longestJob);

    return AtcsParameters.calibrate(
      start: startDate,
      dueDates: inputJobs.map((job) => job.dueDate),
      meanProcessingMinutes: _averageProcessingTime(),
      meanSetupMinutes: meanSetup,
      makespanMinutes: calendarMinutes(
        PreemptionEngine(workingSchedule: workingSchedule),
        startDate,
        Duration(minutes: workMinutes.round()),
      ),
    );
  }

  /// s̄ at operation level: the mean changeover over every machine and every
  /// ordered pair of distinct jobs that both have a state on it.
  double _meanSetupMinutes(Iterable<int> machineIds) {
    if (stateSetupMatrix == null || jobStates == null) return 0;
    double total = 0;
    int count = 0;
    for (final machineId in machineIds) {
      final matrix = stateSetupMatrix![machineId];
      if (matrix == null) continue;
      final onMachine = inputJobs
          .where((job) =>
              job.operations.any((op) => op.value2.containsKey(machineId)))
          .toList();
      for (final from in onMachine) {
        final fromState = jobStates![from.dbJobId]?[machineId];
        if (fromState == null) continue;
        for (final to in onMachine) {
          if (identical(from, to)) continue;
          final toState = jobStates![to.dbJobId]?[machineId];
          final minutes = toState == null ? null : matrix[fromState]?[toState];
          if (minutes == null) continue;
          total += minutes;
          count++;
        }
      }
    }
    return count == 0 ? 0 : total / count;
  }

  double _averageProcessingTime() {
    double totalProcessingTime = 0;
    int taskCount = 0;

    for (var job in inputJobs) {
      for (var operation in job.operations) {
        for (var duration in operation.value2.values) {
          totalProcessingTime += duration.inMinutes.toDouble();
          taskCount++;
        }
      }
    }
    return taskCount > 0 ? totalProcessingTime / taskCount : 1;
  }

  /// Non-delay list scheduler: each round, the ready operations that can
  /// start earliest compete and [comparator] picks among them.
  ///
  /// Every contender — for every rule — is priced through the preemption
  /// engine on each of its eligible machines and carried as `dispatch`, so
  /// the conflict set is built on EFFECTIVE starts and the machine is chosen
  /// by earliest completion before the rule picks the operation (see
  /// nonDelayConflictSet).
  ///
  /// A job WITHOUT precedences is a true open-shop job: its operations can be
  /// done in any order, but the job is on one machine at a time. A job WITH
  /// precedences (an order that mixes both kinds) follows its graph, and is
  /// also on one machine at a time: a job is one physical piece.
  ///
  /// [forcedMachine] (job id, task id) → machine restricts each operation to
  /// one machine (the genetic algorithm's assignment gene); [quiet] silences
  /// the progress logs during the GA's many decodings.
  ///
  /// [machineQueues] machine -> operations in the order the machine must
  /// process them (strict user sequence): an operation is a candidate only
  /// when it is the head of its machine's queue.
  void _schedule(
    int Function(dynamic, dynamic) comparator, {
    Map<(int, int), int>? forcedMachine,
    Map<int, List<(int, int)>>? machineQueues,
    bool quiet = false,
  }) {
    if (!quiet) {
      print(
          'OpenShop._schedule: entering main loop for ${inputJobs.length} jobs');
    }
    // Private copy: heads are consumed as operations are committed.
    final Map<int, List<(int, int)>>? queues = machineQueues == null
        ? null
        : {for (final e in machineQueues.entries) e.key: [...e.value]};
    // Rastrear qué operaciones ya se completaron por job
    Map<int, Set<int>> completedOperations = {
      for (var job in inputJobs) job.jobId: <int>{},
    };

    Map<int, Map<int, Tuple2<int, Range>>> jobSchedulings = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, Map<int, List<ProcessingSegment>>> jobSegments = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, Map<int, List<ProcessingSegment>>> jobSetupSegments = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, DateTime> jobAvailability = {
      for (var job in inputJobs) job.jobId: job.availableDate,
    };

    Map<int, Map<int, DateTime>> taskCompletionTimes = {
      for (var job in inputJobs) job.jobId: {},
    };

    bool isTaskReady(OpenShopInput job, int taskId, Set<int> completed) {
      if (job.dependencies.isEmpty) {
        // Open shop: any operation not yet done may go next. It used to
        // wait for the operation listed before it, which imposed the order
        // the tasks were created in — a flow shop, not an open shop.
        return true;
      } else {
        for (final dep in job.dependencies) {
          if (dep.successor_id == taskId) {
            if (!completed.contains(dep.predecessor_id)) return false;
          }
        }
        return true;
      }
    }

    DateTime getJobReadyTime(
        OpenShopInput job, int taskId, Map<int, DateTime> compTimes) {
      if (job.dependencies.isEmpty) {
        // One machine at a time: free once its last operation ends.
        return jobAvailability[job.jobId] ?? job.availableDate;
      } else {
        // Its arrows, AND one machine at a time: a job is one physical
        // piece, so operations with no arrow between them still cannot
        // overlap.
        DateTime readyTime = jobAvailability[job.jobId] ?? job.availableDate;
        for (final dep in job.dependencies) {
          if (dep.successor_id == taskId) {
            final predEndTime = compTimes[dep.predecessor_id];
            if (predEndTime != null && predEndTime.isAfter(readyTime)) {
              readyTime = predEndTime;
            }
          }
        }
        return readyTime;
      }
    }

    int iter = 0;
    const int maxIter = 1000000;

    // Mientras haya operaciones sin completar
    while (completedOperations.entries.any((entry) {
      final job = inputJobs.firstWhere((j) => j.jobId == entry.key);
      return entry.value.length < job.operations.length;
    })) {
      iter++;
      if (!quiet && iter % 10000 == 0) {
        print('OpenShop._schedule: iter=$iter');
      }
      if (iter > maxIter) {
        print(
            'OpenShop._schedule: reached max iterations ($maxIter), aborting loop');
        break;
      }
      List<
          ({
            OpenShopInput job,
            int taskId,
            int machineId,
            Duration duration,
            DateTime earliestStart,
            DispatchCandidate<OpenShopInput> dispatch
          })> candidates = [];
      // First pricing failure this round, rethrown only if it leaves no
      // candidate at all — same policy as selectNext in dynamic_dispatch.dart.
      SchedulingHorizonException? pricingFailure;

      // Recopilar todas las operaciones candidatas (no completadas)
      for (var job in inputJobs) {
        final completed = completedOperations[job.jobId]!;
        final compTimes = taskCompletionTimes[job.jobId]!;

        for (var operation in job.operations) {
          final taskId = operation.value1;

          // Si ya se completó esta operación, skip
          if (completed.contains(taskId)) continue;

          if (!isTaskReady(job, taskId, completed)) continue;

          final jobReadyTime = getJobReadyTime(job, taskId, compTimes);

          // Verificar cada máquina posible para esta operación
          final int? onlyMachine = forcedMachine?[(job.jobId, taskId)];
          for (var entry in operation.value2.entries) {
            final machineId = entry.key;
            if (onlyMachine != null && machineId != onlyMachine) continue;
            if (queues != null) {
              final queue = queues[machineId];
              if (queue == null ||
                  queue.isEmpty ||
                  queue.first != (job.jobId, taskId)) {
                continue;
              }
            }
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;
            final jobAvail = jobReadyTime;

            final earliestStart = machineAvailable.isAfter(jobAvail)
                ? machineAvailable
                : jobAvail;
            final adjustedStart = _adjustForWorkingSchedule(earliestStart);

            // What the operation really costs from here, priced through
            // the same code that commits it. One impossible machine must
            // not sink the operation's other options, so a failure only
            // drops this candidate.
            final DispatchCandidate<OpenShopInput> dispatch;
            try {
              dispatch = _dispatchCandidate(job, taskId, machineId, duration,
                  adjustedStart, completed, jobAvail);
            } on SchedulingHorizonException catch (e) {
              pricingFailure ??= e;
              continue;
            }

            candidates.add((
              job: job,
              taskId: taskId,
              machineId: machineId,
              duration: duration,
              earliestStart: adjustedStart,
              dispatch: dispatch,
            ));
          }
        }
      }

      if (candidates.isEmpty) {
        // Every ready operation was unplaceable on every machine: that is
        // the calendar's fault, and the user has to hear about it.
        if (pricingFailure != null) throw pricingFailure;
        break;
      }

      // Non-delay on the EFFECTIVE start (after changeover waits,
      // maintenance, rest caps and non-interruptible waits); if nothing can
      // start at the current instant, the clock effectively jumps to the
      // earliest effective start (Giffler & Thompson 1960, non-delay).
      //
      // Two decisions, kept apart (see nonDelayConflictSet): each operation
      // that can start at t* first gets its machine — earliest completion
      // among its machines available at t*, then cheapest changeover, then
      // lowest id — and only then does the rule choose among operations.
      final contenders = nonDelayConflictSet(
        candidates,
        operationKey: (c) => (c.job.jobId, c.taskId),
        candidate: (c) => c.dispatch,
        machineId: (c) => c.machineId,
      );
      contenders.sort(comparator);

      // Seleccionar el mejor candidato
      final selected = contenders.first;
      // Placed through the same code the dynamic rules priced candidates
      // with, so what gets committed is exactly what was judged.
      final placed = _priceOperation(
        job: selected.job,
        taskId: selected.taskId,
        machineId: selected.machineId,
        duration: selected.duration,
        start: selected.earliestStart,
      );
      final List<ProcessingSegment> setupSegments = placed.setupSegments;
      final SegmentedSchedule schedule = placed.schedule;
      final DateTime taskStart = schedule.startDate;
      final DateTime adjustedEnd = schedule.completionTime;

      // Programar la operación con taskStart (así queda el gap de alistamiento)
      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(taskStart, adjustedEnd));
      jobSegments[selected.job.jobId]![selected.taskId] = schedule.segments;
      jobSetupSegments[selected.job.jobId]![selected.taskId] = setupSegments;

      // Actualizar disponibilidades
      queues?[selected.machineId]?.removeAt(0);
      machinesAvailability[selected.machineId] = adjustedEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      completedOperations[selected.job.jobId]!.add(selected.taskId);
      taskCompletionTimes[selected.job.jobId]![selected.taskId] = adjustedEnd;
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
      // A job with no state (A-J) registered for this machine leaves the
      // machine in the state it found it. Recording it as the last job
      // anyway made the NEXT changeover look up a null state and cost zero.
      if (jobStates == null ||
          jobStates![selected.job.dbJobId]?[selected.machineId] != null) {
        _machineLastJob[selected.machineId] = selected.job.dbJobId;
      }
      _machineContinuousUsage[selected.machineId] = placed.usageAfter;
    }

    // Generar outputs
    for (var job in inputJobs) {
      final scheduling = jobSchedulings[job.jobId]!;
      if (scheduling.isEmpty) continue;

      DateTime? startDate;
      DateTime? endDate;

      for (var entry in scheduling.values) {
        final range = entry.value2;
        if (startDate == null || range.start.isBefore(startDate)) {
          startDate = range.start;
        }
        if (endDate == null || range.end.isAfter(endDate)) {
          endDate = range.end;
        }
      }

      output.add(OpenShopOutput(
        job.jobId,
        job.dbJobId,
        job.dueDate,
        startDate ?? job.availableDate,
        endDate ?? job.availableDate,
        scheduling,
        segmentsByTask: jobSegments[job.jobId],
        setupSegmentsByTask: jobSetupSegments[job.jobId] ?? const {},
      ));
    }
  }

  // ── TABU Open Shop: setup y precio propios ───────────────────────────────
  //
  // Copias de _setupFor y _priceOperation que reciben el estado de la máquina
  // como parámetro en vez de leerlo de la clase: el decode del TABU evalúa
  // vecinos sobre un estado local y no puede tocar _machineLastJob ni
  // _machineContinuousUsage. _setupFor y _priceOperation no se modifican, así
  // que las demás reglas no cambian. Si algún día cambia el cálculo de una,
  // hay que cambiar también su copia aquí (el AVISO de las semillas lo
  // delataría: la semilla decodificada dejaría de coincidir con su regla).

  /// Igual que _setupFor, pero con el último job de la máquina
  /// ([previousJobId], dbJobId) explícito en vez de _machineLastJob.
  Duration _setupForTabu(int machineId, OpenShopInput job, int? previousJobId) {
    if (stateSetupMatrix == null || jobStates == null) return Duration.zero;
    String? previousState;
    if (previousJobId != null && previousJobId > 0) {
      previousState = jobStates![previousJobId]?[machineId];
    } else {
      previousState = initialMachineState[machineId];
    }
    if (previousState == null) return Duration.zero;
    final machineStates = stateSetupMatrix![machineId];
    if (machineStates == null) return Duration.zero;
    final currentState = jobStates![job.dbJobId]?[machineId];
    if (currentState == null) return Duration.zero;
    final setupMinutes = machineStates[previousState]?[currentState];
    return setupMinutes != null
        ? Duration(minutes: setupMinutes)
        : Duration.zero;
  }

  /// Igual que _priceOperation, pero con el último job de la máquina
  /// ([previousJob]) y su racha de uso continuo ([priorUsage]) explícitos.
  /// No escribe nada en la clase.
  ({
    List<ProcessingSegment> setupSegments,
    SegmentedSchedule schedule,
    Duration usageAfter,
  }) _priceOperationTabu({
    required OpenShopInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
    required int? previousJob,
    required Duration priorUsage,
  }) {
    final placed = _engineFor(machineId).computeSetupAndProcessing(
      earliestStart: start,
      setupDuration: _setupForTabu(machineId, job, previousJob),
      processingDuration: duration,
      priorContinuousUsage: priorUsage,
      interruptible: job.isTaskInterruptible(taskId),
    );

    return (
      setupSegments: placed.setupSegments,
      schedule: placed.processing,
      usageAfter: placed.continuousUsageAfter,
    );
  }

  // ── TABU: (MA, π) con decodificador semi-activo ───────────────────────────
  //
  // Misma codificación que el TABU de FJSP (Brandimarte 1993; Pezzella et
  // al. 2008), con la diferencia propia del open shop: un job libre no tiene
  // ruta fija, así que el orden de sus operaciones en π ES su ruta.
  //   MA asigna a cada operación una máquina de SU estación (las máquinas de
  //      operation.value2), y
  //   π ordena todas las operaciones. Solo los jobs con dependencies imponen
  //      precedencias; las operaciones de un job libre van en cualquier orden.
  // _decode recorre π y pone cada operación en su máquina de MA lo antes
  // posible: max(job listo, máquina libre), con setup e interrupciones por el
  // PreemptionEngine — el mismo cálculo que el lazo de _schedule —, donde
  // "job listo" es, como en getJobReadyTime:
  //   job libre       → fin de su operación anterior en π (una máquina a la vez);
  //   job con flechas → fin de sus predecesoras.
  // Dos ramas por iteración:
  //   secuencia y ruta (primera mejora): u se adelanta delante de otra
  //         operación v de SU máquina (cambia la SECUENCIA de la máquina) o
  //         de SU job, si es libre (cambia la RUTA del job).
  //   máquina (mejor mejora): u, de uno de los jobs que más pesan en el
  //         objetivo, pasa a otra máquina Mb de su misma estación y se prueba
  //         en los k+1 huecos de Mb → cambia la ASIGNACIÓN.
  // Lista tabú, aspiración, intensificación y diversificación: las mismas
  // de máquinas paralelas, FFS y FJSP.
  void tabuSearchRule({required TabuParams params}) {
    final TabuObjective objective = params.objective;
    final Random random = Random(params.seed);

    // Dos relojes, como en parallel_machine.dart: [setupWatch] mide las
    // semillas y [watch] SOLO la búsqueda; el presupuesto corre sobre [watch].
    final Stopwatch setupWatch = Stopwatch()..start();
    final Stopwatch watch = Stopwatch();

    final _OpenShopTabuContext ctx = _buildTabuContext(objective);
    final int opCount = ctx.ops.length;

    // Llegan desde la interfaz; se acotan igual que en máquinas paralelas.
    final int maxIterations = params.maxIterations.clamp(1, 100000);
    final int intraAttempts = params.intraAttempts.clamp(1, 100000);
    final int interSamples = params.interJobSamples.clamp(1, max(1, opCount));
    final int maxDestinations = params.maxDestinations.clamp(1, 100);
    final int timeBudgetMs = params.timeBudgetMs.clamp(100, 600000);

    const int minTenure = 5;
    const int maxTenure = 12;
    const int shortTenure = 2; // al intensificar
    const int s1 = 15; // estancamiento -> intensificar
    const int s2 = 45; // estancamiento -> diversificar

    // ── Semillas: correr cada regla non-delay (_resetSchedule + _scheduleBy) ─
    // Orden fijo: si dos semillas empatan en valor y en flujo, gana la que
    // aparece primero. MWR y LWR entran porque son las reglas clásicas del
    // open shop (trabajo restante del job).
    final Map<String, void Function()> seeds = {
      'SPT': scheduleOpenShopSPT,
      'LPT': scheduleOpenShopLPT,
      'EDD': scheduleOpenShopEDD,
      'FIFO': scheduleOpenShopFIFO,
      'WSPT': scheduleOpenShopWSPT,
      'MS': scheduleOpenShopMS,
      'CR': scheduleOpenShopCR,
      'ATCS': scheduleOpenShopATCS,
      'MWR': scheduleOpenShopMWR,
      'LWR': scheduleOpenShopLWR,
    };

    _OpenShopTabuSolution? seedBest;
    String? seedBestName;
    // Mejor regla medida sobre su propio output, por si ninguna semilla se
    // puede convertir a (MA, π).
    String? ruleBestName;
    _OpenShopTabuCost? ruleBestCost;
    // Primera regla que el calendario no dejó terminar: solo se relanza si
    // ninguna otra semilla pudo correr.
    SchedulingHorizonException? seedFailure;
    int seedNumber = 0;
    for (final seed in seeds.entries) {
      seedNumber++;
      _resetSchedule(ctx.initialAvailability);
      try {
        seed.value();
      } on SchedulingHorizonException catch (e) {
        seedFailure ??= e;
        print('[TABU OS semilla $seedNumber] regla=${seed.key} · '
            'no cabe en el calendario, se descarta');
        continue;
      }
      final _OpenShopTabuCost ruleCost = _seedCost(objective, ctx.releaseByJob);
      if (ruleBestCost == null || ruleCost < ruleBestCost) {
        ruleBestCost = ruleCost;
        ruleBestName = seed.key;
      }

      // ── Codificar la semilla: inicio efectivo → fin → jobId → taskId ──
      final encoding = _encodeSchedule(ctx);
      if (encoding == null) {
        print('[TABU OS semilla $seedNumber] regla=${seed.key} · '
            'horario incompleto, se descarta');
        continue;
      }

      // ── current = decodificar(π, MA): _decode con estado local ──
      final _OpenShopTabuSolution candidate =
          _OpenShopTabuSolution.empty(opCount);
      try {
        candidate.cost =
            _decode(ctx, candidate, encoding.pi, encoding.ma, 0, save: true);
      } on SchedulingHorizonException {
        print('[TABU OS semilla $seedNumber] regla=${seed.key} · '
            'no se pudo decodificar, se descarta');
        continue;
      }
      final String mismatch = candidate.cost.compareTo(ruleCost) == 0
          ? ''
          : ' · AVISO: la regla daba ${ruleCost.value}';
      print('[TABU OS semilla $seedNumber] regla=${seed.key} · '
          '${objective.label}=${candidate.cost.value} ${objective.unit} '
          '(flujo ${candidate.cost.flow} min)$mismatch');
      if (seedBest == null || candidate.cost < seedBest.cost) {
        seedBest = candidate;
        seedBestName = seed.key;
      }
    }

    // Ninguna regla terminó: el calendario no admite el horario.
    if (ruleBestName == null) throw seedFailure!;

    // Sin semilla convertible (alguna regla dejó operaciones sin programar):
    // se deja el horario de la mejor regla, sin búsqueda.
    if (seedBest == null) {
      _resetSchedule(ctx.initialAvailability);
      seeds[ruleBestName]!();
      tabuStats = TabuRunStats(
        iterations: 0,
        maxIterations: maxIterations,
        elapsedMs: 0,
        timeBudgetMs: timeBudgetMs,
        objective: objective,
        initialValue: ruleBestCost!.value,
        bestValue: ruleBestCost.value,
        stoppedByTime: false,
      );
      print('[TABU OS] ninguna semilla completa: se deja $ruleBestName');
      return;
    }

    // ── Mejor semilla: current = best, con sus checkpoints ─────────────────
    _OpenShopTabuSolution best = seedBest;
    _OpenShopTabuSolution current = best.copy();
    final _OpenShopTabuCost initialCost = best.cost;

    final Map<String, int> tabuList = {};
    final Map<String, int> moveFrequency = {}; // memoria de largo plazo
    int noImprove = 0;
    int iter = 0;
    bool intensifying = false;
    bool timeUp() => watch.elapsedMilliseconds >= timeBudgetMs;

    // Termina la preparación: desde aquí corre el presupuesto de tiempo.
    setupWatch.stop();
    watch.start();

    // Con una sola operación no hay vecindario.
    while (opCount > 1 && iter < maxIterations && !timeUp()) {
      // ── Inicio de iteración k: current, best y checkpoints vigentes ──
      final List<int> pos = _positionsOf(current.pi);

      // Rama secuencia y ruta (morada).
      final _OpenShopTabuMove? intraMove = _bestIntraMove(
        ctx: ctx,
        current: current,
        pos: pos,
        tabuList: tabuList,
        iter: iter,
        bestCost: best.cost,
        random: random,
        maxAttempts: intraAttempts,
        timeUp: timeUp,
      );
      // Rama máquina (coral).
      final _OpenShopTabuMove? interMove = _bestInterMove(
        ctx: ctx,
        current: current,
        pos: pos,
        tabuList: tabuList,
        iter: iter,
        bestCost: best.cost,
        samples: interSamples,
        maxDestinations: maxDestinations,
        timeUp: timeUp,
      );

      // ── Mejor vecino admisible: valor → flujo → primero encontrado ──
      // intra se evalúa primero, así que gana los empates.
      _OpenShopTabuMove? chosen;
      if (intraMove != null && interMove != null) {
        chosen = interMove.cost < intraMove.cost ? interMove : intraMove;
      } else {
        chosen = intraMove ?? interMove;
      }

      if (chosen == null) {
        // Sin vecino admisible: iteración sin mejora; cae igual al control
        // de estancamiento.
        noImprove++;
      } else {
        // ── Actualizar current: re-decodificar desde i_min con save ──
        // Mismo (MA, π) y mismo checkpoint que la evaluación: mismo costo, y
        // deja los checkpoints nuevos.
        current.cost = _decode(
            ctx, current, chosen.pi, chosen.ma, chosen.from,
            save: true);

        // Atributo tabú con tenencia 5–12 (2 al intensificar).
        final int tenure = intensifying
            ? shortTenure
            : minTenure + random.nextInt(maxTenure - minTenure + 1);
        tabuList[chosen.attribute] = iter + tenure;
        moveFrequency[chosen.attribute] =
            (moveFrequency[chosen.attribute] ?? 0) + 1;
        if (iter % 25 == 0) {
          tabuList.removeWhere((_, expiration) => expiration <= iter);
        }

        // ── ¿F(current) < F(best)? ──
        if (current.cost < best.cost) {
          best = current.copy();
          noImprove = 0;
          intensifying = false;
        } else {
          noImprove++;
        }
      }

      // ── Contador de estancamiento ──
      if (noImprove == s1) {
        // Intensificar: current ← best, tenencia 2.
        current = best.copy();
        intensifying = true;
      } else if (noImprove >= s2) {
        // Diversificar: penaliza los 5 atributos más frecuentes
        // (2·maxTenure) y perturba best con max(2, N/6) movimientos
        // aleatorios, N = número de operaciones.
        tabuList.clear();
        final frequentAttributes = moveFrequency.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final entry in frequentAttributes.take(5)) {
          tabuList[entry.key] = iter + maxTenure * 2;
        }
        moveFrequency.updateAll((_, count) => count ~/ 2);
        moveFrequency.removeWhere((_, count) => count == 0);

        final perturbed =
            _perturbEncoding(ctx, best, max(2, opCount ~/ 6), random);
        final _OpenShopTabuSolution restarted =
            _OpenShopTabuSolution.empty(opCount);
        try {
          restarted.cost = _decode(
              ctx, restarted, perturbed.pi, perturbed.ma, 0,
              save: true);
          current = restarted;
        } on SchedulingHorizonException {
          // La perturbación no cabe en el calendario: se sigue desde best.
          current = best.copy();
        }
        noImprove = 0;
        intensifying = false;
      }

      iter++;
    }
    watch.stop(); // solo cuenta la búsqueda, sin el commit final

    // ── Commit del mejor (MA, π): decode sobre la clase → output, Gantt ──
    final _OpenShopTabuCost committed = _commitTabuSolution(ctx, best);
    if (committed.compareTo(best.cost) != 0) {
      print('[TABU OS] AVISO: el horario comiteado '
          '(${committed.value}) no coincide con el evaluado '
          '(${best.cost.value})');
    }

    // ── Estadísticas al adapter ──
    // El bucle sale por iter >= maxIterations o por tiempo; si quedaron
    // iteraciones sin hacer, la causa fue el presupuesto de tiempo.
    tabuStats = TabuRunStats(
      iterations: iter,
      maxIterations: maxIterations,
      elapsedMs: watch.elapsedMilliseconds,
      timeBudgetMs: timeBudgetMs,
      objective: objective,
      initialValue: initialCost.value,
      bestValue: best.cost.value,
      stoppedByTime: opCount > 1 && iter < maxIterations,
    );
    final String mejora = initialCost.value == 0
        ? '0.0'
        : ((initialCost.value - best.cost.value) * 100 / initialCost.value)
            .toStringAsFixed(1);
    print('[TABU OS] jobs=${inputJobs.length} · operaciones=$opCount · '
        'libres=${ctx.freeJob.where((free) => free).length} · '
        'semilla ganadora=$seedBestName · iteraciones=$iter/$maxIterations · '
        'semillas ${setupWatch.elapsedMilliseconds} ms · '
        'busqueda ${watch.elapsedMilliseconds} ms');
    print('[TABU OS] ${objective.label}: ${initialCost.value} → '
        '${best.cost.value} ${objective.unit} ($mejora% de mejora) · '
        'flujo total: ${initialCost.flow} → ${best.cost.flow} min');
  }

  /// Deja el horario como estaba al terminar el constructor y antes de
  /// correr cualquier regla, para que cada semilla del TABU arranque del
  /// mismo punto. _engineByMachine se conserva: solo guarda la
  /// configuración del calendario de cada máquina.
  void _resetSchedule(Map<int, DateTime> initialAvailability) {
    machinesAvailability
      ..clear()
      ..addAll(initialAvailability);
    output.clear();
    _machineContinuousUsage.clear();
    _machineLastSequence.clear();
    _machineLastJob.clear();
    _initializeMachineLastSequence();
  }

  /// Costo del horario que hay en [output] (o en [schedule], si se pasa)
  /// para [objective], con las mismas definiciones que _machineCost en
  /// parallel_machine.dart. Cj es el fin de la última operación del job.
  _OpenShopTabuCost _seedCost(
    TabuObjective objective,
    Map<int, DateTime> releaseByJob, [
    List<OpenShopOutput>? schedule,
  ]) {
    Duration flow = Duration.zero;
    Duration tardiness = Duration.zero;
    Duration earliness = Duration.zero;
    int tardyJobs = 0;
    DateTime lastEnd = startDate;
    for (final out in schedule ?? output) {
      final DateTime release = releaseByJob[out.jobId] ?? startDate;
      flow += out.endTime.difference(release); // C_j − r_j
      if (out.endTime.isAfter(out.dueDate)) {
        tardiness += out.endTime.difference(out.dueDate); // max(0, C_j − d_j)
        tardyJobs++; // U_j
      } else {
        earliness += out.dueDate.difference(out.endTime); // max(0, d_j − C_j)
      }
      if (out.endTime.isAfter(lastEnd)) lastEnd = out.endTime; // C_max
    }
    final int flowMinutes = flow.inMinutes;
    final int value = switch (objective) {
      TabuObjective.totalFlow => flowMinutes,
      TabuObjective.makespan => lastEnd.difference(startDate).inMinutes,
      TabuObjective.totalTardiness => tardiness.inMinutes,
      TabuObjective.tardyJobs => tardyJobs,
      TabuObjective.totalEarliness => earliness.inMinutes,
    };
    return _OpenShopTabuCost(value, flowMinutes);
  }

  // ── TABU Open Shop: codificación (MA, π) ──────────────────────────────────

  /// Operaciones, precedencias y datos fijos de la corrida. Solo los jobs con
  /// dependencies aportan precedencias; un job libre no tiene cadena (en FJSP
  /// sí, por su ruta), y la regla "una máquina a la vez" la impone _decode.
  _OpenShopTabuContext _buildTabuContext(TabuObjective objective) {
    final List<_OpenShopOp> ops = [];
    final List<List<int>> opsByJob = [];
    final List<bool> freeJob = [];
    for (int j = 0; j < inputJobs.length; j++) {
      final OpenShopInput job = inputJobs[j];
      final List<int> ids = [];
      for (final operation in job.operations) {
        ids.add(ops.length);
        ops.add(_OpenShopOp(
          job: job,
          jobIndex: j,
          taskId: operation.value1,
          durations: operation.value2,
        ));
      }
      opsByJob.add(ids);
      freeJob.add(job.dependencies.isEmpty);
    }

    final List<List<int>> predecessors = List.generate(ops.length, (_) => []);
    final List<List<int>> successors = List.generate(ops.length, (_) => []);
    for (int j = 0; j < inputJobs.length; j++) {
      if (freeJob[j]) continue;
      final Map<int, int> opOfTask = {
        for (final id in opsByJob[j]) ops[id].taskId: id,
      };
      for (final dep in inputJobs[j].dependencies) {
        final int? succ = opOfTask[dep.successor_id];
        final int? pred = opOfTask[dep.predecessor_id];
        if (succ == null || pred == null) continue;
        predecessors[succ].add(pred);
        successors[pred].add(succ);
      }
    }

    return _OpenShopTabuContext(
      objective: objective,
      initialAvailability: Map<int, DateTime>.from(machinesAvailability),
      releaseByJob: {
        for (final job in inputJobs) job.jobId: job.availableDate,
      },
      ops: ops,
      opsByJob: opsByJob,
      freeJob: freeJob,
      predecessors: predecessors,
      successors: successors,
    );
  }

  /// Convierte el horario que dejó una regla en [output] a (MA, π):
  /// MA = la máquina de cada operación; π = las operaciones ordenadas por
  /// inicio efectivo (setup incluido), luego fin, luego jobId y taskId.
  /// null si a la regla le faltó programar alguna operación.
  ///
  /// El fin desempata dos inicios iguales: con una operación de cero minutos
  /// [t, t] y otra [t, t+p] del mismo job o de la misma máquina, la de cero
  /// fue necesariamente la primera (si no, habría empezado en t+p). FJSP
  /// desempata con la posición en la ruta, que aquí no existe.
  ({List<int> pi, List<int> ma})? _encodeSchedule(_OpenShopTabuContext ctx) {
    final Map<int, OpenShopOutput> outputByJob = {
      for (final out in output) out.jobId: out,
    };
    final int n = ctx.ops.length;
    final List<int> ma = List<int>.filled(n, -1);
    final List<DateTime> effectiveStart = List<DateTime>.filled(n, startDate);
    final List<DateTime> end = List<DateTime>.filled(n, startDate);
    for (int opId = 0; opId < n; opId++) {
      final _OpenShopOp op = ctx.ops[opId];
      final OpenShopOutput? out = outputByJob[op.job.jobId];
      final Tuple2<int, Range>? entry = out?.scheduling[op.taskId];
      if (entry == null) return null;
      ma[opId] = entry.value1;
      final List<ProcessingSegment> setups =
          out!.setupSegmentsByTask[op.taskId] ?? const [];
      effectiveStart[opId] =
          setups.isNotEmpty ? setups.first.start : entry.value2.startDate;
      end[opId] = entry.value2.endDate;
    }

    final List<int> order = List<int>.generate(n, (k) => k)
      ..sort((a, b) {
        int cmp = effectiveStart[a].compareTo(effectiveStart[b]);
        if (cmp != 0) return cmp;
        cmp = end[a].compareTo(end[b]);
        if (cmp != 0) return cmp;
        cmp = ctx.ops[a].job.jobId.compareTo(ctx.ops[b].job.jobId);
        if (cmp != 0) return cmp;
        cmp = ctx.ops[a].taskId.compareTo(ctx.ops[b].taskId);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
    return (pi: _respectPrecedence(ctx, order), ma: ma);
  }

  /// Orden topológico estable: conserva [order] salvo que una operación de
  /// un job con dependencies aparezca antes que una predecesora (solo
  /// posible con duraciones cero). Las operaciones libres no se mueven.
  List<int> _respectPrecedence(_OpenShopTabuContext ctx, List<int> order) {
    final Set<int> done = {};
    final List<int> pending = List<int>.from(order);
    final List<int> result = [];
    while (pending.isNotEmpty) {
      final int idx = pending
          .indexWhere((op) => ctx.predecessors[op].every(done.contains));
      if (idx < 0) {
        result.addAll(pending); // ciclo en dependencies: se deja como está
        break;
      }
      final int op = pending.removeAt(idx);
      result.add(op);
      done.add(op);
    }
    return result;
  }

  /// opId → posición en [pi].
  List<int> _positionsOf(List<int> pi) {
    final List<int> pos = List<int>.filled(pi.length, 0);
    for (int k = 0; k < pi.length; k++) {
      pos[pi[k]] = k;
    }
    return pos;
  }

  /// Ventana de inserción de [u] en π sin u: [lo, hi] = después de su última
  /// predecesora y antes de su primera sucesora. Cualquier índice de la
  /// ventana mantiene π factible. Para una operación de un job libre la
  /// ventana es toda π.
  (int, int) _windowWithout(
      _OpenShopTabuContext ctx, List<int> pos, int u, int length) {
    final int pu = pos[u];
    int at(int opId) => pos[opId] < pu ? pos[opId] : pos[opId] - 1;
    int lo = 0;
    for (final p in ctx.predecessors[u]) {
      lo = max(lo, at(p) + 1);
    }
    int hi = length - 1;
    for (final s in ctx.successors[u]) {
      hi = min(hi, at(s));
    }
    return (lo, hi);
  }

  // ── TABU Open Shop: decodificador ─────────────────────────────────────────

  /// Decodifica (MA, π) = ([ma], [pi]) y devuelve su costo (objetivo, flujo).
  ///
  /// [from] = i_min (la posición p del diagrama): π[0..from−1] y sus
  /// máquinas deben coincidir con [base]; se restaura base.checkpoints[from]
  /// y solo se re-simula el sufijo.
  ///
  /// Cada operación arranca en max(job listo, máquina libre), ajustado al
  /// turno, y se precia con _priceOperationTabu: el mismo cálculo que el lazo
  /// de _schedule, sobre un _OpenShopDecodeState local. "Job listo" se
  /// calcula igual que getJobReadyTime en _schedule:
  ///   job libre       → jobFree: fin de su última operación ya puesta
  ///                     (jobAvailability en _schedule);
  ///   job con flechas → máximo entre su liberación y el fin de sus
  ///                     predecesoras.
  /// Ambos se reconstruyen del prefijo, así que el checkpoint solo guarda el
  /// estado de las máquinas.
  ///
  /// save: false → no toca [base] (evaluar un vecino).
  /// save: true  → [base] pasa a ser (MA, π) con sus checkpoints nuevos.
  _OpenShopTabuCost _decode(
    _OpenShopTabuContext ctx,
    _OpenShopTabuSolution base,
    List<int> pi,
    List<int> ma,
    int from, {
    required bool save,
  }) {
    final int n = pi.length;

    // ── Restaurar checkpoint[i_min] ──
    final _OpenShopDecodeState state = from == 0
        ? _OpenShopDecodeState.initial(ctx.initialAvailability)
        : base.checkpoints[from].copy();
    final List<_OpenShopPlacedOp?> placed =
        save ? base.placed : List<_OpenShopPlacedOp?>.from(base.placed);

    // Fin de cada operación del prefijo (por job y tarea) y momento en que
    // cada job libre queda desocupado.
    final List<Map<int, DateTime>> completion =
        List.generate(ctx.opsByJob.length, (_) => <int, DateTime>{});
    final List<DateTime> jobFree = [
      for (final job in inputJobs) job.availableDate,
    ];
    for (int k = 0; k < from; k++) {
      final _OpenShopOp op = ctx.ops[pi[k]];
      final DateTime end = placed[pi[k]]!.schedule.completionTime;
      completion[op.jobIndex][op.taskId] = end;
      jobFree[op.jobIndex] = end;
    }

    if (save) base.checkpoints.removeRange(from, base.checkpoints.length);

    // ── Re-simular el sufijo ──
    for (int k = from; k < n; k++) {
      if (save) base.checkpoints.add(state.copy());
      final int opId = pi[k];
      final _OpenShopOp op = ctx.ops[opId];
      final int machineId = ma[opId];

      DateTime jobReady;
      if (ctx.freeJob[op.jobIndex]) {
        // Una máquina a la vez: espera a que termine su operación anterior.
        jobReady = jobFree[op.jobIndex];
      } else {
        jobReady = op.job.availableDate;
        for (final int p in ctx.predecessors[opId]) {
          final DateTime? predEnd = completion[op.jobIndex][ctx.ops[p].taskId];
          if (predEnd != null && predEnd.isAfter(jobReady)) jobReady = predEnd;
        }
      }
      final DateTime machineFree = state.machineFree[machineId] ?? startDate;
      final DateTime earliest =
          machineFree.isAfter(jobReady) ? machineFree : jobReady;
      final DateTime start = _adjustForWorkingSchedule(earliest);
      final int? previousJob = state.lastJob[machineId];
      final Duration priorUsage = state.usage[machineId] ?? Duration.zero;

      // Misma operación, misma máquina y mismos datos que en el decode
      // anterior → mismo resultado: se reutiliza. Un movimiento solo cambia
      // las operaciones a las que alcanza (su máquina, su job y lo que
      // empuje); el resto del sufijo se copia en vez de re-preciarse.
      final _OpenShopPlacedOp? previous = placed[opId];
      final _OpenShopPlacedOp result = previous != null &&
              previous.machineId == machineId &&
              previous.start == start &&
              previous.previousJob == previousJob &&
              previous.priorUsage == priorUsage
          ? previous
          : _placeOperation(op, machineId, start, previousJob, priorUsage);
      final DateTime end = result.schedule.completionTime;

      state.machineFree[machineId] = end;
      state.usage[machineId] = result.usageAfter;
      // Igual que _schedule: un job sin estado en esta máquina la deja en el
      // estado en que la encontró.
      if (jobStates == null || jobStates![op.job.dbJobId]?[machineId] != null) {
        state.lastJob[machineId] = op.job.dbJobId;
      }
      completion[op.jobIndex][op.taskId] = end;
      jobFree[op.jobIndex] = end;
      placed[opId] = result;
    }

    final List<OpenShopOutput> schedule = _tabuSchedule(ctx, placed);
    final _OpenShopTabuCost cost =
        _seedCost(ctx.objective, ctx.releaseByJob, schedule);
    if (save) {
      base.pi = pi;
      base.ma = ma;
      base.finalState = state;
      base.schedule = schedule;
      base.cost = cost;
    }
    return cost;
  }

  /// Precia [op] en [machineId] desde [start] con _priceOperationTabu — el
  /// mismo cálculo que el lazo de _schedule — y guarda con qué datos se
  /// precio.
  _OpenShopPlacedOp _placeOperation(
    _OpenShopOp op,
    int machineId,
    DateTime start,
    int? previousJob,
    Duration priorUsage,
  ) {
    final result = _priceOperationTabu(
      job: op.job,
      taskId: op.taskId,
      machineId: machineId,
      duration: op.durations[machineId]!,
      start: start,
      previousJob: previousJob,
      priorUsage: priorUsage,
    );
    return (
      machineId: machineId,
      start: start,
      previousJob: previousJob,
      priorUsage: priorUsage,
      setupSegments: result.setupSegments,
      schedule: result.schedule,
      usageAfter: result.usageAfter,
    );
  }

  /// Arma el output de un decode con el mismo formato que _schedule: un
  /// OpenShopOutput por job, inicio = menor inicio de procesamiento y fin =
  /// mayor fin de sus operaciones.
  List<OpenShopOutput> _tabuSchedule(
    _OpenShopTabuContext ctx,
    List<_OpenShopPlacedOp?> placed,
  ) {
    final List<OpenShopOutput> result = [];
    for (int j = 0; j < inputJobs.length; j++) {
      final OpenShopInput job = inputJobs[j];
      final Map<int, Tuple2<int, Range>> sched = {};
      final Map<int, List<ProcessingSegment>> segments = {};
      final Map<int, List<ProcessingSegment>> setups = {};
      for (final int opId in ctx.opsByJob[j]) {
        final _OpenShopPlacedOp? p = placed[opId];
        if (p == null) continue;
        final int taskId = ctx.ops[opId].taskId;
        sched[taskId] = Tuple2(
            p.machineId, Range(p.schedule.startDate, p.schedule.completionTime));
        segments[taskId] = p.schedule.segments;
        setups[taskId] = p.setupSegments;
      }
      if (sched.isEmpty) continue;

      final DateTime start = sched.values
          .map((t) => t.value2.startDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final DateTime end = sched.values
          .map((t) => t.value2.endDate)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      result.add(OpenShopOutput(
        job.jobId,
        job.dbJobId,
        job.dueDate,
        start,
        end,
        sched,
        segmentsByTask: segments,
        setupSegmentsByTask: setups,
      ));
    }
    return result;
  }

  /// Commit: decodifica [solution] desde 0 y deja su horario en la clase —
  /// output y el estado de cada máquina, como lo dejaría el lazo de
  /// _schedule. Devuelve el costo del horario comiteado.
  _OpenShopTabuCost _commitTabuSolution(
    _OpenShopTabuContext ctx,
    _OpenShopTabuSolution solution,
  ) {
    final _OpenShopTabuCost cost =
        _decode(ctx, solution, solution.pi, solution.ma, 0, save: true);
    _resetSchedule(ctx.initialAvailability);
    machinesAvailability.addAll(solution.finalState.machineFree);
    _machineLastJob.addAll(solution.finalState.lastJob);
    _machineContinuousUsage.addAll(solution.finalState.usage);
    for (final int opId in solution.pi) {
      _machineLastSequence[solution.ma[opId]] = ctx.ops[opId].job.sequenceId;
    }
    output.addAll(solution.schedule);
    return cost;
  }

  // ── TABU Open Shop: vecindarios ───────────────────────────────────────────

  /// Rama secuencia y ruta — primera mejora (morada en el diagrama).
  ///
  /// Toma hasta [maxAttempts] operaciones u al azar (solo cuentan las que
  /// tienen algún candidato) y, dentro de su ventana, prueba adelantar u
  /// justo delante de otra operación v, de la más cercana a la más lejana,
  /// cuando v es:
  ///   - de la MISMA MÁQUINA que u → cambia la secuencia de esa máquina;
  ///   - del MISMO JOB que u, si el job es libre → cambia su ruta (qué
  ///     operación hace primero).
  /// Las demás v se saltan porque el vecino sería igual a current: mover u
  /// delante de una operación de otra máquina y otro job no cambia ninguna
  /// secuencia ni ninguna ruta. Por lo mismo, en un job con dependencies el
  /// "mismo job" no cuenta: sus operaciones sin flecha se pueden solapar y su
  /// orden relativo en π no cambia nada.
  /// Devuelve el primero admisible que mejora current.
  _OpenShopTabuMove? _bestIntraMove({
    required _OpenShopTabuContext ctx,
    required _OpenShopTabuSolution current,
    required List<int> pos,
    required Map<String, int> tabuList,
    required int iter,
    required _OpenShopTabuCost bestCost,
    required Random random,
    required int maxAttempts,
    required bool Function() timeUp,
  }) {
    final List<int> pi = current.pi;
    final List<int> ma = current.ma;
    final List<int> order = List<int>.from(pi)..shuffle(random);

    int attempts = 0;
    for (final int u in order) {
      if (attempts >= maxAttempts) break;
      final int m = ma[u];
      final int jobOfU = ctx.ops[u].jobIndex;
      final bool routeIsFree = ctx.freeJob[jobOfU];
      final int pu = pos[u];
      int lo = 0;
      for (final p in ctx.predecessors[u]) {
        lo = max(lo, pos[p] + 1);
      }

      bool counted = false;
      for (int k = pu - 1; k >= lo; k--) {
        final int v = pi[k];
        final bool sameMachine = ma[v] == m;
        final bool sameRoute = routeIsFree && ctx.ops[v].jobIndex == jobOfU;
        if (!sameMachine && !sameRoute) continue;
        if (!counted) {
          counted = true;
          attempts++;
        }
        if (timeUp()) return null;

        final List<int> trial = List<int>.from(pi)
          ..removeAt(pu)
          ..insert(k, u);
        final _OpenShopTabuCost cost;
        try {
          cost = _decode(ctx, current, trial, ma, k, save: false);
        } on SchedulingHorizonException {
          continue; // no cabe en el calendario: vecino no factible
        }
        if (!(cost < current.cost)) continue;

        final String attribute = _intraAttribute(ctx, u, v);
        final bool isTabu = (tabuList[attribute] ?? -1) > iter;
        final bool aspiration = cost < bestCost;
        if (isTabu && !aspiration) continue;

        return _OpenShopTabuMove(
          isIntra: true,
          pi: trial,
          ma: ma,
          from: k,
          attribute: attribute,
          cost: cost,
        );
      }
    }
    return null;
  }

  /// Rama máquina — mejor mejora (coral en el diagrama).
  ///
  /// Ordena las operaciones flexibles (más de una máquina en su estación)
  /// por el aporte de su job al objetivo — el apalancamiento — (desempate:
  /// flujo del job y fin de la operación) y toma hasta [samples]. Para cada
  /// u prueba hasta [maxDestinations] máquinas Mb de su misma estación, las
  /// que terminan antes, y en cada Mb los k+1 huecos que dejan sus k
  /// operaciones dentro de la ventana de u (toda π si el job es libre).
  /// Devuelve el mejor admisible.
  _OpenShopTabuMove? _bestInterMove({
    required _OpenShopTabuContext ctx,
    required _OpenShopTabuSolution current,
    required List<int> pos,
    required Map<String, int> tabuList,
    required int iter,
    required _OpenShopTabuCost bestCost,
    required int samples,
    required int maxDestinations,
    required bool Function() timeUp,
  }) {
    final List<int> pi = current.pi;
    final List<int> ma = current.ma;

    // ── Elegir u por apalancamiento: aporte del job al objetivo ──
    final Map<int, (int, int)> weightByJob = {};
    for (final out in current.schedule) {
      final DateTime release = ctx.releaseByJob[out.jobId] ?? startDate;
      final int flow = out.endTime.difference(release).inMinutes;
      final bool late = out.endTime.isAfter(out.dueDate);
      final int contribution = switch (ctx.objective) {
        TabuObjective.totalFlow => flow,
        TabuObjective.makespan => out.endTime.difference(startDate).inMinutes,
        TabuObjective.totalTardiness =>
          late ? out.endTime.difference(out.dueDate).inMinutes : 0,
        TabuObjective.tardyJobs => late ? 1 : 0,
        TabuObjective.totalEarliness =>
          late ? 0 : out.dueDate.difference(out.endTime).inMinutes,
      };
      weightByJob[out.jobId] = (contribution, flow);
    }

    DateTime endOf(int opId) => current.placed[opId]!.schedule.completionTime;
    final List<int> flexible = [
      for (int opId = 0; opId < ctx.ops.length; opId++)
        if (ctx.ops[opId].durations.length > 1) opId,
    ]..sort((a, b) {
        final (int, int) wa = weightByJob[ctx.ops[a].job.jobId] ?? (0, 0);
        final (int, int) wb = weightByJob[ctx.ops[b].job.jobId] ?? (0, 0);
        int cmp = wb.$1.compareTo(wa.$1);
        if (cmp != 0) return cmp;
        cmp = wb.$2.compareTo(wa.$2);
        if (cmp != 0) return cmp;
        cmp = endOf(b).compareTo(endOf(a));
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    _OpenShopTabuMove? bestMove;
    for (final int u in flexible.take(samples)) {
      final int machineFrom = ma[u];
      final int pu = pos[u];

      // ── Destinos Mb elegibles (mismo proceso): menor fin primero ──
      final List<int> destinations = ctx.ops[u].durations.keys
          .where((m) => m != machineFrom)
          .toList()
        ..sort((a, b) {
          final int cmp = (current.finalState.machineFree[a] ?? startDate)
              .compareTo(current.finalState.machineFree[b] ?? startDate);
          return cmp != 0 ? cmp : a.compareTo(b);
        });

      // ── Retirar u de su máquina origen ──
      final List<int> without = List<int>.from(pi)..removeAt(pu);
      final (int lo, int hi) = _windowWithout(ctx, pos, u, pi.length);

      for (final int machineTo in destinations.take(maxDestinations)) {
        // ── Huecos de Mb en la ventana: k operaciones → k+1 huecos ──
        final List<(int, int)> gaps = [];
        int gapStart = lo;
        for (int k = lo; k < hi; k++) {
          if (ma[without[k]] == machineTo) {
            gaps.add((gapStart, k));
            gapStart = k + 1;
          }
        }
        gaps.add((gapStart, hi));

        for (final (int gapLo, int gapHi) in gaps) {
          if (timeUp()) return bestMove;
          // Dentro del hueco, la posición más cercana a la original (relocate
          // + insert): misma secuencia en Mb, la ruta del job cambia lo menos
          // posible y el i_min es el más alto posible.
          final int insertAt = pu.clamp(gapLo, gapHi);
          final List<int> trialPi = List<int>.from(without)..insert(insertAt, u);
          final List<int> trialMa = List<int>.from(ma)..[u] = machineTo;
          final int from = min(pu, insertAt);

          final _OpenShopTabuCost cost;
          try {
            cost = _decode(ctx, current, trialPi, trialMa, from, save: false);
          } on SchedulingHorizonException {
            continue; // no cabe en el calendario: vecino no factible
          }

          final String attribute =
              'inter:${ctx.ops[u].key}:${machineFrom}_$machineTo';
          final bool isTabu = (tabuList[attribute] ?? -1) > iter;
          final bool aspiration = cost < bestCost;
          if (isTabu && !aspiration) continue;

          if (bestMove == null || cost < bestMove.cost) {
            bestMove = _OpenShopTabuMove(
              isIntra: false,
              pi: trialPi,
              ma: trialMa,
              from: from,
              attribute: attribute,
              cost: cost,
            );
          }
        }
      }
    }
    return bestMove;
  }

  /// Atributo intra (u, v), sin orden. Sirve igual para un cambio de
  /// secuencia o de ruta: lo que se prohíbe es volver a invertir el par.
  String _intraAttribute(_OpenShopTabuContext ctx, int u, int v) {
    final String a = ctx.ops[u].key;
    final String b = ctx.ops[v].key;
    return a.compareTo(b) < 0 ? 'intra:${a}_$b' : 'intra:${b}_$a';
  }

  /// Diversificación: [steps] movimientos aleatorios sobre best. Cada uno
  /// saca una operación, le sortea una máquina de su estación y la vuelve a
  /// poner en una posición al azar de su ventana — en un job libre eso
  /// también baraja su ruta.
  ({List<int> pi, List<int> ma}) _perturbEncoding(
    _OpenShopTabuContext ctx,
    _OpenShopTabuSolution best,
    int steps,
    Random random,
  ) {
    final List<int> pi = List<int>.from(best.pi);
    final List<int> ma = List<int>.from(best.ma);
    for (int s = 0; s < steps; s++) {
      final List<int> pos = _positionsOf(pi);
      final int u = random.nextInt(ctx.ops.length);
      final (int lo, int hi) = _windowWithout(ctx, pos, u, pi.length);
      pi.removeAt(pos[u]);
      final List<int> machines = ctx.ops[u].durations.keys.toList();
      ma[u] = machines[random.nextInt(machines.length)];
      pi.insert(lo + random.nextInt(hi - lo + 1), u);
    }
    return (pi: pi, ma: ma);
  }

  int calcularCmax(List<OpenShopOutput> outputs) {
    if (outputs.isEmpty) return 0;

    DateTime maxEndTime = outputs.first.endTime;
    for (var output in outputs) {
      if (output.endTime.isAfter(maxEndTime)) {
        maxEndTime = output.endTime;
      }
    }

    return maxEndTime.difference(startDate).inMinutes;
  }
}

/// Punto de entrada del isolate. Devuelve {'output': [...], 'tabuStats':
/// {...} o null}, como flexibleJobShopSchedule.
Map<String, dynamic> openShopSchedule(Map<String, dynamic> payload) {
  final startDate =
      DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(
        hour: payload['workingStartHour'] as int,
        minute: payload['workingStartMinute'] as int),
    TimeOfDay(
        hour: payload['workingEndHour'] as int,
        minute: payload['workingEndMinute'] as int),
  );

  final List<OpenShopInput> inputJobs =
      (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jd = Map<String, dynamic>.from(jobData as Map);
    final Map<int, bool> interruptibleByTask = {};
    final operations = (jd['operations'] as List<dynamic>).map((opData) {
      final od = Map<String, dynamic>.from(opData as Map);
      final machineDurations =
          (od['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) =>
            MapEntry(key as int, Duration(milliseconds: value as int)),
      );
      final taskId = od['taskId'] as int;
      interruptibleByTask[taskId] = (od['interruptible'] as bool?) ?? true;
      return Tuple2(taskId, machineDurations);
    }).toList();

    final dependencies = (jd['dependencies'] as List<dynamic>)
        .map((depData) {
          final depMap = Map<String, dynamic>.from(depData as Map);
          return TaskDependencyEntity(
            predecessor_id: depMap['predecessor_id'] as int,
            successor_id: depMap['successor_id'] as int,
            sequenceId: depMap['sequenceId'] as int,
          );
        })
        .cast<TaskDependencyEntity>()
        .toList();

    return OpenShopInput(
      jd['jobId'] as int,
      jd['dbJobId'] as int,
      jd['sequenceId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jd['dueDate'] as int),
      jd['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jd['availableDate'] as int),
      operations,
      dependencies: dependencies,
      interruptibleByTask: interruptibleByTask,
    );
  }).toList();

  final machinesAvailability =
      (payload['machinesAvailability'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
              key as int, DateTime.fromMillisecondsSinceEpoch(value as int)));

  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  for (final entry
      in (payload['machineInactivities'] as Map<dynamic, dynamic>).entries) {
    final machineId = entry.key as int;
    final list = (entry.value as List<dynamic>);
    machineInactivities[machineId] = list
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return MachineInactivityEntity(
            machineId: map['machineId'] as int,
            name: map['name'] as String,
            weekdays: (map['weekdays'] as List<dynamic>)
                .map((w) => Weekday.values[w as int])
                .toSet(),
            startTime: Duration(minutes: map['startTimeMinutes'] as int),
            duration: Duration(minutes: map['durationMinutes'] as int),
          );
        })
        .cast<MachineInactivityEntity>()
        .toList();
  }

  final machineContinueCapacity =
      (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as int));

  final machineRestTime = <int, Duration?>{};
  for (final entry
      in (payload['machineRestTime'] as Map<dynamic, dynamic>).entries) {
    machineRestTime[entry.key as int] =
        entry.value == null ? null : Duration(milliseconds: entry.value as int);
  }

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map)).map(
              (prev, curr) => MapEntry(
                prev as String,
                (Map<dynamic, dynamic>.from(curr as Map)).map((next, minutes) =>
                    MapEntry(next as String, minutes as int)),
              ),
            ),
          ),
        );

  final jobStates = payload['jobStates'] == null
      ? null
      : (payload['jobStates'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map))
                .map((mKey, state) => MapEntry(mKey as int, state as String)),
          ),
        );

  final initialMachineState = payload['initialMachineState'] == null
      ? const <int, String>{}
      : (payload['initialMachineState'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as String));

  // TabuParams viaja en primitivos, como el resto del payload.
  final rawTabu = payload['tabuParams'] as Map<dynamic, dynamic>?;
  final TabuParams tabuParams = rawTabu == null
      ? const TabuParams()
      : TabuParams(
          maxIterations: rawTabu['maxIterations'] as int,
          intraAttempts: rawTabu['intraAttempts'] as int,
          interJobSamples: rawTabu['interJobSamples'] as int,
          maxDestinations: rawTabu['maxDestinations'] as int,
          timeBudgetMs: rawTabu['timeBudgetMs'] as int,
          seed: rawTabu['seed'] as int,
          randomStart: rawTabu['randomStart'] as bool,
          objective:
              TabuObjective.values.byName(rawTabu['objective'] as String),
        );

  final OpenShop openShop = OpenShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    initialMachineState: initialMachineState,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    geneticParams: GeneticParams.fromMap(
        payload['geneticParams'] as Map<dynamic, dynamic>?),
    userSequence: (payload['userSequence'] as List<dynamic>?)?.cast<int>(),
    machineSequences: (payload['machineSequences'] as Map<dynamic, dynamic>?)
        ?.map((machine, jobs) => MapEntry(
            machine as int, (jobs as List<dynamic>).cast<int>())),
    userRoutes: (payload['userRoutes'] as Map<dynamic, dynamic>?)?.map(
        (job, machines) => MapEntry(
            job as int, (machines as List<dynamic>).cast<int>())),
    tabuParams: tabuParams,
  );
  final output = openShop.output;
  final TabuRunStats? stats = openShop.tabuStats;

  final List<Map<String, dynamic>> outputPayload =
      output.map<Map<String, dynamic>>((out) {
    return {
      'jobId': out.jobId,
      'dbJobId': out.dbJobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling':
          out.scheduling.map((key, value) => MapEntry(key.toString(), {
                'machineId': value.value1,
                'start': value.value2.startDate.millisecondsSinceEpoch,
                'end': value.value2.endDate.millisecondsSinceEpoch,
              })),
      'segmentsByTask': out.segmentsByTask.map((taskId, segments) => MapEntry(
            taskId.toString(),
            segments
                .map((s) => {
                      'start': s.start.millisecondsSinceEpoch,
                      'end': s.end.millisecondsSinceEpoch,
                    })
                .toList(),
          )),
      'setupSegmentsByTask':
          out.setupSegmentsByTask.map((taskId, segments) => MapEntry(
                taskId.toString(),
                segments
                    .map((s) => {
                          'start': s.start.millisecondsSinceEpoch,
                          'end': s.end.millisecondsSinceEpoch,
                        })
                    .toList(),
              )),
    };
  }).toList();

  return {
    'output': outputPayload,
    'tabuStats': stats == null
        ? null
        : {
            'iterations': stats.iterations,
            'maxIterations': stats.maxIterations,
            'elapsedMs': stats.elapsedMs,
            'timeBudgetMs': stats.timeBudgetMs,
            'objective': stats.objective.name,
            'initialValue': stats.initialValue,
            'bestValue': stats.bestValue,
            'stoppedByTime': stats.stoppedByTime,
          },
  };
}