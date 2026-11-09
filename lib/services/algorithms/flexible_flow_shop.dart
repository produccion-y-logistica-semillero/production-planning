import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/genetic_engine.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/services/scheduling/schedule_objective_value.dart';
import 'package:production_planning/services/scheduling/user_sequence.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';
import  'package:production_planning/entities/tabu_objective.dart';
import 'package:production_planning/entities/tabu_params.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';

class FlexibleFlowInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //tuple2 <task id, Map<machineId, Duration of task in machine>>
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  FlexibleFlowInput(this.jobId, this.dueDate, this.priority, this.availableDate,
      this.taskSequence,
      {this.interruptibleByTask = const {}});

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class FlexibleFlowOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //map<task id, tuple2<machineId, range scheuled>>
  final Map<int, Tuple2<int, Range>> scheduling;

  /// Processing segments per station (stationId → segments), for tasks that
  /// were preempted mid-processing.
  final Map<int, List<ProcessingSegment>> segmentsByStation;

  /// Setup/changeover segments per station (stationId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByStation;

  FlexibleFlowOutput(
      this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling,
      {Map<int, List<ProcessingSegment>>? segmentsByStation,
      this.setupSegmentsByStation = const {}})
      : segmentsByStation = segmentsByStation ??
            scheduling.map((stationId, entry) => MapEntry(
                stationId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

/// One task priced on one machine, not yet committed.
class _FlexibleFlowTask {
  final int machineId;
  final List<ProcessingSegment> setupSegments;
  final SegmentedSchedule schedule;

  /// The machine's continuous-use streak once this task is done.
  final Duration continuousUsageAfter;

  const _FlexibleFlowTask({
    required this.machineId,
    required this.setupSegments,
    required this.schedule,
    required this.continuousUsageAfter,
  });

  /// When the machine starts working: setup if there is one, else processing.
  DateTime get start =>
      setupSegments.isNotEmpty ? setupSegments.first.start : schedule.startDate;
}

/// A whole job's route through the stations, priced but not committed.
///
/// The two `*After` maps hold the per-machine state the route would leave
/// behind, applied only by `FlexibleFlowShop._commitPlacement`.
class _FlexibleFlowPlacement {
  final FlexibleFlowInput job;
  final DateTime startTime;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;
  final Map<int, List<ProcessingSegment>> segmentsByStation;
  final Map<int, List<ProcessingSegment>> setupSegmentsByStation;
  final Map<int, DateTime> availabilityAfter;
  final Map<int, Duration> continuousUsageAfter;

  const _FlexibleFlowPlacement({
    required this.job,
    required this.startTime,
    required this.endTime,
    required this.scheduling,
    required this.segmentsByStation,
    required this.setupSegmentsByStation,
    required this.availabilityAfter,
    required this.continuousUsageAfter,
  });
}



// Flexibilizar la operacion 
class _FlexibleFlowTabuCost {
  final int value;

  final int flow;

  const _FlexibleFlowTabuCost(this.value, this.flow);

  int compareTo(_FlexibleFlowTabuCost other) => value != other.value
      ? value.compareTo(other.value)
      : flow.compareTo(other.flow);

  bool operator <(_FlexibleFlowTabuCost other) => compareTo(other) < 0;
}

class _Station1Photo {
  final Map<int, DateTime> availability;
  final Map<int, int?> lastJob;
  final Map<int, Duration> continuousUsage;

  const _Station1Photo({
    required this.availability,
    required this.lastJob,
    required this.continuousUsage,
  });
}

/// Una solución del TABU FFS: la permutación π que manda en la estación 1,
/// la foto y la tarea de estación 1 de cada posición, y su costo.
///
/// photos[k] y station1Tasks[k] solo dependen de π[0..k], por eso siguen
/// valiendo para cualquier vecino que comparta ese prefijo.
class _FlexibleFlowTabuSolution {
  final List<FlexibleFlowInput> permutation;
  final List<_Station1Photo> photos;
  final List<_FlexibleFlowTask?> station1Tasks;
  _FlexibleFlowTabuCost cost;

  _FlexibleFlowTabuSolution()
      : permutation = [],
        photos = [],
        station1Tasks = [],
        cost = const _FlexibleFlowTabuCost(0, 0);

  _FlexibleFlowTabuSolution._(
      this.permutation, this.photos, this.station1Tasks, this.cost);

  /// Copia de las listas las fotos y las tareas son inmutables.
  _FlexibleFlowTabuSolution copy() => _FlexibleFlowTabuSolution._(
        List<FlexibleFlowInput>.from(permutation),
        List<_Station1Photo>.from(photos),
        List<_FlexibleFlowTask?>.from(station1Tasks),
        cost,
      );
}

/// Lo que no cambia durante una corrida del TABU FFS y el decodificador
/// necesita en cada llamada.
class _FlexibleFlowTabuContext {
  final TabuObjective objective;

  /// Disponibilidad de las máquinas antes de cualquier regla.
  final Map<int, DateTime> initialAvailability;

  /// r_j de cada trabajo, para el flujo C_j − r_j.
  final Map<int, DateTime> releaseByJob;

  /// Máquinas de la estación 1 (las únicas que guarda una foto).
  final Set<int> station1Machines;

  const _FlexibleFlowTabuContext({
    required this.objective,
    required this.initialAvailability,
    required this.releaseByJob,
    required this.station1Machines,
  });
}

/// Mejor vecino admisible de una rama (insert o swap).
class _FlexibleFlowTabuMove {
  final bool isInsert;

  /// π' completa.
  final List<FlexibleFlowInput> permutation;

  /// min(a, b): primera posición que cambia respecto a current.
  final int from;

  /// Atributo que se revisa en el filtro tabú: el par que el movimiento
  /// CREA. Insert: par:(J, nuevo vecino); swap: par:(Ja, Jb). Al aplicar
  /// el movimiento también se registra.
  final String attribute;

  /// Segundo atributo que se registra al aplicar el movimiento: el par que
  /// DESTRUYE. Insert: par:(J, vecino original); swap: el mismo par:(Ja, Jb).
  ///
  /// Hacen falta los dos para vetar el inverso de un insert:
  /// - no adyacente: solo J puede deshacerlo, y al volver crea
  ///   (J, vecino original) → lo veta [tabuOnApply];
  /// - adyacente ([P, J, X] → [P, X, J]): lo deshace X (J hacia atrás se
  ///   salta por b == a−1), y X crea (X, J) → lo veta [attribute].
  final String tabuOnApply;

  final _FlexibleFlowTabuCost cost;

  const _FlexibleFlowTabuMove({
    required this.isInsert,
    required this.permutation,
    required this.from,
    required this.attribute,
    required this.tabuOnApply,
    required this.cost,
  });
}

class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleFlowInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  List<FlexibleFlowOutput> output = [];
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job.
  final Map<int, String> initialMachineState;
  final Map<int, int?> _machineLastJob = {};

  // Machine inactivity support.
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};
  final TabuParams tabuParams ;
  TabuRunStats? tabuStats;


  /// Settings and objective of GENETICS, chosen in the algorithm picker.
  final GeneticParams geneticParams;

  /// Job ids in the order the user chose (rule SECUENCIA_USUARIO).
  final List<int>? userSequence;

  FlexibleFlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.stateSetupMatrix,
    this.jobStates,
    this.initialMachineState = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
    this.geneticParams = const GeneticParams(),
    this.userSequence,
    this.tabuParams = const TabuParams(),
  }) {
    final r = rule.toUpperCase();
    switch (r) {
      case "EDD":
        eddRule();
        break;
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "FIFO":
        fifoRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "MS":
        msRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "LWR":
        lwrRule();
        break;
      case "MWR":
        mwrRule();
        break;
      case "JOHNSON":
        _applyJohnsonRuleFlexible(inputJobs);
        break;

      case "CDS":
        cdsAlgorithm();
        break;
      // Composite priority score ((w + 1) / total route time). It used to be
      // offered as "GENETICS", but it is a static order, not a genetic
      // algorithm.
      case "PRIORIDAD_COMPUESTA":
        _schedule((a, b) {
          final scoreA = (a.priority / max(1, _totalProcessingTime(a))) + (1 / max(1, _totalProcessingTime(a)));
          final scoreB = (b.priority / max(1, _totalProcessingTime(b))) + (1 / max(1, _totalProcessingTime(b)));
          final cmp = scoreB.compareTo(scoreA);
          return cmp != 0 ? cmp : a.jobId.compareTo(b.jobId);
        });
        break;
      case "GENETICS":
        geneticRule(settings: geneticParams);
        break;
      case "SECUENCIA_USUARIO":
        userSequenceRule();
        break;
      case "MINSLACK":
        // The DB grants MINSLACK to some environments and MS to others; they
        // are the same rule. Accepting both keeps a granted rule from
        // silently producing an empty schedule.
        msRule();
        break;
      case "TABU":
        tabuSearchRule(params: tabuParams);
        break;
      default:
        throw ArgumentError('Regla de despacho desconocida: "$rule"');
    }
  }

  // ── Static rules ──────────────────────────────────────────────────────────
  //
  // A flexible flow shop has no single job order to keep: a station with
  // several machines hands jobs on in whatever order they finish. So the
  // rule is re-applied at EVERY station, to the jobs queued there, with the
  // job's NOMINAL time at that station (on the machine chosen for it) as
  // `p_j`. FIFO is first to arrive at the station.
  //
  // These used to sort the jobs once by the sum of the whole route and walk
  // each job through every station in that order, which is a permutation
  // schedule imposed on a shop that does not keep permutations.

  void eddRule() => _runDynamicStagewise(DispatchCriterion.edd);
  void sptRule() => _runDynamicStagewise(DispatchCriterion.sptNominal);
  void lptRule() => _runDynamicStagewise(DispatchCriterion.lptNominal);
  void fifoRule() => _runDynamicStagewise(DispatchCriterion.fifoArrival);
  void wsptRule() => _runDynamicStagewise(DispatchCriterion.wsptNominal);

  // LWR / MWR: nominal work the job still has from this station on.
  void lwrRule() => _runDynamicStagewise(DispatchCriterion.lwr);
  void mwrRule() => _runDynamicStagewise(DispatchCriterion.mwr);

  /// Genetic algorithm with a job-permutation chromosome, the standard
  /// encoding for the hybrid flow shop (Ruiz & Maroto, 2006): jobs enter the
  /// line in chromosome order and, at every station, each goes to the
  /// machine that finishes it first (ECT, with setups and interruptions).
  /// Fitness: the objective chosen in [settings] (makespan by default). See
  /// docs/diagnostico_genetics.md.
  void geneticRule({GeneticParams settings = const GeneticParams()}) {
    final jobs = List<FlexibleFlowInput>.of(inputJobs);
    if (jobs.isEmpty) return;
    final availability0 = Map<int, DateTime>.of(machinesAvailability);
    final usage0 = Map<int, Duration>.of(_machineContinuousUsage);
    final lastJob0 = Map<int, int?>.of(_machineLastJob);

    void decode(List<int> permutation) {
      machinesAvailability
        ..clear()
        ..addAll(availability0);
      _machineContinuousUsage
        ..clear()
        ..addAll(usage0);
      _machineLastJob
        ..clear()
        ..addAll(lastJob0);
      output = [];
      inputJobs = [for (final i in permutation) jobs[i]];
      for (final job in inputJobs) {
        _assignJobToMachines(job);
      }
    }

    double fitness(List<int> permutation) {
      try {
        decode(permutation);
      } on SchedulingHorizonException {
        return double.infinity;
      }
      if (output.length < jobs.length) return double.infinity;
      final done = completionByJob<FlexibleFlowOutput>(
          output, (o) => o.jobId, (o) => o.endTime);
      return scheduleObjectiveValue(
        settings.objective,
        [
          for (final j in jobs)
            JobCompletion(j.availableDate, j.dueDate, done[j.jobId]!),
        ],
        startDate,
      );
    }

    // Seeds: the order received and the composite-priority order.
    final identity = List<int>.generate(jobs.length, (i) => i);
    final byScore = List<int>.of(identity)
      ..sort((a, b) {
        double score(FlexibleFlowInput j) =>
            (j.priority + 1) / max(1, _totalProcessingTime(j));
        final cmp = score(jobs[b]).compareTo(score(jobs[a]));
        return cmp != 0 ? cmp : jobs[a].jobId.compareTo(jobs[b].jobId);
      });

    final result = runGenetic<List<int>>(
      seeds: [identity, byScore],
      randomIndividual: (r) => List<int>.of(identity)..shuffle(r),
      fitness: fitness,
      crossover: orderCrossover,
      mutate: insertionMutation,
      key: (p) => p.join(','),
      settings: settings,
    );
    decode(result.best);
  }

  /// The jobs enter the line in the order the user chose; jobs left out of
  /// [userSequence] follow in arrival order.
  void userSequenceRule() {
    inputJobs = orderByUserSequence(
        inputJobs, userSequence, (j) => j.jobId, (j) => j.availableDate);
    _scheduleInOrder();
  }

  /// Schedules [inputJobs] exactly in their current order. Johnson and CDS
  /// used to call _schedule with a comparator that always returned 0; the
  /// sort is not stable, so the sequence they had built could be lost.
  void _scheduleInOrder() {
    for (final job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void _schedule(
      int Function(FlexibleFlowInput, FlexibleFlowInput) comparator) {

    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

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

  void _assignJobToMachines(FlexibleFlowInput job) {
    _commitPlacement(_simulateJob(job, notBefore: null));
  }

  /// Schedules ONE task of [jobId] on [machineId], setup then processing,
  /// without writing anything.
  ///
  /// This is the single definition of what a task costs on a machine. Both
  /// [_selectBestMachine] and [_simulateJob] go through it, which is what
  /// keeps the machine chosen and the machine scheduled in agreement — they
  /// used to disagree, because selection priced setup+processing as one
  /// combined block while assignment scheduled them as two separate ones. A
  /// boundary falling between the two, or an uninterruptible task, made the
  /// combined estimate longer than reality and could hand the task to the
  /// wrong machine.
  _FlexibleFlowTask _scheduleTaskOn({
    required int machineId,
    required int jobId,
    required DateTime earliestStart,
    required Duration processingTime,
    required bool interruptible,
  }) {
    final DateTime machineFree = machinesAvailability[machineId] ?? startDate;
    DateTime startTime =
        earliestStart.isAfter(machineFree) ? earliestStart : machineFree;
    startTime = _adjustForWorkingSchedule(startTime);

    final Duration setupDuration = _getSetupDuration(
      machineId,
      jobId,
      _machineLastJob[machineId],
    );

    // Setup then processing, both through the preemption engine. The task's
    // interruption flag governs the pair: interruptible → each may be split
    // by a shift end / maintenance / rest cap; not interruptible → one
    // contiguous block, processing starting the instant setup ends.
    final placed = _engineFor(machineId).computeSetupAndProcessing(
      earliestStart: startTime,
      setupDuration: setupDuration,
      processingDuration: processingTime,
      priorContinuousUsage:
          _machineContinuousUsage[machineId] ?? Duration.zero,
      interruptible: interruptible,
    );

    return _FlexibleFlowTask(
      machineId: machineId,
      setupSegments: placed.setupSegments,
      schedule: placed.processing,
      continuousUsageAfter: placed.continuousUsageAfter,
    );
  }

  /// Walks [job] through every station and returns the placement WITHOUT
  /// committing it — no field is written, so contenders can be priced and
  /// discarded. [_commitPlacement] does the writing.
  _FlexibleFlowPlacement _simulateJob(
    FlexibleFlowInput job, {
    DateTime? notBefore,
  }) {
    DateTime jobStartTime = job.availableDate;
    if (notBefore != null && notBefore.isAfter(jobStartTime)) {
      jobStartTime = notBefore;
    }
    DateTime? actualStartTime;
    DateTime? finalEndTime;

    Map<int, Tuple2<int, Range>> scheduling = {};
    Map<int, List<ProcessingSegment>> segmentsByStation = {};
    Map<int, List<ProcessingSegment>> setupSegmentsByStation = {};
    Map<int, DateTime> availabilityAfter = {};
    Map<int, Duration> continuousUsageAfter = {};

    for (var task in job.taskSequence) {
      int stationId = task.value1;
      Map<int, Duration> machinesInStation = task.value2;

      final bool taskInterruptible = job.isTaskInterruptible(stationId);
      final int machineId = _selectBestMachine(
        machinesInStation,
        job.jobId,
        jobStartTime,
        taskInterruptible,
      );

      final placed = _scheduleTaskOn(
        machineId: machineId,
        jobId: job.jobId,
        earliestStart: jobStartTime,
        processingTime: machinesInStation[machineId]!,
        interruptible: taskInterruptible,
      );

      final DateTime taskStart = placed.schedule.startDate;
      final DateTime endTime = placed.schedule.completionTime;

      // Guarda el primer tiempo real de inicio
      actualStartTime ??= placed.start;
      // Guarda el último tiempo de finalización
      finalEndTime = endTime;

      scheduling[stationId] = Tuple2(machineId, Range(taskStart, endTime));
      segmentsByStation[stationId] = placed.schedule.segments;
      setupSegmentsByStation[stationId] = placed.setupSegments;
      availabilityAfter[machineId] = endTime;
      continuousUsageAfter[machineId] = placed.continuousUsageAfter;

      jobStartTime = endTime;
    }

    return _FlexibleFlowPlacement(
      job: job,
      startTime: actualStartTime ?? jobStartTime,
      endTime: finalEndTime ?? jobStartTime,
      scheduling: scheduling,
      segmentsByStation: segmentsByStation,
      setupSegmentsByStation: setupSegmentsByStation,
      availabilityAfter: availabilityAfter,
      continuousUsageAfter: continuousUsageAfter,
    );
  }

  /// Applies a placement produced by [_simulateJob] to the real schedule.
  void _commitPlacement(_FlexibleFlowPlacement placement) {
    final job = placement.job;

    placement.availabilityAfter.forEach((machineId, endTime) {
      machinesAvailability[machineId] = endTime;
      _rememberLastJob(machineId, job.jobId);
    });
    placement.continuousUsageAfter.forEach((machineId, usage) {
      _machineContinuousUsage[machineId] = usage;
    });

    output.add(FlexibleFlowOutput(
      job.jobId,
      job.dueDate,
      placement.startTime,
      placement.endTime,
      placement.scheduling,
      segmentsByStation: placement.segmentsByStation,
      setupSegmentsByStation: placement.setupSegmentsByStation,
    ));
  }


  /// Picks the machine in a station that finishes the task soonest.
  ///
  /// Prices every option through [_scheduleTaskOn] — the same code path the
  /// task is actually scheduled with — so the machine chosen here is the one
  /// that really is fastest, setup and preemptions included.
  int _selectBestMachine(
    Map<int, Duration> machinesInStation,
    int jobId,
    DateTime jobStartTime,
    bool taskInterruptible,
  ) {
    int bestMachineId = -1;
    DateTime bestEndTime = DateTime(9999);
    DateTime bestStartTime = DateTime(9999);

    for (var entry in machinesInStation.entries) {
      final machineId = entry.key;

      final placed = _scheduleTaskOn(
        machineId: machineId,
        jobId: jobId,
        earliestStart: jobStartTime,
        processingTime: entry.value,
        interruptible: taskInterruptible,
      );
      final DateTime taskStart = placed.start;
      final DateTime endTime = placed.schedule.completionTime;

      // Earliest finish wins; ties go to the earliest start, then to the
      // lowest machine id so the choice is deterministic.
      if (bestMachineId == -1 ||
          endTime.isBefore(bestEndTime) ||
          (endTime.isAtSameMomentAs(bestEndTime) &&
              taskStart.isBefore(bestStartTime)) ||
          (endTime.isAtSameMomentAs(bestEndTime) &&
              taskStart.isAtSameMomentAs(bestStartTime) &&
              machineId < bestMachineId)) {
        bestMachineId = machineId;
        bestEndTime = endTime;
        bestStartTime = taskStart;
      }
    }

    return bestMachineId;
  }

  int _totalProcessingTime(FlexibleFlowInput job) {
    int totalProcessingTime = 0;
    for (var task in job.taskSequence) {
      Map<int, Duration> machineTimes = task.value2;
      int averageProcessingTime = machineTimes.values
              .fold(Duration.zero, (sum, time) => sum + time)
              .inMinutes ~/
          machineTimes.length;
      totalProcessingTime += averageProcessingTime;
    }
    return totalProcessingTime;
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;


    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {

      return DateTime(
        start.year,
        start.month,
        start.day,
        workingStart.hour,
        workingStart.minute,
      );

    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {

      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingStart.hour,
        workingStart.minute,
      );
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
      start.year,
      start.month,
      start.day,
      workingEnd.hour,
      workingEnd.minute,
    );

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      ).add(remainingTime);
    }
    return end;
  }

  Duration _getSetupDuration(
    int machineId,
    int currentJobId,
    int? previousJobId,
  ) {
    // With no previous job on this machine yet, fall back to the machine's
    // configured initial state for this order.
    if (stateSetupMatrix != null && jobStates != null) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        String? previousState;
        if (previousJobId != null && previousJobId > 0) {
          previousState = jobStates![previousJobId]?[machineId];
        } else {
          previousState = initialMachineState[machineId];
        }
        final currentState = jobStates![currentJobId]?[machineId];
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

  /// Records [jobId] as the last job on [machineId] — the job whose state
  /// the next changeover starts from. A job with no state (A-J) registered
  /// for this machine leaves the machine in the state it found it;
  /// recording it anyway made the NEXT changeover look up a null state and
  /// cost zero.
  void _rememberLastJob(int machineId, int jobId) {
    if (jobStates == null || jobStates![jobId]?[machineId] != null) {
      _machineLastJob[machineId] = jobId;
    }
  }

  // ── Dynamic (*_ADAPTADO) rules ────────────────────────────────────────────
  //
  // Same loop as the static rules above (_runDynamicStagewise); the only
  // difference is the index: the operation's EFFECTIVE span on its machine
  // — setup out of the machine's current state, processing, and every
  // interruption — instead of its nominal time.

  void eddaRule() => _runDynamicStagewise(DispatchCriterion.edd);
  void sptaRule() => _runDynamicStagewise(DispatchCriterion.spt);
  void lptaRule() => _runDynamicStagewise(DispatchCriterion.lpt);
  void fifoaRule() => _runDynamicStagewise(DispatchCriterion.fifo);
  void wsptaRule() => _runDynamicStagewise(DispatchCriterion.wspt);

  // MS, CR and ATCS are dynamic by definition — their index depends on the
  // clock t — so they run through the same event-driven dispatch as the
  // *_ADAPTADO rules.
  void msRule() => _runDynamicStagewise(DispatchCriterion.ms);
  void crRule() => _runDynamicStagewise(DispatchCriterion.cr);
  void atcRule() => _runDynamicStagewise(DispatchCriterion.atcs);

  /// Stage-by-stage event-driven dispatch for every dispatching rule of a
  /// (flexible) hybrid flow shop: the static ones, LWR/MWR, the *_ADAPTADO
  /// ones and MS/CR/ATCS. They differ only in the index [criterion] reads.
  ///
  /// Earlier this priced and ranked whole ROUTES (see the removed
  /// `_runDynamic`): at every decision it simulated each pending job clear
  /// through every remaining station and picked the one with the best
  /// route-level index. That matches a strict permutation flow shop, where
  /// one machine per stage keeps a single global order — but a station with
  /// several parallel machines does not keep one order at all, so ranking
  /// whole routes does not match how the shop actually queues work at each
  /// station. The standard treatment of a hybrid/flexible flow shop in the
  /// literature dispatches at EACH station, among the jobs actually queued
  /// there (Ruiz & Vázquez-Rodríguez 2010; Pinedo, *Scheduling*, ch. 4 on
  /// hybrid flow shops) — the same operation-level treatment Open Shop and
  /// Flexible Job Shop already use in this codebase.
  ///
  /// One non-delay loop drives every station at once, mirroring
  /// `OpenShop._schedule`: each round collects the (job, machine) pairings
  /// whose job is ready at that job's CURRENT station (its route order is
  /// still fixed — only the ranking is per-station now), prices every one of
  /// them through [_scheduleTaskOn], and commits the pairing that can start
  /// earliest — ties broken by the dispatch rule. `remainingWork`, which
  /// MS/CR/ATCS charge against the due date, is the job's own nominal time
  /// over the stations still ahead of it (mirrors Vepsäläinen & Morton 1987's
  /// use of remaining work in slack-based indices).
  void _runDynamicStagewise(DispatchCriterion criterion) {
    if (inputJobs.isEmpty) return;

    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParametersStagewise() : null;

    final Map<int, int> stageIndex = {
      for (final job in inputJobs) job.jobId: 0,
    };
    final Map<int, DateTime> jobReadyAt = {
      for (final job in inputJobs) job.jobId: job.availableDate,
    };
    final Map<int, Map<int, Tuple2<int, Range>>> jobScheduling = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, Map<int, List<ProcessingSegment>>> jobSegments = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, Map<int, List<ProcessingSegment>>> jobSetupSegments = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, DateTime> jobActualStart = {};

    bool isActive(FlexibleFlowInput job) =>
        stageIndex[job.jobId]! < job.taskSequence.length;

    while (inputJobs.any(isActive)) {
      final candidates = <({
        FlexibleFlowInput job,
        int stationId,
        int machineId,
        DateTime earliestStart,
        _FlexibleFlowTask placed,
        DispatchCandidate<FlexibleFlowInput> dispatch,
      })>[];
      SchedulingHorizonException? pricingFailure;

      for (final job in inputJobs) {
        if (!isActive(job)) continue;
        final int stage = stageIndex[job.jobId]!;
        final task = job.taskSequence[stage];
        final int stationId = task.value1;
        final Map<int, Duration> machines = task.value2;
        final bool interruptible = job.isTaskInterruptible(stationId);
        final DateTime ready = jobReadyAt[job.jobId]!;

        for (final entry in machines.entries) {
          final machineId = entry.key;
          final DateTime machineFree =
              machinesAvailability[machineId] ?? startDate;
          final DateTime earliestStart = _adjustForWorkingSchedule(
              ready.isAfter(machineFree) ? ready : machineFree);

          final _FlexibleFlowTask placed;
          try {
            placed = _scheduleTaskOn(
              machineId: machineId,
              jobId: job.jobId,
              earliestStart: earliestStart,
              processingTime: entry.value,
              interruptible: interruptible,
            );
          } on SchedulingHorizonException catch (e) {
            pricingFailure ??= e;
            continue;
          }

          final DateTime end = placed.schedule.completionTime;
          // Measured from the EFFECTIVE start (after maintenance, rest caps
          // and non-interruptible waits), which is what the loop ranks on.
          final Duration span = end.difference(placed.start);
          candidates.add((
            job: job,
            stationId: stationId,
            machineId: machineId,
            earliestStart: earliestStart,
            placed: placed,
            dispatch: DispatchCandidate(
              job: job,
              start: placed.start,
              end: end,
              span: span.isNegative ? Duration.zero : span,
              dueDate: job.dueDate,
              releaseDate: job.availableDate,
              priority: job.priority,
              jobId: job.jobId,
              setup: segmentsDuration(placed.setupSegments),
              remainingWork: _remainingWorkAfterStage(job, stage),
              processing: entry.value,
              arrival: ready,
            ),
          ));
        }
      }

      if (candidates.isEmpty) {
        // Every ready operation was unplaceable on every candidate machine:
        // that is the calendar's fault, and the user has to hear about it.
        if (pricingFailure != null) throw pricingFailure;
        break;
      }

      // Non-delay on EFFECTIVE starts — the start the preemption engine
      // returns, after maintenance, rest caps and the wait for a window that
      // fits a non-interruptible block — so a job the calendar would hold
      // back never beats one that can really run now. If nothing can start
      // at the current instant the clock effectively jumps to the earliest
      // effective start (Giffler & Thompson 1960, non-delay).
      //
      // Two decisions, kept apart (see nonDelayConflictSet): each job that
      // can start at t* first gets its machine — earliest completion among
      // the station's machines available at t* — and only then does the
      // dispatch rule choose among the jobs.
      final contenders = nonDelayConflictSet(
        candidates,
        operationKey: (c) => c.job.jobId,
        candidate: (c) => c.dispatch,
        machineId: (c) => c.machineId,
      );
      contenders.sort((a, b) {
        final cmp = compareCandidates<FlexibleFlowInput>(
          criterion,
          a.dispatch,
          b.dispatch,
          decisionTime: a.placed.start,
          atcs: atcs,
        );
        if (cmp != 0) return cmp;
        if (a.stationId != b.stationId) {
          return a.stationId.compareTo(b.stationId);
        }
        return a.machineId.compareTo(b.machineId);
      });

      final selected = contenders.first;
      final job = selected.job;
      final placed = selected.placed;
      final DateTime taskStart = placed.schedule.startDate;
      final DateTime end = placed.schedule.completionTime;

      jobActualStart.putIfAbsent(job.jobId, () => placed.start);
      jobScheduling[job.jobId]![selected.stationId] =
          Tuple2(selected.machineId, Range(taskStart, end));
      jobSegments[job.jobId]![selected.stationId] = placed.schedule.segments;
      jobSetupSegments[job.jobId]![selected.stationId] = placed.setupSegments;

      machinesAvailability[selected.machineId] = end;
      _rememberLastJob(selected.machineId, job.jobId);
      _machineContinuousUsage[selected.machineId] = placed.continuousUsageAfter;

      stageIndex[job.jobId] = stageIndex[job.jobId]! + 1;
      jobReadyAt[job.jobId] = end;

      // Append the moment the job finishes its LAST station, so `output`
      // reflects the order jobs actually finish in — same convention the
      // static rules and the old route-level dispatch both kept (and what
      // callers like the Gantt adapter and these tests read as "the
      // schedule's order"). Building it from `inputJobs` at the very end,
      // as this used to, always produced the ORIGINAL input order — it
      // silently discarded every dispatch decision the loop just made.
      if (stageIndex[job.jobId] == job.taskSequence.length) {
        output.add(FlexibleFlowOutput(
          job.jobId,
          job.dueDate,
          jobActualStart[job.jobId] ?? job.availableDate,
          end,
          Map<int, Tuple2<int, Range>>.from(jobScheduling[job.jobId]!),
          segmentsByStation:
              Map<int, List<ProcessingSegment>>.from(jobSegments[job.jobId]!),
          setupSegmentsByStation: Map<int, List<ProcessingSegment>>.from(
              jobSetupSegments[job.jobId]!),
        ));
      }
    }
  }

  /// Nominal work [job] still has after stage [currentStageIndex]: every
  /// later station's mean duration over its candidate machines. Mirrors
  /// OpenShop._remainingWorkAfter.
  Duration _remainingWorkAfterStage(
      FlexibleFlowInput job, int currentStageIndex) {
    Duration total = Duration.zero;
    for (int i = currentStageIndex + 1; i < job.taskSequence.length; i++) {
      final machines = job.taskSequence[i].value2;
      if (machines.isEmpty) continue;
      total +=
          machines.values.fold(Duration.zero, (sum, d) => sum + d) ~/
              machines.length;
    }
    return total;
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]) for the STAGE-WISE dispatcher: a candidate
  /// here is one operation (one job at one station), so p̄ and s̄ must be
  /// per-operation — mirrors OpenShop._atcsParameters.
  AtcsParameters _atcsParametersStagewise() {
    double totalProcessing = 0;
    int operationCount = 0;
    final Map<int, double> stationLoad = {};
    final Set<int> allMachineIds = {};

    for (final job in inputJobs) {
      for (final task in job.taskSequence) {
        final machines = task.value2;
        if (machines.isEmpty) continue;
        final double mean = machines.values
                .fold<double>(0, (sum, d) => sum + d.inSeconds / 60.0) /
            machines.length;
        totalProcessing += mean;
        operationCount++;
        // A station of k machines works through its queue k times faster.
        stationLoad[task.value1] =
            (stationLoad[task.value1] ?? 0) + mean / machines.length;
        allMachineIds.addAll(machines.keys);
      }
    }
    final double meanProcessing =
        operationCount == 0 ? 1 : totalProcessing / operationCount;

    // Mean pairwise changeover, at the OPERATION level: over every machine
    // that appears in some station, and every ordered pair of distinct jobs
    // that both have a state on it.
    double setupTotal = 0;
    int setupCount = 0;
    if (stateSetupMatrix != null && jobStates != null) {
      for (final machineId in allMachineIds) {
        final matrix = stateSetupMatrix![machineId];
        if (matrix == null) continue;
        for (final from in inputJobs) {
          final fromState = jobStates![from.jobId]?[machineId];
          if (fromState == null) continue;
          for (final to in inputJobs) {
            if (identical(from, to)) continue;
            final toState = jobStates![to.jobId]?[machineId];
            final minutes =
                toState == null ? null : matrix[fromState]?[toState];
            if (minutes == null) continue;
            setupTotal += minutes;
            setupCount++;
          }
        }
      }
    }
    final double meanSetup = setupCount == 0 ? 0 : setupTotal / setupCount;

    final double bottleneck =
        stationLoad.values.fold(0.0, (a, b) => max(a, b));
    final int stationCount = max(stationLoad.length, 1);
    final double workMinutes =
        bottleneck + operationCount * meanSetup / stationCount;

    return AtcsParameters.calibrate(
      start: startDate,
      dueDates: inputJobs.map((job) => job.dueDate),
      meanProcessingMinutes: meanProcessing,
      meanSetupMinutes: meanSetup,
      makespanMinutes: calendarMinutes(
        PreemptionEngine(workingSchedule: workingSchedule),
        startDate,
        Duration(minutes: workMinutes.round()),
      ),
    );
  }

  void cdsAlgorithm() {
    if (inputJobs.isEmpty) return;

    int numStations = inputJobs.first.taskSequence.length;

    if (numStations == 2) {
      _applyJohnsonRuleFlexible(inputJobs);
      return;
    }

    List<FlexibleFlowInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numStations; k++) {
      List<FlexibleFlowInput> tempJobs = inputJobs.map((job) {
        Duration sumA = Duration.zero;
        Duration sumB = Duration.zero;

        for (int i = 0; i < k; i++) {
          Map<int, Duration> machineDurations = job.taskSequence[i].value2;
          sumA += _averageProcessingTime(machineDurations);
        }

        for (int i = k; i < numStations; i++) {
          Map<int, Duration> machineDurations = job.taskSequence[i].value2;
          sumB += _averageProcessingTime(machineDurations);
        }

        return FlexibleFlowInput(
          job.jobId,
          job.dueDate,
          job.priority,
          job.availableDate,
          [
            Tuple2(0, {0: sumA}),
            Tuple2(1, {1: sumB}),
          ],
        );
      }).toList();


      List<FlexibleFlowInput> ordered =
          _getJohnsonOrderedJobsFlexible(tempJobs);

      List<int> orderedIds = ordered.map((e) => e.jobId).toList();

      List<FlexibleFlowInput> orderedOriginal = orderedIds
          .map((id) => inputJobs.firstWhere((job) => job.jobId == id))
          .toList();

      int makespan = _calculateMakespanFlexible(orderedOriginal);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = orderedOriginal;
      }
    }

    inputJobs = bestSequence;
    _scheduleInOrder();
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  // ── TABU: permutación en la estación 1, FIFO después ──────────────────────
  //
  // Una solución es una permutación π de los trabajos. _decodeFrom la
  // convierte en horario: en la estación 1 los trabajos entran en el orden
  // de π, cada uno en la máquina que lo termina antes; en las estaciones
  // 2..S entra primero el que terminó antes la estación anterior (FIFO), en
  // la máquina que lo termina antes . Semillas, vecinos y commit pasan por el
  // MISMO decodificador: el horario que pinta el Gantt es el que se evaluó.
  void tabuSearchRule({required TabuParams params}) {
    final TabuObjective objective = params.objective;
    final int n = inputJobs.length;
    final Random random = Random(params.seed);

    // Dos relojes, como en parallel_machine.dart: [setupWatch] mide las
    // semillas y [watch] SOLO la búsqueda; el presupuesto corre sobre [watch].
    final Stopwatch setupWatch = Stopwatch()..start();
    final Stopwatch watch = Stopwatch();

    // Llegan desde la interfaz; se acotan igual que en máquinas paralelas.
    final int maxIterations = params.maxIterations.clamp(1, 100000);
    final int timeBudgetMs = params.timeBudgetMs.clamp(100, 600000);

    const int minTenure = 5;
    const int maxTenure = 12;
    const int shortTenure = 2; // al intensificar (t = 2)
    const int s1 = 15; // estancamiento -> intensificar
    const int s2 = 45; // estancamiento -> diversificar

    // inputJobs se restaura a este orden después de cada semilla: CDS y
    // Johnson lo reasignan.
    final List<FlexibleFlowInput> receivedJobs =
        List<FlexibleFlowInput>.from(inputJobs);
    final _FlexibleFlowTabuContext ctx = _FlexibleFlowTabuContext(
      objective: objective,
      initialAvailability: Map<int, DateTime>.from(machinesAvailability),
      releaseByJob: {
        for (final job in receivedJobs) job.jobId: job.availableDate,
      },
      station1Machines: {
        for (final job in receivedJobs)
          if (job.taskSequence.isNotEmpty) ...job.taskSequence.first.value2.keys,
      },
    );
    // Con menos de 2 trabajos no hay permutación que cambiar.
    if (n < 2) {
      final _FlexibleFlowTabuSolution only = _FlexibleFlowTabuSolution();
      only.cost = _decodeFrom(ctx, only, receivedJobs, 0, save: true);
      tabuStats = TabuRunStats(
        iterations: 0,
        maxIterations: maxIterations,
        elapsedMs: 0,
        timeBudgetMs: timeBudgetMs,
        objective: objective,
        initialValue: only.cost.value,
        bestValue: only.cost.value,
        stoppedByTime: false,
      );
      return;
    }

    // Lista de candidatos por iteración, con los mismos campos y topes que
    // máquinas paralelas: interJobSamples = k jobs de π que prueban todas
    // sus posiciones (rama insert); intraAttempts = m pares no adyacentes
    // (rama swap). Si k ≥ n o m ≥ pares, la rama recorre su vecindario
    // completo.
    final int jobSamples = params.interJobSamples.clamp(1, n);
    final int swapSamples = params.intraAttempts.clamp(1, 100000);

    // ── Semillas por ordenamiento: _seedPermutations + Johnson/CDS
    final Map<String, List<FlexibleFlowInput>> seeds = {
      for (final entry in _seedPermutations(receivedJobs).entries)
        'orden ${entry.key}': entry.value,
    };
    final List<FlexibleFlowInput>? johnsonCds =
        _johnsonCdsPermutation(receivedJobs, ctx.initialAvailability);
    if (johnsonCds != null) seeds['orden JOHNSON/CDS'] = johnsonCds;

    //  Semillas stagewise: π = inicio en la estación 1 
    final Map<String, void Function()> stagewiseRules = {
      'SPT': sptRule,
      'LPT': lptRule,
      'EDD': eddRule,
      'FIFO': fifoRule,
      'WSPT': wsptRule,
      'MS': msRule,
      'CR': crRule,
      'ATCS': atcRule,
    };
    for (final rule in stagewiseRules.entries) {
      _resetSchedule(ctx.initialAvailability);
      inputJobs = List<FlexibleFlowInput>.from(receivedJobs);
      rule.value();
      seeds['stagewise ${rule.key}'] = _station1StartOrder(receivedJobs);
    }
    inputJobs = List<FlexibleFlowInput>.from(receivedJobs);

    //  Decodificar cada semilla: _decodeFrom(π, 0) · se queda la mejor
    // Toda π se re-decodifica (también las stagewise), así la semilla se
    // mide con el mismo modelo que los vecinos, y deja sus fotos.
    _FlexibleFlowTabuSolution? seedBest;
    String? seedBestName;
    int seedNumber = 0;
    for (final seed in seeds.entries) {
      seedNumber++;
      final _FlexibleFlowTabuSolution candidate = _FlexibleFlowTabuSolution();
      candidate.cost = _decodeFrom(ctx, candidate, seed.value, 0, save: true);
      print('[TABU FFS semilla $seedNumber] ${seed.key} · '
          '${objective.label}=${candidate.cost.value} ${objective.unit} '
          '(flujo ${candidate.cost.flow} min)');
      if (seedBest == null || candidate.cost < seedBest.cost) {
        seedBest = candidate;
        seedBestName = seed.key;
      }
    }

    // ── current π: fotos de la estación 1 · best = current 
    _FlexibleFlowTabuSolution best = seedBest!;
    _FlexibleFlowTabuSolution current = best.copy();
    final _FlexibleFlowTabuCost initialCost = best.cost;

    final Map<String, int> tabuList = {};
    final Map<String, int> moveFrequency = {}; // memoria de largo plazo
    int noImprove = 0;
    int iter = 0;
    bool intensifying = false;
    bool timeUp() => watch.elapsedMilliseconds >= timeBudgetMs;

    // Termina la preparación: desde aquí corre el presupuesto de tiempo.
    setupWatch.stop();
    watch.start();

    while (iter < maxIterations && !timeUp()) {
      // ── Rama insert y rama swap: mejor vecino admisible de cada una ──────
      final _FlexibleFlowTabuMove? insertMove = _bestInsertMove(
        ctx: ctx,
        current: current,
        tabuList: tabuList,
        iter: iter,
        bestCost: best.cost,
        timeUp: timeUp,
        jobSamples: jobSamples,
        random: random,
      );
      final _FlexibleFlowTabuMove? swapMove = _bestSwapMove(
        ctx: ctx,
        current: current,
        tabuList: tabuList,
        iter: iter,
        bestCost: best.cost,
        timeUp: timeUp,
        pairSamples: swapSamples,
        random: random,
      );

      // ── Mejor vecino admisible: mejor insert vs mejor swap 
      // Empate = insert.
      _FlexibleFlowTabuMove? chosen;
      if (insertMove != null && swapMove != null) {
        chosen = swapMove.cost < insertMove.cost ? swapMove : insertMove;
      } else {
        chosen = insertMove ?? swapMove;
      }

      if (chosen == null) {
        // Sin vecino admisible: iteración sin mejora; cae igual al control
        // de estancamiento.
        noImprove++;
      } else {
        // Aplicar movimiento: current  π', save: true 
        // Re-decodifica desde min(a,b) guardando las fotos nuevas. Da el
        // mismo costo que la evaluación (mismo π', misma foto).
        current.cost = _decodeFrom(
            ctx, current, chosen.permutation, chosen.from,
            save: true);

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

        // ── ¿F(current) < F(best)? 
        if (current.cost < best.cost) {
          best = current.copy(); // nueva mejor global
          noImprove = 0;
          intensifying = false;
        } else {
          noImprove++;
        }
      }

      // ── Control de estancamiento
      if (noImprove == s1) {
        // s1: volver a best, tenencia corta.
        current = best.copy();
        intensifying = true;
      } else if (noImprove >= s2) {
        // s2: penaliza los 5 atributos más frecuentes (t = 2·maxTenure = 24)
        // y perturba best con inserts aleatorios.
        tabuList.clear();
        final frequentAttributes = moveFrequency.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        for (final entry in frequentAttributes.take(5)) {
          tabuList[entry.key] = iter + maxTenure * 2;
        }
        moveFrequency.updateAll((_, count) => count ~/ 2);
        moveFrequency.removeWhere((_, count) => count == 0);

        final List<FlexibleFlowInput> perturbed =
            List<FlexibleFlowInput>.from(best.permutation);
        for (int p = 0; p < max(2, n ~/ 6); p++) {
          final FlexibleFlowInput job = perturbed.removeAt(random.nextInt(n));
          perturbed.insert(random.nextInt(n), job);
        }
        final _FlexibleFlowTabuSolution restarted = _FlexibleFlowTabuSolution();
        try {
          restarted.cost = _decodeFrom(ctx, restarted, perturbed, 0, save: true);
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

    // ── Commit del mejor π: decodifica best y escribe output ───────────────
    // Mismo decodificador que evaluó best: output, machinesAvailability,
    // _machineLastJob y _machineContinuousUsage quedan como los de best.
    final _FlexibleFlowTabuCost committed =
        _decodeFrom(ctx, best, best.permutation, 0, save: false);
    if (committed.compareTo(best.cost) != 0) {
      print('[TABU FFS] AVISO: el horario comiteado '
          '(${committed.value}) no coincide con el evaluado '
          '(${best.cost.value})');
    }

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
      stoppedByTime: iter < maxIterations,
    );
    final String mejora = initialCost.value == 0
        ? '0.0'
        : ((initialCost.value - best.cost.value) * 100 / initialCost.value)
            .toStringAsFixed(1);
    print('[TABU FFS] n=$n · semilla ganadora=$seedBestName · '
        'iteraciones=$iter/$maxIterations · '
        'semillas ${setupWatch.elapsedMilliseconds} ms · '
        'busqueda ${watch.elapsedMilliseconds} ms');
    print('[TABU FFS] ${objective.label}: ${initialCost.value} → '
        '${best.cost.value} ${objective.unit} ($mejora% de mejora) · '
        'flujo total: ${initialCost.flow} → ${best.cost.flow} min');
  }

  void _resetSchedule(Map<int, DateTime> initialAvailability) {
    machinesAvailability
      ..clear()
      ..addAll(initialAvailability);
    output.clear();
    _machineLastJob.clear();
    _machineContinuousUsage.clear();
  }

  _FlexibleFlowTabuCost _seedCost(
    TabuObjective objective,
    Map<int, DateTime> releaseByJob,
  ) {
    Duration flow = Duration.zero;
    Duration tardiness = Duration.zero;
    Duration earliness = Duration.zero;
    int tardyJobs = 0;
    DateTime lastEnd = startDate;
    for (final out in output) {
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
    return _FlexibleFlowTabuCost(value, flowMinutes);
  }

  // ── TABU FFS: semillas ────────────────────────────────────────────────────

  /// Semillas por ordenamiento: π = los trabajos ordenados por un índice
  /// estático (tiempos nominales: media por estación de _totalProcessingTime),
  /// más el orden recibido. Empates por jobId: List.sort no es estable.
  Map<String, List<FlexibleFlowInput>> _seedPermutations(
      List<FlexibleFlowInput> jobs) {
    List<FlexibleFlowInput> sortedBy(
        int Function(FlexibleFlowInput, FlexibleFlowInput) cmp) {
      return List<FlexibleFlowInput>.from(jobs)
        ..sort((a, b) {
          final int c = cmp(a, b);
          return c != 0 ? c : a.jobId.compareTo(b.jobId);
        });
    }

    int p(FlexibleFlowInput job) => max(1, _totalProcessingTime(job));
    int dueIn(FlexibleFlowInput job) =>
        job.dueDate.difference(startDate).inMinutes;

    return {
      'SPT': sortedBy((a, b) => p(a).compareTo(p(b))),
      'LPT': sortedBy((a, b) => p(b).compareTo(p(a))),
      'EDD': sortedBy((a, b) => a.dueDate.compareTo(b.dueDate)),
      'FIFO': sortedBy((a, b) => a.availableDate.compareTo(b.availableDate)),
      'WSPT': sortedBy((a, b) => (b.priority / p(b)).compareTo(a.priority / p(a))),
      'MS': sortedBy((a, b) => (dueIn(a) - p(a)).compareTo(dueIn(b) - p(b))),
      'CR': sortedBy((a, b) => (dueIn(a) / p(a)).compareTo(dueIn(b) / p(b))),
      'RECIBIDO': List<FlexibleFlowInput>.from(jobs),
    };
  }

  /// Semilla Johnson/CDS: corre cdsAlgorithm (que con 2 estaciones aplica
  /// Johnson) y toma como π el orden en que deja inputJobs. Con menos de 2
  /// estaciones CDS deja inputJobs vacío, así que no aplica.
  List<FlexibleFlowInput>? _johnsonCdsPermutation(
    List<FlexibleFlowInput> jobs,
    Map<int, DateTime> initialAvailability,
  ) {
    if (jobs.isEmpty || jobs.first.taskSequence.length < 2) return null;
    _resetSchedule(initialAvailability);
    inputJobs = List<FlexibleFlowInput>.from(jobs);
    cdsAlgorithm();
    final List<FlexibleFlowInput> permutation =
        List<FlexibleFlowInput>.from(inputJobs);
    inputJobs = List<FlexibleFlowInput>.from(jobs);
    return permutation.length == jobs.length ? permutation : null;
  }

  /// π de una semilla stagewise: los trabajos en el orden en que arrancaron
  /// en la estación 1 (FlexibleFlowOutput.startDate es el inicio real en la
  /// primera estación, setup incluido). Empates por jobId.
  List<FlexibleFlowInput> _station1StartOrder(List<FlexibleFlowInput> jobs) {
    final Map<int, DateTime> startByJob = {
      for (final out in output) out.jobId: out.startDate,
    };
    final DateTime never = DateTime(9999);
    return List<FlexibleFlowInput>.from(jobs)
      ..sort((a, b) {
        final int cmp = (startByJob[a.jobId] ?? never)
            .compareTo(startByJob[b.jobId] ?? never);
        return cmp != 0 ? cmp : a.jobId.compareTo(b.jobId);
      });
  }

  // ── TABU FFS: decodificador ───────────────────────────────────────────────

  /// Decodifica [permutation] (π') y devuelve su _TabuCost (objetivo, flujo).

  _FlexibleFlowTabuCost _decodeFrom(
    _FlexibleFlowTabuContext ctx,
    _FlexibleFlowTabuSolution base,
    List<FlexibleFlowInput> permutation,
    int from, {
    required bool save,
  }) {
    final int n = permutation.length;
    _resetSchedule(ctx.initialAvailability);

    // Tareas programadas de cada posición, una por estación en orden.
    final List<List<_FlexibleFlowTask>> tasksByPosition =
        List.generate(n, (_) => <_FlexibleFlowTask>[]);

    // ── Restaurar foto[min(a,b)] ──
    if (from > 0) {
      _restoreStation1Photo(base.photos[from], ctx.station1Machines);
      for (int k = 0; k < from; k++) {
        final _FlexibleFlowTask? task = base.station1Tasks[k];
        if (task != null) tasksByPosition[k].add(task);
      }
    }

    if (save) {
      final List<FlexibleFlowInput> tail = permutation.sublist(from);
      base.permutation
        ..removeRange(from, base.permutation.length)
        ..addAll(tail);
      base.photos.removeRange(from, base.photos.length);
      base.station1Tasks.removeRange(from, base.station1Tasks.length);
    }

    // ── Estación 1: manda π' desde min(a,b) 
    for (int k = from; k < n; k++) {

    // estados antes de programar una maquina
      if (save) base.photos.add(_takeStation1Photo(ctx.station1Machines));
      final FlexibleFlowInput job = permutation[k];
      _FlexibleFlowTask? placed;
      if (job.taskSequence.isNotEmpty) {
        // Busca el lugar adecuado 
        placed = _placeStage(job, 0, job.availableDate);
        tasksByPosition[k].add(placed);
      }
      // cuantas estaciones necesita 
      if (save) base.station1Tasks.add(placed);
    }

    // ── Estaciones 2..S: FIFO ──
    // En un FFS todos los trabajos siguen la misma ruta sin reentrada, así
    // que las máquinas de cada estación no se repiten en otra y se puede
    // programar estación por estación.
    final int stages = permutation.fold<int>(
        0, (m, job) => max(m, job.taskSequence.length));
    for (int stage = 1; stage < stages; stage++) {
      final List<int> queue = [
        for (int k = 0; k < n; k++)
          if (permutation[k].taskSequence.length > stage) k,
      ]..sort((a, b) {
          final int cmp = tasksByPosition[a]
              .last
              .schedule
              .completionTime
              .compareTo(tasksByPosition[b].last.schedule.completionTime);
          return cmp != 0 ? cmp : a.compareTo(b);
        });
      for (final int k in queue) {
        final FlexibleFlowInput job = permutation[k];
        tasksByPosition[k].add(_placeStage(
            job, stage, tasksByPosition[k].last.schedule.completionTime));
      }
    }

    //Output, en el orden en que los trabajos terminan su última estación
    // Construccion del orden final de la maquinas 
    final List<int> finishOrder = List<int>.generate(n, (k) => k);
    DateTime endOf(int k) => tasksByPosition[k].isEmpty
        ? permutation[k].availableDate
        : tasksByPosition[k].last.schedule.completionTime;
    finishOrder.sort((a, b) {
      // ordena por fecha de fianlizacion 
      final int cmp = endOf(a).compareTo(endOf(b));
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    for (final int k in finishOrder) {
      final FlexibleFlowInput job = permutation[k];
      final List<_FlexibleFlowTask> tasks = tasksByPosition[k];
      final Map<int, Tuple2<int, Range>> scheduling = {};
      final Map<int, List<ProcessingSegment>> segmentsByStation = {};
      final Map<int, List<ProcessingSegment>> setupSegmentsByStation = {};
      for (int stage = 0; stage < tasks.length; stage++) {
        final int stationId = job.taskSequence[stage].value1;
        final _FlexibleFlowTask task = tasks[stage];
        scheduling[stationId] = Tuple2(task.machineId,
            Range(task.schedule.startDate, task.schedule.completionTime));
        segmentsByStation[stationId] = task.schedule.segments;
        setupSegmentsByStation[stationId] = task.setupSegments;
      }
      output.add(FlexibleFlowOutput(
        job.jobId,
        job.dueDate,
        tasks.isEmpty ? job.availableDate : tasks.first.start,
        endOf(k),
        scheduling,
        segmentsByStation: segmentsByStation,
        setupSegmentsByStation: setupSegmentsByStation,
      ));
    }

    
    return _seedCost(ctx.objective, ctx.releaseByJob);
  }

  /// Programa la estación [stage] de [job] desde [earliestStart] en la
  /// máquina que la termina antes y escribe el estado de esa máquina.
  /// Mismas piezas y mismo orden que _simulateJob + _commitPlacement.
  _FlexibleFlowTask _placeStage(
      FlexibleFlowInput job, int stage, DateTime earliestStart) {
    final Tuple2<int, Map<int, Duration>> task = job.taskSequence[stage];
    final bool interruptible = job.isTaskInterruptible(task.value1);
    final int machineId = _selectBestMachine(
        task.value2, job.jobId, earliestStart, interruptible);
    final _FlexibleFlowTask placed = _scheduleTaskOn(
      machineId: machineId,
      jobId: job.jobId,
      earliestStart: earliestStart,
      processingTime: task.value2[machineId]!,
      interruptible: interruptible,
    );
    machinesAvailability[machineId] = placed.schedule.completionTime;
    _rememberLastJob(machineId, job.jobId);
    _machineContinuousUsage[machineId] = placed.continuousUsageAfter;
    return placed;

  }

  _Station1Photo _takeStation1Photo(Set<int> station1Machines) {
    return _Station1Photo(
      availability: {
        for (final m in station1Machines)
          if (machinesAvailability.containsKey(m)) m: machinesAvailability[m]!,
      },
      lastJob: {
        for (final m in station1Machines)
          if (_machineLastJob.containsKey(m)) m: _machineLastJob[m],
      },
      continuousUsage: {
        for (final m in station1Machines)
          if (_machineContinuousUsage.containsKey(m))
            m: _machineContinuousUsage[m]!,
      },
    );
  }

  void _restoreStation1Photo(_Station1Photo photo, Set<int> station1Machines) {
    for (final m in station1Machines) {
      final DateTime? available = photo.availability[m];
      if (available != null) {
        machinesAvailability[m] = available;
      } else {
        machinesAvailability.remove(m);
      }
      if (photo.lastJob.containsKey(m)) {
        _machineLastJob[m] = photo.lastJob[m];
      } else {
        _machineLastJob.remove(m);
      }
      final Duration? usage = photo.continuousUsage[m];
      if (usage != null) {
        _machineContinuousUsage[m] = usage;
      } else {
        _machineContinuousUsage.remove(m);
      }
    }
  }

  // ── TABU FFS: vecindarios 

  /// Rama insert: mover el trabajo de la posición a a la posición b. Mejor
  /// mejora sobre la lista de candidatos: [jobSamples] posiciones a de π
  /// (k), cada una probada en todas sus posiciones b. Con k ≥ n es el
  /// vecindario completo.

  _FlexibleFlowTabuMove? _bestInsertMove({
    required _FlexibleFlowTabuContext ctx,
    required _FlexibleFlowTabuSolution current,
    required Map<String, int> tabuList,
    required int iter,
    required _FlexibleFlowTabuCost bestCost,
    required bool Function() timeUp,
    required int jobSamples,
    required Random random,
  }) {
    final List<FlexibleFlowInput> pi = current.permutation;
    final int n = pi.length;
    _FlexibleFlowTabuMove? bestMove;

    final List<int> positions = _samplePositions(n, jobSamples, random);
    final Set<int> sampled = positions.toSet();

    for (final int a in positions) {
      final FlexibleFlowInput originalNeighbour = a > 0 ? pi[a - 1] : pi[1];
      for (int b = 0; b < n; b++) {
        if (b == a) continue;
        if (b == a - 1 && sampled.contains(a - 1)) continue;
        if (timeUp()) return bestMove;

        final List<FlexibleFlowInput> trial = List<FlexibleFlowInput>.from(pi);
        final FlexibleFlowInput moved = trial.removeAt(a);
        trial.insert(b, moved);
        final FlexibleFlowInput neighbour = b > 0 ? trial[b - 1] : trial[1];

        bestMove = _admitMove(
          ctx: ctx,
          current: current,
          trial: trial,
          from: min(a, b),
          attribute: _tabuPair(moved, neighbour),
          tabuOnApply: _tabuPair(moved, originalNeighbour),
          isInsert: true,
          tabuList: tabuList,
          iter: iter,
          bestCost: bestCost,
          bestSoFar: bestMove,
        );
      }
    }
    return bestMove;
  }

  /// Rama swap: intercambiar los trabajos de las posiciones a y b, no
  /// adyacentes (el swap adyacente ya es un insert). Mejor mejora sobre la
  /// lista de candidatos: [pairSamples] pares (m) sorteados entre los
  /// (n−1)(n−2)/2 posibles; con m ≥ pares es el vecindario completo.
  /// Atributo par:(Ja, Jb): el mismo se revisa y se registra.
  _FlexibleFlowTabuMove? _bestSwapMove({
    required _FlexibleFlowTabuContext ctx,
    required _FlexibleFlowTabuSolution current,
    required Map<String, int> tabuList,
    required int iter,
    required _FlexibleFlowTabuCost bestCost,
    required bool Function() timeUp,
    required int pairSamples,
    required Random random,
  }) {
    final List<FlexibleFlowInput> pi = current.permutation;
    final int n = pi.length;
    _FlexibleFlowTabuMove? bestMove;

    // Pares (a, b) codificados como a·n + b, en orden a, luego b.
    final List<int> pairs = [
      for (int a = 0; a < n; a++)
        for (int b = a + 1; b < n; b++) a * n + b,
    ];

    for (final int pair in _sampleSorted(pairs, pairSamples, random)) {
      final int a = pair ~/ n;
      final int b = pair % n;
      if (timeUp()) return bestMove;

      final List<FlexibleFlowInput> trial = List<FlexibleFlowInput>.from(pi);
      trial[a] = pi[b];
      trial[b] = pi[a];

      final String attribute = _tabuPair(pi[a], pi[b]);
      bestMove = _admitMove(
        ctx: ctx,
        current: current,
        trial: trial,
        from: a,
        attribute: attribute,
        tabuOnApply: attribute,
        isInsert: false,
        tabuList: tabuList,
        iter: iter,
        bestCost: bestCost,
        bestSoFar: bestMove,
      );
    }
    return bestMove;
  }

  /// Posiciones a de la rama insert: las n si k ≥ n; si no, k distintas.
  List<int> _samplePositions(int n, int k, Random random) =>
      _sampleSorted(List<int>.generate(n, (i) => i), k, random);

  /// Toma [k] elementos distintos de [items] (Fisher–Yates parcial con el
  /// [random] de la corrida, así la semilla la reproduce) y los devuelve
  /// en orden ascendente, para que los empates entre vecinos de igual costo
  /// se resuelvan igual que al recorrer el vecindario completo. Con
  /// k ≥ items.length devuelve [items] tal cual y no consume [random].
  List<int> _sampleSorted(List<int> items, int k, Random random) {
    if (k >= items.length) return items;
    final List<int> pool = List<int>.from(items);
    for (int i = 0; i < k; i++) {
      final int j = i + random.nextInt(pool.length - i);
      final int tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return pool.sublist(0, k)..sort();
  }

  /// Evalúa un candidato (save: false) y le aplica el filtro tabú con
  /// aspiración: un atributo vetado solo pasa si mejora best. Devuelve el
  /// mejor admisible entre [bestSoFar] y este candidato. El filtro revisa
  /// [attribute]; [tabuOnApply] solo viaja hasta que se aplica el movimiento.
  _FlexibleFlowTabuMove? _admitMove({
    required _FlexibleFlowTabuContext ctx,
    required _FlexibleFlowTabuSolution current,
    required List<FlexibleFlowInput> trial,
    required int from,
    required String attribute,
    required String tabuOnApply,
    required bool isInsert,
    required Map<String, int> tabuList,
    required int iter,
    required _FlexibleFlowTabuCost bestCost,
    required _FlexibleFlowTabuMove? bestSoFar,
  }) {
    final _FlexibleFlowTabuCost cost;
    try {
      cost = _decodeFrom(ctx, current, trial, from, save: false);
    } on SchedulingHorizonException {
      return bestSoFar; // π' no cabe en el calendario: vecino no factible
    }

    final bool isTabu = (tabuList[attribute] ?? -1) > iter;
    final bool aspiration = cost < bestCost;
    if (isTabu && !aspiration) return bestSoFar;

    if (bestSoFar != null && !(cost < bestSoFar.cost)) return bestSoFar;
    return _FlexibleFlowTabuMove(
      isInsert: isInsert,
      permutation: trial,
      from: from,
      attribute: attribute,
      tabuOnApply: tabuOnApply,
      cost: cost,
    );
  }

  /// Atributo tabú par:(Ja, Jb), sin orden, por jobId.
  String _tabuPair(FlexibleFlowInput a, FlexibleFlowInput b) {
    final int lo = min(a.jobId, b.jobId);
    final int hi = max(a.jobId, b.jobId);
    return 'par:${lo}_$hi';
  }
  
  void _applyJohnsonRuleFlexible(List<FlexibleFlowInput> jobs) {
    List<FlexibleFlowInput> groupI = [];
    List<FlexibleFlowInput> groupII = [];

    for (var job in jobs) {
      Duration a = job.taskSequence[0].value2.values.first;
      Duration b = job.taskSequence[1].value2.values.first;

      if (a <= b) {
        groupI.add(job);
      } else {
        groupII.add(job);
      }
    }


    groupI.sort((a, b) => a.taskSequence[0].value2.values.first
        .compareTo(b.taskSequence[0].value2.values.first));
    groupII.sort((a, b) => b.taskSequence[1].value2.values.first
        .compareTo(a.taskSequence[1].value2.values.first));


    inputJobs = [...groupI, ...groupII];
    _scheduleInOrder();
  }

  Duration _averageProcessingTime(Map<int, Duration> times) {
    if (times.isEmpty) return Duration.zero;
    int totalMs = times.values.fold(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ times.length);
  }


  List<FlexibleFlowInput> _getJohnsonOrderedJobsFlexible(
      List<FlexibleFlowInput> jobs) {
    List<FlexibleFlowInput> groupI = [];
    List<FlexibleFlowInput> groupII = [];

    for (var job in jobs) {
      Duration a = job.taskSequence[0].value2[0]!;
      Duration b = job.taskSequence[1].value2[1]!;

      if (a <= b) {
        groupI.add(job);
      } else {
        groupII.add(job);
      }
    }


    groupI.sort((a, b) =>
        a.taskSequence[0].value2[0]!.compareTo(b.taskSequence[0].value2[0]!));
    groupII.sort((a, b) =>
        b.taskSequence[1].value2[1]!.compareTo(a.taskSequence[1].value2[1]!));


    return [...groupI, ...groupII];
  }

  int _calculateMakespanFlexible(List<FlexibleFlowInput> jobSequence) {
    // Disponibilidad actual de cada máquina en cada estación
    Map<int, Map<int, DateTime>> stationMachineAvailability = {};

    // Inicializa todas las máquinas como disponibles desde el inicio
    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int stationId = task.value1;
        for (var machineId in task.value2.keys) {
          stationMachineAvailability.putIfAbsent(stationId, () => {});
          stationMachineAvailability[stationId]![machineId] = startDate;
        }
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int stationId = task.value1;
        Map<int, Duration> machineOptions = task.value2;

        // Elegimos la máquina más disponible con menor tiempo de procesamiento
        int selectedMachineId = -1;
        DateTime earliestStart = DateTime(9999);
        Duration selectedDuration = Duration.zero;

        for (var entry in machineOptions.entries) {
          int machineId = entry.key;
          Duration duration = entry.value;

          DateTime machineAvailable =
              stationMachineAvailability[stationId]?[machineId] ?? startDate;

          DateTime tentativeStart = jobStartTime.isAfter(machineAvailable)
              ? jobStartTime
              : machineAvailable;

          tentativeStart = _adjustForWorkingSchedule(tentativeStart);
          DateTime tentativeEnd = tentativeStart.add(duration);
          tentativeEnd =
              _adjustEndTimeForWorkingSchedule(tentativeStart, tentativeEnd);


          if (tentativeEnd.isBefore(earliestStart)) {
            earliestStart = tentativeEnd;
            selectedMachineId = machineId;
            selectedDuration = duration;
          }
        }

        // Programamos el trabajo en la máquina seleccionada
        DateTime machineAvailable =
            stationMachineAvailability[stationId]![selectedMachineId]!;
        DateTime startTime = jobStartTime.isAfter(machineAvailable)
            ? jobStartTime
            : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(selectedDuration);
        endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

        // Actualizamos disponibilidad
        stationMachineAvailability[stationId]![selectedMachineId] = endTime;
        jobStartTime = endTime; // Para la próxima estación

        // Actualizar el tiempo final global si es mayor
        if (endTime.isAfter(makespanEndTime)) {
          makespanEndTime = endTime;
        }
      }
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }


List<Map<String, dynamic>> flexibleFlowShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(hour: payload['workingStartHour'] as int, minute: payload['workingStartMinute'] as int),
    TimeOfDay(hour: payload['workingEndHour'] as int, minute: payload['workingEndMinute'] as int),
  );

  final inputJobs = (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jobMap = Map<String, dynamic>.from(jobData as Map);
    final taskSequence = (jobMap['taskSequence'] as List<dynamic>).map((taskData) {
      final taskMap = Map<String, dynamic>.from(taskData as Map);
      final machineDurations = (taskMap['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) => MapEntry(key as int, Duration(milliseconds: value as int)),
      );
      return Tuple2(taskMap['taskId'] as int, machineDurations);
    }).toList();

    return FlexibleFlowInput(
      jobMap['jobId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
      jobMap['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['availableDate'] as int),
      taskSequence,
    );
  }).toList();

  final machinesAvailability = (payload['machinesAvailability'] as Map<dynamic, dynamic>)
      .map((key, value) => MapEntry(key as int, DateTime.fromMillisecondsSinceEpoch(value as int)));

  // Calendar inputs — inactivity windows, the continuous-use cap and the
  // rest duration — used to be dropped on the floor here, so an order run
  // through this isolate entry point ignored maintenance/shift/rest
  // altogether. Parsed the same way openShopSchedule does.
  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  final rawInactivities = payload['machineInactivities'];
  if (rawInactivities != null) {
    for (final entry in (rawInactivities as Map<dynamic, dynamic>).entries) {
      final machineId = entry.key as int;
      machineInactivities[machineId] = (entry.value as List<dynamic>)
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
  }

  final machineContinueCapacity = payload['machineContinueCapacity'] == null
      ? const <int, int>{}
      : (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as int));

  final machineRestTime = <int, Duration?>{};
  final rawRestTime = payload['machineRestTime'];
  if (rawRestTime != null) {
    for (final entry in (rawRestTime as Map<dynamic, dynamic>).entries) {
      machineRestTime[entry.key as int] = entry.value == null
          ? null
          : Duration(milliseconds: entry.value as int);
    }
  }

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
                key as int,
                (Map<dynamic, dynamic>.from(value as Map)).map(
                  (prev, curr) => MapEntry(
                    prev as String,
                    (Map<dynamic, dynamic>.from(curr as Map)).map(
                      (next, minutes) => MapEntry(next as String, minutes as int),
                    ),
                  ),
                ),
              ),
        );

  final jobStates = payload['jobStates'] == null
      ? null
      : (payload['jobStates'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map)).map((mKey, state) => MapEntry(mKey as int, state as String)),
          ),
        );

  final initialMachineState = payload['initialMachineState'] == null
      ? const <int, String>{}
      : (payload['initialMachineState'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as String));

  final output = FlexibleFlowShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    initialMachineState: initialMachineState,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    geneticParams: GeneticParams.fromMap(
        payload['geneticParams'] as Map<dynamic, dynamic>?),
    userSequence: (payload['userSequence'] as List<dynamic>?)?.cast<int>(),
  ).output;

  List<Map<String, dynamic>> segmentsToPayload(
      List<ProcessingSegment> segments) {
    return segments
        .map((s) => {
              'start': s.start.millisecondsSinceEpoch,
              'end': s.end.millisecondsSinceEpoch,
            })
        .toList();
  }

  return output.map((out) {
    return {
      'jobId': out.jobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling': out.scheduling.map((key, value) => MapEntry(key.toString(), {
            'machineId': value.value1,
            'start': value.value2.startDate.millisecondsSinceEpoch,
            'end': value.value2.endDate.millisecondsSinceEpoch,
          })),
      'segmentsByStation': out.segmentsByStation.map((key, segments) =>
          MapEntry(key.toString(), segmentsToPayload(segments))),
      'setupSegmentsByStation': out.setupSegmentsByStation.map(
          (key, segments) =>
              MapEntry(key.toString(), segmentsToPayload(segments))),
    };
  }).toList();
}

}