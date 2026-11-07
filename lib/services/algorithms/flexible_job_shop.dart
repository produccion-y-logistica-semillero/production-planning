import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/tabu_objective.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'dart:math';

class FlexibleJobInput {
  final int jobId;
  final int dbJobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;
  final List<TaskDependencyEntity> dependencies;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  FlexibleJobInput(
    this.jobId,
    this.dbJobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.taskSequence, {
    this.dependencies = const [],
    this.interruptibleByTask = const {},
  });

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class FlexibleJobOutput {
  final int jobId;
  final int dbJobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;

  /// Processing segments per task (taskId → segments), for tasks that were
  /// preempted mid-processing.
  final Map<int, List<ProcessingSegment>> segmentsByTask;

  /// Setup/changeover segments per task (taskId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByTask;

  FlexibleJobOutput(this.jobId, this.dbJobId, this.dueDate, this.startDate,
      this.endTime, this.scheduling,
      {Map<int, List<ProcessingSegment>>? segmentsByTask,
      this.setupSegmentsByTask = const {}})
      : segmentsByTask = segmentsByTask ??
            scheduling.map((taskId, entry) => MapEntry(taskId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

/// Costo de un horario para la regla TABU: el valor del objetivo elegido y
/// el flujo total, que rompe los empates. Misma comparacion que _TabuCost en
/// parallel_machine.dart (alli es privada de esa libreria).
class _FlexibleJobTabuCost {
  /// Valor del objetivo elegido (minutos, o trabajos para Σ Uj).
  final int value;

  /// Flujo total Σ (Cj − rj) en minutos. Rompe los empates de [value].
  final int flow;

  const _FlexibleJobTabuCost(this.value, this.flow);

  int compareTo(_FlexibleJobTabuCost other) => value != other.value
      ? value.compareTo(other.value)
      : flow.compareTo(other.flow);

  bool operator <(_FlexibleJobTabuCost other) => compareTo(other) < 0;
}

/// Una operación del FJSP: la tarea [taskId] del job [job], en la posición
/// [routeIndex] de su ruta. Es la unidad que mueve el TABU: no el job
/// entero ni la estación entera, sino un paso de la ruta de un job.
class _FlexibleJobOp {
  final FlexibleJobInput job;

  /// Posición del job en inputJobs.
  final int jobIndex;
  final int taskId;
  final int routeIndex;

  /// Máquinas elegibles (las de la estación que pide la tarea) y su tiempo.
  final Map<int, Duration> durations;

  /// Clave estable para los atributos tabú: jobId.taskId.
  final String key;

  _FlexibleJobOp({
    required this.job,
    required this.jobIndex,
    required this.taskId,
    required this.routeIndex,
    required this.durations,
  }) : key = '${job.jobId}.$taskId';
}

/// Una operación ya puesta en la línea de tiempo de su máquina.
class _FlexibleJobSlot {
  final int opId;

  /// Cuándo quedó lista por su job (fin de sus predecesoras o liberación).
  /// No cambia aunque después se inserten otras operaciones en la máquina.
  final DateTime ready;
  final _FlexibleJobPlacedOp placed;

  /// dbJobId del último job con estado (A-J) en la máquina DESPUÉS de esta
  /// operación, como _machineLastJob: de él parte el setup siguiente.
  final int? lastJobAfter;

  const _FlexibleJobSlot(this.opId, this.ready, this.placed, this.lastJobAfter);

  /// Inicio efectivo: el setup si lo hay; si no, el proceso.
  DateTime get start => placed.setupSegments.isNotEmpty
      ? placed.setupSegments.first.start
      : placed.schedule.startDate;

  DateTime get end => placed.schedule.completionTime;
}

/// Estado de las máquinas durante un _decode: la línea de tiempo de cada
/// máquina (sus operaciones ordenadas por inicio). El decodificador activo
/// necesita la línea completa, no solo el fin de la última operación, para
/// buscar huecos. Las listas nunca se modifican en sitio — cada cambio
/// pone una lista nueva —, así que un checkpoint es una copia del mapa.
class _FlexibleJobDecodeState {
  final Map<int, DateTime> initialAvailability;
  final Map<int, List<_FlexibleJobSlot>> timelines;

  _FlexibleJobDecodeState(this.initialAvailability, this.timelines);

  _FlexibleJobDecodeState.initial(this.initialAvailability) : timelines = {};

  _FlexibleJobDecodeState copy() => _FlexibleJobDecodeState(
      initialAvailability, Map<int, List<_FlexibleJobSlot>>.from(timelines));

  /// Fin de la última operación de cada máquina (o su disponibilidad inicial).
  Map<int, DateTime> get machineFree => {
        ...initialAvailability,
        for (final e in timelines.entries)
          if (e.value.isNotEmpty) e.key: e.value.last.end,
      };

  /// Último job con estado en cada máquina, como _machineLastJob.
  Map<int, int?> get lastJob => {
        for (final e in timelines.entries)
          if (e.value.isNotEmpty && e.value.last.lastJobAfter != null)
            e.key: e.value.last.lastJobAfter,
      };

  /// Racha de uso continuo con que queda cada máquina.
  Map<int, Duration> get usage => {
        for (final e in timelines.entries)
          if (e.value.isNotEmpty) e.key: e.value.last.placed.usageAfter,
      };
}

/// Una operación ya decodificada en su máquina.
typedef _FlexibleJobPlacedOp = ({
  int machineId,
  List<ProcessingSegment> setupSegments,
  SegmentedSchedule schedule,
  Duration usageAfter,
});

/// Una solución del TABU FJSP: (MA, π), sus checkpoints y lo que dejó el
/// decode.

class _FlexibleJobTabuSolution {
  List<int> pi;
  List<int> ma;
  final List<_FlexibleJobDecodeState> checkpoints;
  final List<_FlexibleJobPlacedOp?> placed;
  _FlexibleJobDecodeState finalState;
  List<FlexibleJobOutput> schedule;
  _FlexibleJobTabuCost cost;

  _FlexibleJobTabuSolution.empty(int opCount)
      : pi = [],
        ma = [],
        checkpoints = [],
        placed = List<_FlexibleJobPlacedOp?>.filled(opCount, null),
        finalState = _FlexibleJobDecodeState({}, {}),
        schedule = [],
        cost = const _FlexibleJobTabuCost(0, 0);

  _FlexibleJobTabuSolution._(this.pi, this.ma, this.checkpoints, this.placed,
      this.finalState, this.schedule, this.cost);

  /// Copia de las listas; los checkpoints guardados, las operaciones
  /// decodificadas y las salidas no se modifican después de crearse.
  _FlexibleJobTabuSolution copy() => _FlexibleJobTabuSolution._(
        List<int>.from(pi),
        List<int>.from(ma),
        List<_FlexibleJobDecodeState>.from(checkpoints),
        List<_FlexibleJobPlacedOp?>.from(placed),
        finalState,
        List<FlexibleJobOutput>.from(schedule),
        cost,
      );
}

/// Lo que no cambia durante una corrida del TABU FJSP.
class _FlexibleJobTabuContext {
  final TabuObjective objective;
  final Map<int, DateTime> initialAvailability;
  final Map<int, DateTime> releaseByJob;

  /// Todas las operaciones; su índice es el opId.
  final List<_FlexibleJobOp> ops;

  /// opIds de cada job (por jobIndex), en el orden de su ruta.
  final List<List<int>> opsByJob;

  /// Precedencias directas por opId: cadena por la ruta si el job no tiene
  /// dependencies, o el DAG de dependencies (mismo criterio que
  /// _isTaskReady).
  final List<List<int>> predecessors;
  final List<List<int>> successors;

  const _FlexibleJobTabuContext({
    required this.objective,
    required this.initialAvailability,
    required this.releaseByJob,
    required this.ops,
    required this.opsByJob,
    required this.predecessors,
    required this.successors,
  });
}

/// Mejor vecino de una rama: el (MA, π) resultante, desde dónde cambia y su
/// atributo tabú.
class _FlexibleJobTabuMove {
  final bool isIntra;
  final List<int> pi;
  final List<int> ma;

  /// i_min: primera posición de π que cambia.
  final int from;

  /// Lo que se revisa en el filtro tabú: intra:(u,v) o inter:u:Mb.
  final String attribute;

  /// Se registra al aplicar: veta el movimiento inverso.
  /// intra: el mismo par (u,v). inter: inter:u:Ma (que u vuelva a su origen).
  final String tabuOnApply;
  final _FlexibleJobTabuCost cost;

  const _FlexibleJobTabuMove({
    required this.isIntra,
    required this.pi,
    required this.ma,
    required this.from,
    required this.attribute,
    required this.tabuOnApply,
    required this.cost,
  });
}

class FlexibleJobShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleJobInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
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
  /// before its first job.
  final Map<int, String> initialMachineState;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};
  List<FlexibleJobOutput> output = [];

  /// Parametros de la busqueda tabu; solo los lee la regla TABU.
  final TabuParams tabuParams;

  /// Resumen de la corrida TABU; null para las demas reglas.
  TabuRunStats? tabuStats;

  FlexibleJobShop(
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
    this.tabuParams = const TabuParams(),
  }) {
    _initializeMachineLastSequence();

    final r = rule.toUpperCase();
    switch (r) {
      case "FIFO":
        scheduleFlexibleJobShopFIFO();
        break;
      case "SPT":
        scheduleFlexibleJobShopSPT();
        break;
      case "LPT":
        scheduleFlexibleJobShopLPT();
        break;
      case "EDD":
        scheduleFlexibleJobShopEDD();
        break;
      case "WSPT":
        scheduleFlexibleJobShopWSPT();
        break;
      case "MWR":
        scheduleFlexibleJobShopMWR();
        break;
      case "LWR":
        scheduleFlexibleJobShopLWR();
        break;
      case "ATCS":
        scheduleFlexibleJobShopATCS();
        break;
      // The DB grants MS here and MINSLACK elsewhere; same rule.
      case "MINSLACK":
      case "MS":
        scheduleFlexibleJobShopMS();
        break;
      case "CR":
        scheduleFlexibleJobShopCR();
        break;
      case "GENETICS":
        scheduleFlexibleJobShopGENETICS();
        break;
      case "TABU":
        tabuSearchRule(params: tabuParams);
        break;
    }
  }

  void scheduleFlexibleJobShopGENETICS() {
    // Simple genetics-like heuristic: combine CR and WSPT into a score
    print('FlexibleJobShop: starting scheduling (GENETICS)');
    _schedule((a, b) {
      final scoreA = _geneticsScore(a.job, a.duration, a.earliestStart);
      final scoreB = _geneticsScore(b.job, b.duration, b.earliestStart);
      return scoreB.compareTo(scoreA);
    });
    print('FlexibleJobShop: scheduling finished (GENETICS)');
  }

  int _safeMinutes(Duration duration) => max(duration.inMinutes, 1);

  double _geneticsScore(
      FlexibleJobInput job, Duration duration, DateTime now) {
    final cr = _calculateCR(job, duration, now);
    final wspt = job.priority / _safeMinutes(duration);
    return (1 / max(cr, 0.0001)) + wspt;
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
  }

  Duration _getSetupDuration(
    int machineId,
    int currentJobId,
    int? previousJobId,
  ) {
    final currentJob = inputJobs.firstWhere((j) => j.jobId == currentJobId);
    final currentDbJobId = currentJob.dbJobId;

    if (stateSetupMatrix != null && jobStates != null) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        String? previousState;
        if (previousJobId != null && previousJobId > 0) {
          previousState = jobStates![previousJobId]?[machineId];
        } else {
          previousState = initialMachineState[machineId];
        }
        final currentState = jobStates![currentDbJobId]?[machineId];
        if (previousState != null && currentState != null) {
          final setupMinutes = machineStates[previousState]?[currentState];
          if (setupMinutes != null) {
            return Duration(minutes: setupMinutes);
          }
        }
      }
    }

    return Duration.zero;
  }

  // ── Static rules ──────────────────────────────────────────────────────────
  //
  // Applied queue by queue, to the operations that can start (see
  // _schedule), with the operation's NOMINAL attributes as the index: its
  // processing time on the machine chosen for it, the job's due date, or
  // when the operation arrived at the queue.
  //
  // FIFO used to compare job ids, which is the order jobs were typed in,
  // not the order they arrive.

  void scheduleFlexibleJobShopFIFO() =>
      _scheduleBy(DispatchCriterion.fifoArrival);

  void scheduleFlexibleJobShopSPT() =>
      _scheduleBy(DispatchCriterion.sptNominal);

  void scheduleFlexibleJobShopLPT() =>
      _scheduleBy(DispatchCriterion.lptNominal);

  void scheduleFlexibleJobShopEDD() => _scheduleBy(DispatchCriterion.edd);

  void scheduleFlexibleJobShopWSPT() =>
      _scheduleBy(DispatchCriterion.wsptNominal);

  // LWR / MWR: nominal work the job still has — this operation plus every
  // operation not yet completed (see _remainingWorkAfter). The previous MWR
  // counted "operations from position k of the list on", k being how many
  // the job had completed; with a precedence graph the completed ones are
  // not the first k of the list, so it added up the wrong operations.

  void scheduleFlexibleJobShopLWR() => _scheduleBy(DispatchCriterion.lwr);

  void scheduleFlexibleJobShopMWR() => _scheduleBy(DispatchCriterion.mwr);

  void scheduleFlexibleJobShopMS() => _scheduleBy(DispatchCriterion.ms);

  void scheduleFlexibleJobShopCR() => _scheduleBy(DispatchCriterion.cr);

  /// Critical ratio used only by the GENETICS score, at [now] — the
  /// schedule's clock, never the wall clock.
  double _calculateCR(FlexibleJobInput job, Duration duration, DateTime now) {
    final cr = job.dueDate.difference(now).inMinutes / _safeMinutes(duration);
    return cr < 0 ? 0 : cr;
  }

  void scheduleFlexibleJobShopATCS() => _scheduleBy(DispatchCriterion.atcs);

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
        final int cmp = compareCandidates<FlexibleJobInput>(
          criterion,
          a.dispatch as DispatchCandidate<FlexibleJobInput>,
          b.dispatch as DispatchCandidate<FlexibleJobInput>,
          // The loop only consults the rule among candidates whose
          // EFFECTIVE start coincides, so that is the shared decision time.
          decisionTime:
              (a.dispatch as DispatchCandidate<FlexibleJobInput>).start,
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
  DispatchCandidate<FlexibleJobInput> _dispatchCandidate(
    FlexibleJobInput job,
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
      FlexibleJobInput job, int taskId, Set<int> completed) {
    Duration total = Duration.zero;
    for (final task in job.taskSequence) {
      if (task.value1 == taskId || completed.contains(task.value1)) continue;
      if (task.value2.isEmpty) continue;
      total += task.value2.values.fold(Duration.zero, (sum, d) => sum + d) ~/
          task.value2.length;
    }
    return total;
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
    required FlexibleJobInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
  }) =>
      _priceOperationWith(
        job: job,
        taskId: taskId,
        machineId: machineId,
        duration: duration,
        start: start,
        previousJob: _machineLastJob[machineId],
        priorUsage: _machineContinuousUsage[machineId] ?? Duration.zero,
      );

  /// [_priceOperation] con el estado de la máquina explícito: el último job
  /// (del que parte el setup) y la racha de uso continuo. El TABU lo llama
  /// con el estado local de su decode; _priceOperation, con el de la clase.
  /// Una sola definición del costo de una operación para los dos.
  ({
    List<ProcessingSegment> setupSegments,
    SegmentedSchedule schedule,
    Duration usageAfter,
  }) _priceOperationWith({
    required FlexibleJobInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
    required int? previousJob,
    required Duration priorUsage,
  }) {
    // Setup then processing through the preemption engine. The task's
    // interruption flag governs the pair: interruptible → each may be split
    // by a shift end / maintenance / rest cap; not interruptible → one
    // contiguous block, processing starting the instant setup ends.
    final placed = _engineFor(machineId).computeSetupAndProcessing(
      earliestStart: start,
      setupDuration: _getSetupDuration(machineId, job.jobId, previousJob),
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
      for (final task in job.taskSequence) {
        final machines = task.value2;
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
          .where((job) => job.taskSequence
              .any((task) => task.value2.containsKey(machineId)))
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
      for (var task in job.taskSequence) {
        for (var duration in task.value2.values) {
          totalProcessingTime += duration.inMinutes.toDouble();
          taskCount++;
        }
      }
    }
    return taskCount > 0 ? totalProcessingTime / taskCount : 1;
  }

  bool _isTaskReady(FlexibleJobInput job, int taskId, Set<int> completed) {
    if (job.dependencies.isEmpty) {
      final idx = job.taskSequence.indexWhere((t) => t.value1 == taskId);
      if (idx > 0) {
        final predId = job.taskSequence[idx - 1].value1;
        return completed.contains(predId);
      }
      return true;
    } else {
      for (final dep in job.dependencies) {
        if (dep.successor_id == taskId) {
          if (!completed.contains(dep.predecessor_id)) {
            return false;
          }
        }
      }
      return true;
    }
  }

  DateTime _getJobReadyTime(
      FlexibleJobInput job, int taskId, Map<int, DateTime> compTimes) {
    if (job.dependencies.isEmpty) {
      final idx = job.taskSequence.indexWhere((t) => t.value1 == taskId);
      if (idx > 0) {
        final predId = job.taskSequence[idx - 1].value1;
        return compTimes[predId] ?? job.availableDate;
      }
      return job.availableDate;
    } else {
      DateTime readyTime = job.availableDate;
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

  /// Non-delay list scheduler: each round, the ready operations that can
  /// start earliest compete and [comparator] picks among them.
  ///
  /// Every contender — for every rule, static or dynamic — is priced
  /// through the preemption engine on each of its eligible machines and
  /// carried as `dispatch`. The static rules used to skip the pricing and
  /// build the conflict set from the NOMINAL start, `max(machine free, job
  /// ready)`: an operation facing a long changeover, a maintenance window or
  /// the wait for a block that fits it uninterrupted looked as if it could
  /// start right away and took the machine from one that really could.
  void _schedule(int Function(dynamic, dynamic) comparator) {
    print('FlexibleJobShop._schedule: entering main loop');

    Map<int, Set<int>> completedTasks = {
      for (var job in inputJobs) job.jobId: <int>{},
    };

    Map<int, Map<int, DateTime>> taskCompletionTimes = {
      for (var job in inputJobs) job.jobId: {},
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

    int iter = 0;
    const int maxIter = 1000000; // safety cap
    int lastCompletedCount = 0;
    int stallIterations = 0;

    while (completedTasks.entries.any((entry) {
      final job = inputJobs.firstWhere((j) => j.jobId == entry.key);
      return entry.value.length < job.taskSequence.length;
    })) {
      iter++;
      if (iter % 10000 == 0) {
        print(
            'FlexibleJobShop._schedule: iter=$iter, remainingJobs=${completedTasks.values.map((s) => s.length).join(',')}');
      }
      if (iter > maxIter) {
        print(
            'FlexibleJobShop._schedule: reached max iterations ($maxIter), aborting to avoid freeze');
        break;
      }
      final currentCompletedCount =
          completedTasks.values.fold<int>(0, (sum, set) => sum + set.length);
      if (currentCompletedCount == lastCompletedCount) {
        stallIterations += 1;
      } else {
        stallIterations = 0;
      }
      lastCompletedCount = currentCompletedCount;
      if (stallIterations > 1000) {
        print(
            'FlexibleJobShop._schedule: no progress after $stallIterations iterations, aborting to avoid freeze');
        break;
      }

      List<
          ({
            FlexibleJobInput job,
            int taskId,
            int machineId,
            Duration duration,
            DateTime earliestStart,
            DispatchCandidate<FlexibleJobInput> dispatch
          })> candidates = [];
      // First pricing failure this round, rethrown only if it leaves no
      // candidate at all — same policy as selectNext in dynamic_dispatch.dart.
      SchedulingHorizonException? pricingFailure;

      for (var job in inputJobs) {
        final completed = completedTasks[job.jobId]!;
        final compTimes = taskCompletionTimes[job.jobId]!;

        for (var task in job.taskSequence) {
          final taskId = task.value1;
          if (completed.contains(taskId)) continue;

          if (!_isTaskReady(job, taskId, completed)) continue;

          final jobReadyTime = _getJobReadyTime(job, taskId, compTimes);

          for (var entry in task.value2.entries) {
            final machineId = entry.key;
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;

            final earliestStart = machineAvailable.isAfter(jobReadyTime)
                ? machineAvailable
                : jobReadyTime;
            final adjustedStart = _adjustForWorkingSchedule(earliestStart);

            // What the operation really costs from here, priced through
            // the same code that commits it. One impossible machine must
            // not sink the operation's other options, so a failure only
            // drops this candidate.
            final DispatchCandidate<FlexibleJobInput> dispatch;
            try {
              dispatch = _dispatchCandidate(job, taskId, machineId, duration,
                  adjustedStart, completed, jobReadyTime);
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
        print(
            'FlexibleJobShop._schedule: no schedulable candidates remaining, aborting loop');
        break;
      }

      // Non-delay on the EFFECTIVE start (after the changeover's own wait,
      // maintenance, rest caps and non-interruptible waits), so an operation
      // the calendar would hold back never beats one that can really run
      // now; if nothing can start at the current instant, the clock
      // effectively jumps to the earliest effective start (Giffler &
      // Thompson 1960, non-delay).
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

      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(taskStart, adjustedEnd));
      jobSegments[selected.job.jobId]![selected.taskId] = schedule.segments;
      jobSetupSegments[selected.job.jobId]![selected.taskId] = setupSegments;

      machinesAvailability[selected.machineId] = adjustedEnd;
      _machineContinuousUsage[selected.machineId] = placed.usageAfter;
      completedTasks[selected.job.jobId]!.add(selected.taskId);
      taskCompletionTimes[selected.job.jobId]![selected.taskId] = adjustedEnd;
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
      // A job with no state (A-J) registered for this machine leaves the
      // machine in the state it found it. Recording it as the last job
      // anyway made the NEXT changeover look up a null state and cost zero.
      if (jobStates == null ||
          jobStates![selected.job.dbJobId]?[selected.machineId] != null) {
        _machineLastJob[selected.machineId] = selected.job.dbJobId;
      }
    }
    print('FlexibleJobShop._schedule: exiting main loop after iter=$iter');

    for (var job in inputJobs) {
      final sched = jobSchedulings[job.jobId]!;
      if (sched.isEmpty) continue;

      final start = sched.values.map((t) => t.value2.start).fold<DateTime?>(
          null, (a, b) => a == null ? b : (a.isBefore(b) ? a : b))!;
      final end = sched.values.map((t) => t.value2.end).fold<DateTime?>(
          null, (a, b) => a == null ? b : (a.isAfter(b) ? a : b))!;

      output.add(FlexibleJobOutput(
        job.jobId,
        job.dbJobId,
        job.dueDate,
        start,
        end,
        sched,
        segmentsByTask: jobSegments[job.jobId],
        setupSegmentsByTask: jobSetupSegments[job.jobId] ?? const {},
      ));
    }
  }

  // ── TABU: (MA, π) con decodificador activo ────────────────────────────────
  //
  // Una solución es el par (MA, π) (Brandimarte 1993; Pezzella et al. 2008):
  //   MA asigna a cada operación una máquina de SU estación (las máquinas de
  //      task.value2), y
  //   π ordena todas las operaciones respetando las precedencias de cada job.
  // _decode recorre π y pone cada operación en su máquina de MA lo antes
  // posible: en el primer hueco de la máquina donde quepa sin mover a nadie
  // (decodificador activo, ver _placeActive) o, si no hay, al final. Setup e
  // interrupciones van por el PreemptionEngine — el mismo cálculo que el
  // lazo de _schedule —. El orden de cada máquina ya no es necesariamente
  // el de π: una operación tardía en π puede quedar antes en el tiempo.
  // Dos ramas por iteración:
  //   intra (por máquina): u se queda en su máquina m y se adelanta delante
  //         de otra operación v de m → cambia la SECUENCIA de m.
  //   inter (por job): u, de uno de los jobs que más pesan en el objetivo,
  //         pasa a otra máquina Mb de su misma estación → cambia la
  //         ASIGNACIÓN.
  void tabuSearchRule({required TabuParams params}) {
    final TabuObjective objective = params.objective;
    final Random random = Random(params.seed);

    // Dos relojes, como en parallel_machine.dart: [setupWatch] mide las
    // semillas y [watch] SOLO la búsqueda; el presupuesto corre sobre [watch].
    final Stopwatch setupWatch = Stopwatch()..start();
    final Stopwatch watch = Stopwatch();

    final _FlexibleJobTabuContext ctx = _buildTabuContext(objective);
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

    // ── Semillas: correr cada regla (_resetSchedule + _scheduleBy) ─────────
    // Orden fijo: si dos semillas empatan en valor y en flujo, gana la que
    // aparece primero.
    final Map<String, void Function()> seeds = {
      'SPT': scheduleFlexibleJobShopSPT,
      'LPT': scheduleFlexibleJobShopLPT,
      'EDD': scheduleFlexibleJobShopEDD,
      'FIFO': scheduleFlexibleJobShopFIFO,
      'WSPT': scheduleFlexibleJobShopWSPT,
      'MS': scheduleFlexibleJobShopMS,
      'CR': scheduleFlexibleJobShopCR,
      'ATCS': scheduleFlexibleJobShopATCS,
      'MWR': scheduleFlexibleJobShopMWR,
    };

    _FlexibleJobTabuSolution? seedBest;
    String? seedBestName;
    // Mejor regla medida sobre su propio output, por si ninguna semilla se
    // puede convertir a (MA, π).
    String? ruleBestName;
    _FlexibleJobTabuCost? ruleBestCost;
    int seedNumber = 0;
    for (final seed in seeds.entries) {
      seedNumber++;
      _resetSchedule(ctx.initialAvailability);
      seed.value();
      final _FlexibleJobTabuCost ruleCost =
          _seedCost(objective, ctx.releaseByJob);
      if (ruleBestCost == null || ruleCost < ruleBestCost) {
        ruleBestCost = ruleCost;
        ruleBestName = seed.key;
      }

      // ── Convertir a (MA, π): inicio efectivo → pos. en ruta → jobId ──
      final encoding = _encodeSchedule(ctx);
      if (encoding == null) {
        print('[TABU FJSP semilla $seedNumber] regla=${seed.key} · '
            'horario incompleto, se descarta');
        continue;
      }

      // ── Decodificar cada semilla: _decode con estado local ──
      final _FlexibleJobTabuSolution candidate =
          _FlexibleJobTabuSolution.empty(opCount);
      candidate.cost =
          _decode(ctx, candidate, encoding.pi, encoding.ma, 0, save: true);
      final String mismatch = candidate.cost.compareTo(ruleCost) == 0
          ? ''
          : ' · AVISO: la regla daba ${ruleCost.value}';
      print('[TABU FJSP semilla $seedNumber] regla=${seed.key} · '
          '${objective.label}=${candidate.cost.value} ${objective.unit} '
          '(flujo ${candidate.cost.flow} min)$mismatch');
      if (seedBest == null || candidate.cost < seedBest.cost) {
        seedBest = candidate;
        seedBestName = seed.key;
      }
    }

    // Sin semilla convertible (alguna regla dejó operaciones sin programar):
    // se comporta como la fase 1 y deja el horario de la mejor regla.
    if (seedBest == null) {
      _resetSchedule(ctx.initialAvailability);
      seeds[ruleBestName!]!();
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
      print('[TABU FJSP] ninguna semilla completa: se deja $ruleBestName');
      return;
    }

    // ── Mejor semilla: current = best, guardar checkpoints ─────────────────
    _FlexibleJobTabuSolution best = seedBest;
    _FlexibleJobTabuSolution current = best.copy();
    final _FlexibleJobTabuCost initialCost = best.cost;

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

      final _FlexibleJobTabuMove? intraMove = _bestIntraMove(
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
      final _FlexibleJobTabuMove? interMove = _bestInterMove(
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
      _FlexibleJobTabuMove? chosen;
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
        tabuList[chosen.tabuOnApply] = iter + tenure;
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
        final _FlexibleJobTabuSolution restarted =
            _FlexibleJobTabuSolution.empty(opCount);
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
    final _FlexibleJobTabuCost committed = _commitTabuSolution(ctx, best);
    if (committed.compareTo(best.cost) != 0) {
      print('[TABU FJSP] AVISO: el horario comiteado '
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
    print('[TABU FJSP] jobs=${inputJobs.length} · operaciones=$opCount · '
        'semilla ganadora=$seedBestName · iteraciones=$iter/$maxIterations · '
        'semillas ${setupWatch.elapsedMilliseconds} ms · '
        'busqueda ${watch.elapsedMilliseconds} ms');
    print('[TABU FJSP] ${objective.label}: ${initialCost.value} → '
        '${best.cost.value} ${objective.unit} ($mejora% de mejora) · '
        'flujo total: ${initialCost.flow} → ${best.cost.flow} min');
  }

  /// Deja el horario como estaba al terminar el constructor y antes de
  /// correr cualquier regla, para que cada semilla del TABU arranque del
  /// mismo punto. _engineByMachine se conserva: solo guarda la
  /// configuracion del calendario de cada maquina.
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
  /// parallel_machine.dart. Cj es el fin de la ultima operacion del job.
  _FlexibleJobTabuCost _seedCost(
    TabuObjective objective,
    Map<int, DateTime> releaseByJob, [
    List<FlexibleJobOutput>? schedule,
  ]) {
    Duration flow = Duration.zero;
    Duration tardiness = Duration.zero;
    int tardyJobs = 0;
    DateTime lastEnd = startDate;
    for (final out in schedule ?? output) {
      final DateTime release = releaseByJob[out.jobId] ?? startDate;
      flow += out.endTime.difference(release); // C_j − r_j
      if (out.endTime.isAfter(out.dueDate)) {
        tardiness += out.endTime.difference(out.dueDate); // max(0, C_j − d_j)
        tardyJobs++; // U_j
      }
      if (out.endTime.isAfter(lastEnd)) lastEnd = out.endTime; // C_max
    }
    final int flowMinutes = flow.inMinutes;
    final int value = switch (objective) {
      TabuObjective.totalFlow => flowMinutes,
      TabuObjective.makespan => lastEnd.difference(startDate).inMinutes,
      TabuObjective.totalTardiness => tardiness.inMinutes,
      TabuObjective.tardyJobs => tardyJobs,
    };
    return _FlexibleJobTabuCost(value, flowMinutes);
  }

  // ── TABU FJSP: codificación (MA, π) ───────────────────────────────────────

  /// Operaciones, precedencias y datos fijos de la corrida.
  _FlexibleJobTabuContext _buildTabuContext(TabuObjective objective) {
    final List<_FlexibleJobOp> ops = [];
    final List<List<int>> opsByJob = [];
    for (int j = 0; j < inputJobs.length; j++) {
      final FlexibleJobInput job = inputJobs[j];
      final List<int> ids = [];
      for (int r = 0; r < job.taskSequence.length; r++) {
        ids.add(ops.length);
        ops.add(_FlexibleJobOp(
          job: job,
          jobIndex: j,
          taskId: job.taskSequence[r].value1,
          routeIndex: r,
          durations: job.taskSequence[r].value2,
        ));
      }
      opsByJob.add(ids);
    }

    final List<List<int>> predecessors = List.generate(ops.length, (_) => []);
    final List<List<int>> successors = List.generate(ops.length, (_) => []);
    for (int j = 0; j < inputJobs.length; j++) {
      final FlexibleJobInput job = inputJobs[j];
      final List<int> ids = opsByJob[j];
      if (job.dependencies.isEmpty) {
        for (int r = 1; r < ids.length; r++) {
          predecessors[ids[r]].add(ids[r - 1]);
          successors[ids[r - 1]].add(ids[r]);
        }
      } else {
        final Map<int, int> opOfTask = {
          for (final id in ids) ops[id].taskId: id,
        };
        for (final dep in job.dependencies) {
          final int? succ = opOfTask[dep.successor_id];
          final int? pred = opOfTask[dep.predecessor_id];
          if (succ == null || pred == null) continue;
          predecessors[succ].add(pred);
          successors[pred].add(succ);
        }
      }
    }

    return _FlexibleJobTabuContext(
      objective: objective,
      initialAvailability: Map<int, DateTime>.from(machinesAvailability),
      releaseByJob: {
        for (final job in inputJobs) job.jobId: job.availableDate,
      },
      ops: ops,
      opsByJob: opsByJob,
      predecessors: predecessors,
      successors: successors,
    );
  }

  /// Convierte el horario que dejó una regla en [output] a (MA, π):
  /// MA = la máquina de cada operación; π = las operaciones ordenadas por
  /// inicio efectivo (setup incluido), luego posición en la ruta, luego
  /// jobId. null si a la regla le faltó programar alguna operación.
  ({List<int> pi, List<int> ma})? _encodeSchedule(_FlexibleJobTabuContext ctx) {
    final Map<int, FlexibleJobOutput> outputByJob = {
      for (final out in output) out.jobId: out,
    };
    final int n = ctx.ops.length;
    final List<int> ma = List<int>.filled(n, -1);
    final List<DateTime> effectiveStart = List<DateTime>.filled(n, startDate);
    for (int opId = 0; opId < n; opId++) {
      final _FlexibleJobOp op = ctx.ops[opId];
      final FlexibleJobOutput? out = outputByJob[op.job.jobId];
      final Tuple2<int, Range>? entry = out?.scheduling[op.taskId];
      if (entry == null) return null;
      ma[opId] = entry.value1;
      final List<ProcessingSegment> setups =
          out!.setupSegmentsByTask[op.taskId] ?? const [];
      effectiveStart[opId] =
          setups.isNotEmpty ? setups.first.start : entry.value2.startDate;
    }

    final List<int> order = List<int>.generate(n, (k) => k)
      ..sort((a, b) {
        int cmp = effectiveStart[a].compareTo(effectiveStart[b]);
        if (cmp != 0) return cmp;
        cmp = ctx.ops[a].routeIndex.compareTo(ctx.ops[b].routeIndex);
        if (cmp != 0) return cmp;
        cmp = ctx.ops[a].job.jobId.compareTo(ctx.ops[b].job.jobId);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
    return (pi: _respectPrecedence(ctx, order), ma: ma);
  }

  /// Orden topológico estable: conserva [order] salvo que una operación
  /// aparezca antes que una predecesora (solo posible con duraciones cero o
  /// una ruta cuyo orden de lista no sigue las flechas).
  List<int> _respectPrecedence(_FlexibleJobTabuContext ctx, List<int> order) {
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
  /// ventana mantiene π factible.
  (int, int) _windowWithout(
      _FlexibleJobTabuContext ctx, List<int> pos, int u, int length) {
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

  // ── TABU FJSP: decodificador ──────────────────────────────────────────────

  /// Decodifica (MA, π) = ([ma], [pi]) y devuelve su costo (objetivo, flujo).
  ///
  /// [from] = i_min: π[0..from−1] y sus máquinas deben coincidir con [base];
  /// se restaura base.checkpoints[from] y solo se decodifica el sufijo.
  ///
  /// Cada operación va al primer hueco de su máquina donde quepa desde que
  /// su job está listo, o al final (_placeActive), y se precia con
  /// _priceOperationWith: el mismo cálculo que el lazo de _schedule, sobre
  /// un _FlexibleJobDecodeState local.
  ///
  /// save: false → no toca [base] (evaluar un vecino).
  /// save: true  → [base] pasa a ser (MA, π) con sus checkpoints nuevos.
  _FlexibleJobTabuCost _decode(
    _FlexibleJobTabuContext ctx,
    _FlexibleJobTabuSolution base,
    List<int> pi,
    List<int> ma,
    int from, {
    required bool save,
  }) {
    final int n = pi.length;

    // ── Restaurar checkpoint[i_min] ──
    final _FlexibleJobDecodeState state = from == 0
        ? _FlexibleJobDecodeState.initial(ctx.initialAvailability)
        : base.checkpoints[from].copy();

    // Fin de cada operación ya puesta, por job y tarea, para el
    // _getJobReadyTime de las del sufijo. Sale de las líneas de tiempo del
    // checkpoint: una inserción nunca mueve un proceso ya puesto, solo
    // puede cambiar su setup (ver _placeActive).
    final List<Map<int, DateTime>> completion =
        List.generate(ctx.opsByJob.length, (_) => <int, DateTime>{});
    for (final line in state.timelines.values) {
      for (final slot in line) {
        final _FlexibleJobOp op = ctx.ops[slot.opId];
        completion[op.jobIndex][op.taskId] = slot.end;
      }
    }

    if (save) base.checkpoints.removeRange(from, base.checkpoints.length);

    // ── Decodificar el sufijo ──
    for (int k = from; k < n; k++) {
      if (save) base.checkpoints.add(state.copy());
      final int opId = pi[k];
      final _FlexibleJobOp op = ctx.ops[opId];

      final DateTime jobReady =
          _getJobReadyTime(op.job, op.taskId, completion[op.jobIndex]);
      final _FlexibleJobSlot slot =
          _placeActive(ctx, state, opId, ma[opId], jobReady);
      completion[op.jobIndex][op.taskId] = slot.end;
    }

    // placed sale de las líneas de tiempo finales: así lleva también los
    // setups que una inserción recalculó en operaciones del prefijo.
    final List<_FlexibleJobPlacedOp?> placed = save
        ? base.placed
        : List<_FlexibleJobPlacedOp?>.filled(ctx.ops.length, null);
    for (final line in state.timelines.values) {
      for (final slot in line) {
        placed[slot.opId] = slot.placed;
      }
    }

    final List<FlexibleJobOutput> schedule = _tabuSchedule(ctx, placed);
    final _FlexibleJobTabuCost cost =
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

  /// Pone la operación [opId] en [machineId] de forma ACTIVA: en el primer
  /// hueco de la línea de tiempo de la máquina donde quepa desde [ready]
  /// sin mover el proceso de ninguna operación ya puesta; si no cabe en
  /// ningún hueco, al final, como el decodificador semi-activo.
  ///
  /// Con setups dependientes de la secuencia, meter u entre a y b cambia el
  /// setup de b (ahora parte del estado de u). Por eso un hueco se valida
  /// re-preciando con el mismo motor las operaciones que siguen en la
  /// máquina: sirve solo si todas conservan exactamente su proceso (inicio,
  /// fin y cortes). Como ningún proceso ya puesto se mueve, las demás
  /// máquinas y los fines que leen las sucesoras de cada job siguen valiendo.
  _FlexibleJobSlot _placeActive(
    _FlexibleJobTabuContext ctx,
    _FlexibleJobDecodeState state,
    int opId,
    int machineId,
    DateTime ready,
  ) {
    final _FlexibleJobOp op = ctx.ops[opId];
    final Duration duration = op.durations[machineId]!;
    final List<_FlexibleJobSlot> line =
        state.timelines[machineId] ?? const <_FlexibleJobSlot>[];
    final DateTime initialFree =
        state.initialAvailability[machineId] ?? startDate;

    // ── Huecos: antes de la primera operación y entre cada par ──
    for (int i = 0; i < line.length; i++) {
      final _FlexibleJobSlot? prev = i == 0 ? null : line[i - 1];
      final DateTime gapStart = prev?.end ?? initialFree;
      final DateTime earliest = ready.isAfter(gapStart) ? ready : gapStart;
      // Poda barata: si ni el proceso solo cabe antes de que empiece el
      // proceso de line[i], no vale la pena preciar.
      if (earliest.add(duration).isAfter(line[i].placed.schedule.startDate)) {
        continue;
      }
      final List<_FlexibleJobSlot>? inserted =
          _tryInsert(ctx, line, i, op, opId, machineId, duration, ready, earliest);
      if (inserted != null) {
        state.timelines[machineId] = inserted;
        return inserted[i];
      }
    }

    // ── Sin hueco: al final de la máquina ──
    final _FlexibleJobSlot? last = line.isEmpty ? null : line.last;
    final DateTime freeAt = last?.end ?? initialFree;
    final DateTime earliest = ready.isAfter(freeAt) ? ready : freeAt;
    final _FlexibleJobSlot slot =
        _priceSlot(op, opId, machineId, duration, ready, earliest, last);
    state.timelines[machineId] = [...line, slot];
    return slot;
  }

  /// Intenta meter [op] en el hueco [i] de [line] (justo antes de line[i]).
  /// Devuelve la línea nueva, o null si no cabe o si alguna operación
  /// siguiente cambiaría su proceso.
  List<_FlexibleJobSlot>? _tryInsert(
    _FlexibleJobTabuContext ctx,
    List<_FlexibleJobSlot> line,
    int i,
    _FlexibleJobOp op,
    int opId,
    int machineId,
    Duration duration,
    DateTime ready,
    DateTime earliest,
  ) {
    final _FlexibleJobSlot? prev = i == 0 ? null : line[i - 1];
    final _FlexibleJobSlot slot;
    try {
      slot = _priceSlot(op, opId, machineId, duration, ready, earliest, prev);
    } on SchedulingHorizonException {
      return null;
    }
    if (slot.end.isAfter(line[i].placed.schedule.startDate)) return null;

    // La racha de uso continuo solo cambia tiempos si la máquina tiene tope.
    final bool usageMatters =
        _engineFor(machineId).continuousUseCap > Duration.zero;

    final List<_FlexibleJobSlot> result = [...line.sublist(0, i), slot];
    _FlexibleJobSlot before = slot;
    for (int j = i; j < line.length; j++) {
      // Si line[j] ya llega con el mismo estado que antes (mismo último job
      // con estado y, si importa, misma racha), de ahí en adelante nada
      // cambia: se copia el resto tal cual.
      if (j > i &&
          before.lastJobAfter == line[j - 1].lastJobAfter &&
          (!usageMatters ||
              before.placed.usageAfter == line[j - 1].placed.usageAfter)) {
        result.addAll(line.sublist(j));
        return result;
      }
      final _FlexibleJobSlot old = line[j];
      final _FlexibleJobOp oldOp = ctx.ops[old.opId];
      final _FlexibleJobSlot repriced;
      try {
        repriced = _priceSlot(
          oldOp,
          old.opId,
          machineId,
          oldOp.durations[machineId]!,
          old.ready,
          old.ready.isAfter(before.end) ? old.ready : before.end,
          before,
        );
      } on SchedulingHorizonException {
        return null;
      }
      // Su proceso tiene que quedar idéntico; si no, el hueco no sirve.
      if (!_sameProcessing(repriced.placed.schedule, old.placed.schedule)) {
        return null;
      }
      result.add(repriced);
      before = repriced;
    }
    return result;
  }

  /// Precia [op] en [machineId] desde [earliest] (ajustado al turno), con el
  /// estado que dejó [prev] en la máquina (null = la máquina sin usar).
  _FlexibleJobSlot _priceSlot(
    _FlexibleJobOp op,
    int opId,
    int machineId,
    Duration duration,
    DateTime ready,
    DateTime earliest,
    _FlexibleJobSlot? prev,
  ) {
    final result = _priceOperationWith(
      job: op.job,
      taskId: op.taskId,
      machineId: machineId,
      duration: duration,
      start: _adjustForWorkingSchedule(earliest),
      previousJob: prev?.lastJobAfter,
      priorUsage: prev?.placed.usageAfter ?? Duration.zero,
    );
    // Igual que _schedule: un job sin estado en esta máquina la deja en el
    // estado en que la encontró.
    final bool hasState =
        jobStates == null || jobStates![op.job.dbJobId]?[machineId] != null;
    return _FlexibleJobSlot(
      opId,
      ready,
      (
        machineId: machineId,
        setupSegments: result.setupSegments,
        schedule: result.schedule,
        usageAfter: result.usageAfter,
      ),
      hasState ? op.job.dbJobId : prev?.lastJobAfter,
    );
  }

  /// Mismo proceso: mismos cortes, con el mismo inicio y fin cada uno.
  static bool _sameProcessing(SegmentedSchedule a, SegmentedSchedule b) {
    if (a.segments.length != b.segments.length) return false;
    for (int s = 0; s < a.segments.length; s++) {
      if (!a.segments[s].start.isAtSameMomentAs(b.segments[s].start) ||
          !a.segments[s].end.isAtSameMomentAs(b.segments[s].end)) {
        return false;
      }
    }
    return true;
  }

  /// Arma el output de un decode con el mismo formato que _schedule: un
  /// FlexibleJobOutput por job, inicio = menor inicio de procesamiento y
  /// fin = mayor fin de sus operaciones.
  List<FlexibleJobOutput> _tabuSchedule(
    _FlexibleJobTabuContext ctx,
    List<_FlexibleJobPlacedOp?> placed,
  ) {
    final List<FlexibleJobOutput> result = [];
    for (int j = 0; j < inputJobs.length; j++) {
      final FlexibleJobInput job = inputJobs[j];
      final Map<int, Tuple2<int, Range>> sched = {};
      final Map<int, List<ProcessingSegment>> segments = {};
      final Map<int, List<ProcessingSegment>> setups = {};
      for (final int opId in ctx.opsByJob[j]) {
        final _FlexibleJobPlacedOp? p = placed[opId];
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
      result.add(FlexibleJobOutput(
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
  _FlexibleJobTabuCost _commitTabuSolution(
    _FlexibleJobTabuContext ctx,
    _FlexibleJobTabuSolution solution,
  ) {
    final _FlexibleJobTabuCost cost =
        _decode(ctx, solution, solution.pi, solution.ma, 0, save: true);
    _resetSchedule(ctx.initialAvailability);
    machinesAvailability.addAll(solution.finalState.machineFree);
    _machineLastJob.addAll(solution.finalState.lastJob);
    _machineContinuousUsage.addAll(solution.finalState.usage);
    // Última operación de cada máquina en el TIEMPO (con el decodificador
    // activo ya no es necesariamente la última en π).
    for (final entry in solution.finalState.timelines.entries) {
      if (entry.value.isEmpty) continue;
      _machineLastSequence[entry.key] =
          ctx.ops[entry.value.last.opId].job.sequenceId;
    }
    output.addAll(solution.schedule);
    return cost;
  }

  // ── TABU FJSP: vecindarios ────────────────────────────────────────────────

  /// Rama intra — por MÁQUINA, primera mejora.
  ///
  /// Toma hasta [maxAttempts] operaciones u al azar (solo cuentan las que
  /// tienen algún hueco) y, dentro de su ventana, prueba adelantar u justo
  /// delante de otra operación v de SU máquina m, de la más cercana a la más
  /// lejana. Con el decodificador activo, un cambio en π puede no cambiar el
  /// horario (vecino con el mismo costo que current); se evalúa igual.
  /// Devuelve el primero admisible que mejora current; si ninguno mejora,
  /// el menos malo admisible (puede empeorar: así intra también sale de un
  /// óptimo local).
  _FlexibleJobTabuMove? _bestIntraMove({
    required _FlexibleJobTabuContext ctx,
    required _FlexibleJobTabuSolution current,
    required List<int> pos,
    required Map<String, int> tabuList,
    required int iter,
    required _FlexibleJobTabuCost bestCost,
    required Random random,
    required int maxAttempts,
    required bool Function() timeUp,
  }) {
    final List<int> pi = current.pi;
    final List<int> ma = current.ma;
    final List<int> order = List<int>.from(pi)..shuffle(random);

    // Mejor vecino admisible que NO mejora a current: se devuelve solo si
    // ningún intento mejora.
    _FlexibleJobTabuMove? bestNonImproving;

    int attempts = 0;
    for (final int u in order) {
      if (attempts >= maxAttempts) break;
      final int m = ma[u];
      final int pu = pos[u];
      int lo = 0;
      for (final p in ctx.predecessors[u]) {
        lo = max(lo, pos[p] + 1);
      }

      bool counted = false;
      for (int k = pu - 1; k >= lo; k--) {
        final int v = pi[k];
        if (ma[v] != m) continue;
        if (!counted) {
          counted = true;
          attempts++;
        }
        if (timeUp()) return bestNonImproving;

        final List<int> trial = List<int>.from(pi)
          ..removeAt(pu)
          ..insert(k, u);
        final _FlexibleJobTabuCost cost;
        try {
          cost = _decode(ctx, current, trial, ma, k, save: false);
        } on SchedulingHorizonException {
          continue; // no cabe en el calendario: vecino no factible
        }
        final String attribute = _intraAttribute(ctx, u, v);
        final bool isTabu = (tabuList[attribute] ?? -1) > iter;
        final bool aspiration = cost < bestCost;
        if (isTabu && !aspiration) continue;

        final _FlexibleJobTabuMove move = _FlexibleJobTabuMove(
          isIntra: true,
          pi: trial,
          ma: ma,
          from: k,
          attribute: attribute,
          tabuOnApply: attribute,
          cost: cost,
        );

        // Primera mejora: el primero que supera a current se devuelve ya.
        if (cost < current.cost) return move;

        // No mejora: se guarda si es el menos malo hasta ahora.
        if (bestNonImproving == null || cost < bestNonImproving.cost) {
          bestNonImproving = move;
        }
      }
    }
    return bestNonImproving; // null si todos los intentos eran tabú o infactibles
  }

  /// Rama inter — por JOB, mejor mejora.
  ///
  /// Ordena las operaciones flexibles (más de una máquina en su estación)
  /// por el aporte de su job al objetivo (desempate: flujo del job y fin de
  /// la operación) y toma hasta [samples]. Para cada u prueba hasta
  /// [maxDestinations] máquinas Mb de su misma estación, las que terminan
  /// antes, y en cada Mb los k+1 huecos que dejan sus k operaciones dentro
  /// de la ventana de u. Devuelve el mejor admisible.
  _FlexibleJobTabuMove? _bestInterMove({
    required _FlexibleJobTabuContext ctx,
    required _FlexibleJobTabuSolution current,
    required List<int> pos,
    required Map<String, int> tabuList,
    required int iter,
    required _FlexibleJobTabuCost bestCost,
    required int samples,
    required int maxDestinations,
    required bool Function() timeUp,
  }) {
    final List<int> pi = current.pi;
    final List<int> ma = current.ma;

    // ── Elegir u por peso: aporte del job al objetivo ──
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

    // Fin de cada máquina, calculado una vez (machineFree arma un mapa).
    final Map<int, DateTime> machineFree = current.finalState.machineFree;

    _FlexibleJobTabuMove? bestMove;
    for (final int u in flexible.take(samples)) {
      final int machineFrom = ma[u];
      final int pu = pos[u];

      // ── Destinos Mb elegibles: menor fin, hasta maxDestinations ──
      final List<int> destinations = ctx.ops[u].durations.keys
          .where((m) => m != machineFrom)
          .toList()
        ..sort((a, b) {
          final int cmp = (machineFree[a] ?? startDate)
              .compareTo(machineFree[b] ?? startDate);
          return cmp != 0 ? cmp : a.compareTo(b);
        });

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
          // Dentro del hueco, la posición más cercana a la original: misma
          // secuencia en Mb y el i_min más alto posible.
          final int insertAt = pu.clamp(gapLo, gapHi);
          final List<int> trialPi = List<int>.from(without)..insert(insertAt, u);
          final List<int> trialMa = List<int>.from(ma)..[u] = machineTo;
          final int from = min(pu, insertAt);

          final _FlexibleJobTabuCost cost;
          try {
            cost = _decode(ctx, current, trialPi, trialMa, from, save: false);
          } on SchedulingHorizonException {
            continue; // no cabe en el calendario: vecino no factible
          }

          final String attribute = 'inter:${ctx.ops[u].key}:$machineTo'; // llevar u a machineTo
          final String tabuOnApply = 'inter:${ctx.ops[u].key}:$machineFrom'; // al aplicar: vetar que regrese
          final bool isTabu = (tabuList[attribute] ?? -1) > iter;
          final bool aspiration = cost < bestCost;
          if (isTabu && !aspiration) continue;

          if (bestMove == null || cost < bestMove.cost) {
            bestMove = _FlexibleJobTabuMove(
              isIntra: false,
              pi: trialPi,
              ma: trialMa,
              from: from,
              attribute: attribute,
              tabuOnApply: tabuOnApply,
              cost: cost,
            );
          }
        }
      }
    }
    return bestMove;
  }

  /// Atributo intra (u, v), sin orden.
  String _intraAttribute(_FlexibleJobTabuContext ctx, int u, int v) {
    final String a = ctx.ops[u].key;
    final String b = ctx.ops[v].key;
    return a.compareTo(b) < 0 ? 'intra:${a}_$b' : 'intra:${b}_$a';
  }

  /// Diversificación: [steps] movimientos aleatorios sobre best. Cada uno
  /// saca una operación, le sortea una máquina de su estación y la vuelve a
  /// poner en una posición al azar de su ventana.
  ({List<int> pi, List<int> ma}) _perturbEncoding(
    _FlexibleJobTabuContext ctx,
    _FlexibleJobTabuSolution best,
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

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour,
          workingStart.minute);
    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour,
          workingStart.minute);
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
        start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1,
              workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }
    return end;
  }

  int calcularCmax(List<FlexibleJobOutput> output) {
    if (output.isEmpty) return 0;
    final startTimes = output.map((job) => job.startDate).toList();
    final endTimes = output.map((job) => job.endTime).toList();

    final earliestStart = startTimes.fold<DateTime>(
        startTimes.first, (a, b) => a.isBefore(b) ? a : b);
    final latestEnd =
        endTimes.fold<DateTime>(endTimes.first, (a, b) => a.isAfter(b) ? a : b);

    final duration = latestEnd.difference(earliestStart);
    return duration.inHours;
  }
}

/// Punto de entrada del isolate. Devuelve {'output': [...], 'tabuStats':
/// {...} | null}: el horario y, si la regla fue TABU, su resumen, ambos en
/// primitivos como el payload.
Map<String, dynamic> flexibleJobShopSchedule(
    Map<String, dynamic> payload) {
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

  final inputJobs = (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jobMap = Map<String, dynamic>.from(jobData as Map);
    final Map<int, bool> interruptibleByTask = {};
    final taskSequence =
        (jobMap['taskSequence'] as List<dynamic>).map((taskData) {
      final taskMap = Map<String, dynamic>.from(taskData as Map);
      final durations =
          (taskMap['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) =>
            MapEntry(key as int, Duration(milliseconds: value as int)),
      );
      final taskId = taskMap['taskId'] as int;
      interruptibleByTask[taskId] = (taskMap['interruptible'] as bool?) ?? true;
      return Tuple2(taskId, durations);
    }).toList();

    final dependencies = (jobMap['dependencies'] as List<dynamic>)
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

    return FlexibleJobInput(
      jobMap['jobId'] as int,
      jobMap['dbJobId'] as int,
      jobMap['sequenceId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
      jobMap['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['availableDate'] as int),
      taskSequence,
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

  final FlexibleJobShop flexible = FlexibleJobShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    initialMachineState: initialMachineState,
    tabuParams: tabuParams,
  );
  final output = flexible.output;
  final TabuRunStats? stats = flexible.tabuStats;

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