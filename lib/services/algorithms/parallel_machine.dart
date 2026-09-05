import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'dart:math';

class ParallelInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final Map<int, Duration> durationsInMachines;

  /// Product family / job-type label, e.g. "A", "B".
  /// Used as the row/column key in the state-based setup matrix.
  final String jobState;

  /// Optional per-machine state (machineId → state). Falls back to [jobState].
  final Map<int, String>? jobStatesByMachine;

  /// Default interruptibility (usually the task's own setting). Whether this
  /// job's processing may be split by a work-shift boundary, the
  /// continuous-use rest cap, or a maintenance window.
  final bool interruptible;

  /// Optional per-machine override (machineId → interruptible). Falls back
  /// to [interruptible].
  final Map<int, bool>? interruptibleByMachine;

  ParallelInput(
    this.jobId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.durationsInMachines, {
    this.jobState = 'A',
    this.jobStatesByMachine,
    this.interruptible = true,
    this.interruptibleByMachine,
  });

  String stateOnMachine(int machineId) =>
      jobStatesByMachine?[machineId] ?? jobState;

  bool isInterruptibleOnMachine(int machineId) =>
      interruptibleByMachine?[machineId] ?? interruptible;
}

class ParallelOutput {
  final int jobId;
  final int machineId;
  final DateTime startDate;
  final DateTime endDate;
  final Duration delay;
  final DateTime dueDate;
  final List<ProcessingSegment> segments;

  ParallelOutput(
    this.jobId,
    this.machineId,
    this.startDate,
    this.endDate,
    this.delay,
    this.dueDate, {
    List<ProcessingSegment>? segments,
  }) : segments = segments ?? [ProcessingSegment(startDate, endDate)];
}

/// A candidate neighbourhood move (intra- or inter-machine) considered by the
/// tabu search. Carries the resulting sequences so the move can be applied
/// without recomputing anything extra.
class _TabuCandidate {
  final bool isIntra;
  final int machineA;
  final int? machineB;
  final List<ParallelInput> newSequenceA;
  final List<ParallelInput>? newSequenceB;
  final Duration newFlowA;
  final Duration? newFlowB;
  final String attribute;
  final int totalMinutesAfter;

  _TabuCandidate({
    required this.isIntra,
    required this.machineA,
    this.machineB,
    required this.newSequenceA,
    this.newSequenceB,
    required this.newFlowA,
    this.newFlowB,
    required this.attribute,
    required this.totalMinutesAfter,
  });
}

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<ParallelInput> inputJobs = [];
  Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
  List<ParallelOutput> output = [];

  /// Machine → ordered job sequence, as decided by [tabuSearchRule].
  Map<int, List<ParallelInput>> jobsInMachines = {};

  // ── Setup-time state ──────────────────────────────────────────────────────
  // stateSetupMatrix: machineId → fromState → toState → minutes
  // Mirrors the structure used by Flow Shop / Flexible Job Shop / Open Shop.
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;

  // Tracks which job-state each machine processed last (null = cold start).
  final Map<int, String?> _machineLastState = {};

  // Machine inactivity support.
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count — so a
  // single long job can be preempted mid-processing.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule, {
    this.stateSetupMatrix,
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) {
    // Initialise cold-start tracking and a preemption engine per machine.
    for (final machineId in machines.keys) {
      _machineLastState[machineId] = null;
      _machineContinuousUsage[machineId] = Duration.zero;
      final capacityMinutes = machineContinueCapacity[machineId] ?? 0;
      _engineByMachine[machineId] = PreemptionEngine(
        workingSchedule: workingSchedule,
        maintenanceWindows: machineInactivities[machineId] ?? const [],
        continuousUseCap:
            capacityMinutes > 0 ? Duration(minutes: capacityMinutes) : Duration.zero,
        restDuration: machineRestTime[machineId] ?? Duration.zero,
      );
    }

    final r = rule.toUpperCase();
    switch (r) {
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "EDD":
        eddRule();
        break;
      case "FIFO":
        fcfsRule();
        break;
      case "MINSLACK":
        minslackRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "MS":
        msRule();
        break;
      case "GENETICS":
        geneticsRule();
        break;
      case "TABU":        
        tabuSearchRule();
      break;


    }
  }

  // ── Setup-time helper ─────────────────────────────────────────────────────

  /// Returns the changeover duration required on [machineId] before processing
  /// [toJob], given that the machine's last job-state was [fromState].
  ///
  /// Returns [Duration.zero] when:
  ///   • no matrix is configured, or
  ///   • [fromState] is null (cold start / first job on this machine), or
  ///   • the specific (fromState, toState) cell is absent from the matrix.
  Duration _setupDuration(int machineId, String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  // ── Dispatching rules ─────────────────────────────────────────────────────

  void msRule()       => _schedule((a, b) => _slack(a).compareTo(_slack(b)));
  void sptRule()      => _schedule((a, b) => _averageProcessingTime(a).compareTo(_averageProcessingTime(b)));
  void lptRule()      => _schedule((a, b) => _averageProcessingTime(b).compareTo(_averageProcessingTime(a)));
  void eddRule()      => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void fcfsRule()     => _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void minslackRule() => _schedule((a, b) => _slack(a).compareTo(_slack(b)));
  void crRule()       => _schedule((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
  void atcRule()      => _schedule((a, b) => _atcPriority(b, startDate).compareTo(_atcPriority(a, startDate)));
  void wsptRule()     => _schedule((a, b) => calculateWSPT(b).compareTo(calculateWSPT(a)));

  void sptaRule() {
    _schedule((a, b) {
      int minA = a.durationsInMachines.values.reduce((x, y) => x < y ? x : y).inMilliseconds;
      int minB = b.durationsInMachines.values.reduce((x, y) => x < y ? x : y).inMilliseconds;
      return minA.compareTo(minB);
    });
  }

  void eddaRule() {
    final now = DateTime.now();
    _schedule((a, b) {
      final aAvail = !a.availableDate.isAfter(now);
      final bAvail = !b.availableDate.isAfter(now);
      if (aAvail && !bAvail) return -1;
      if (!aAvail && bAvail) return 1;
      if (!aAvail && !bAvail) return 0;
      return a.dueDate.compareTo(b.dueDate);
    });
  }

  void lptaRule() {
    final now = DateTime.now();
    _schedule((a, b) {
      final aAvail = !a.availableDate.isAfter(now);
      final bAvail = !b.availableDate.isAfter(now);
      if (aAvail && !bAvail) return -1;
      if (!aAvail && bAvail) return 1;
      if (!aAvail && !bAvail) return 0;
      return _averageProcessingTime(b).compareTo(_averageProcessingTime(a));
    });
  }

  void fifoaRule() {
    final now = DateTime.now();
    _schedule((a, b) {
      final aAvail = !a.availableDate.isAfter(now);
      final bAvail = !b.availableDate.isAfter(now);
      if (aAvail && !bAvail) return -1;
      if (!aAvail && bAvail) return 1;
      if (!aAvail && !bAvail) return 0;
      return a.availableDate.compareTo(b.availableDate);
    });
  }

  void wsptaRule() {
    final now = DateTime.now();
    _schedule((a, b) {
      final aAvail = !a.availableDate.isAfter(now);
      final bAvail = !b.availableDate.isAfter(now);
      if (aAvail && !bAvail) return -1;
      if (!aAvail && bAvail) return 1;
      if (!aAvail && !bAvail) return 0;
      return calculateWSPT(b).compareTo(calculateWSPT(a));
    });
  }

  // ── Core scheduler ────────────────────────────────────────────────────────

  void _schedule(int Function(ParallelInput, ParallelInput) comparator) {
    inputJobs.sort(comparator);
    _assignJobsToMachines();
  }

  /// Assigns each job to the machine that minimises tardiness after accounting
  /// for the sequence-dependent setup time on that machine.
  ///
  /// Key difference from the original: before committing a job to a machine we
  /// add the setup duration s_{lastState → jobState} to the candidate start
  /// time.  The "best" machine is still the one that produces the earliest
  /// (adjusted) end time, but now setup cost is part of that calculation.
  ///
  /// After a machine is chosen, [_machineLastState] is updated so the next job
  /// assigned to that machine sees the correct "from" state.
  void _assignJobsToMachines() {
    // Current earliest-free DateTime for each machine.
    final Map<int, DateTime> machineAvailable = {
      for (final id in machines.keys) id: startDate,
    };

    for (final job in inputJobs) {
      int bestMachineId = -1;
      DateTime bestProcessStart = DateTime.now();
      Duration bestDelay = const Duration(days: 99999);
      SegmentedSchedule? bestSchedule;

      for (final entry in job.durationsInMachines.entries) {
        final int machineId = entry.key;
        final Duration processingTime = entry.value;

        // Earliest moment when both machine and job are ready.
        DateTime candidateStart = job.availableDate.isAfter(machineAvailable[machineId]!)
            ? job.availableDate
            : machineAvailable[machineId]!;
        candidateStart = _adjustForWorkingSchedule(candidateStart);

        // ── Sequence-dependent setup time ─────────────────────────────────
        // The machine needs s_{prevState → jobState} minutes of preparation
        // before it can start processing this job.  Setup runs on the machine
        // (occupies it), so processing only starts after setup finishes.
        final String toState = job.stateOnMachine(machineId);
        final Duration setup = _setupDuration(
          machineId,
          _machineLastState[machineId],
          toState,
        );
        final DateTime processStart = setup > Duration.zero
            ? _adjustForWorkingSchedule(candidateStart.add(setup))
            : candidateStart;

        // Split into segments wherever the work-shift end, a maintenance
        // window, or the continuous-use rest cap falls inside this job's
        // processing span on this candidate machine.
        final schedule = _engineByMachine[machineId]!.computeSegments(
          earliestStart: processStart,
          totalDuration: processingTime,
          priorContinuousUsage:
              _machineContinuousUsage[machineId] ?? Duration.zero,
          interruptible: job.isInterruptibleOnMachine(machineId),
        );
        final DateTime endTime = schedule.completionTime;
        final Duration delay = endTime.isAfter(job.dueDate)
            ? endTime.difference(job.dueDate)
            : Duration.zero;

        // Choose the machine that minimises delay, breaking ties on end time.
        if (bestSchedule == null ||
            delay < bestDelay ||
            (delay == bestDelay && endTime.isBefore(bestSchedule.completionTime))) {
          bestMachineId = machineId;
          bestProcessStart = processStart;
          bestSchedule = schedule;
          bestDelay = delay;
        }
      }

      if (bestMachineId != -1 && bestSchedule != null) {
        final bestEndTime = bestSchedule.completionTime;

        machineAvailable[bestMachineId] = bestEndTime;
        machines[bestMachineId]?.add(Tuple2(bestProcessStart, bestEndTime));
        // ── Update last-state so the next job on this machine sees the correct
        //    "from" state in the setup matrix.
        _machineLastState[bestMachineId] = job.stateOnMachine(bestMachineId);
        // A pause anywhere within this job's segments already reset the
        // continuity streak; otherwise accumulate onto the running streak.
        _machineContinuousUsage[bestMachineId] = bestSchedule.segments.length > 1
            ? bestSchedule.segments.last.duration
            : (_machineContinuousUsage[bestMachineId] ?? Duration.zero) +
                bestSchedule.segments.single.duration;

        output.add(ParallelOutput(
          job.jobId,
          bestMachineId,
          bestProcessStart,
          bestEndTime,
          bestDelay,
          job.dueDate,
          segments: bestSchedule.segments,
        ));
      }
    }
  }

  // ── Fitness / metric helpers ───────────────────────────────────────────────
  void _clearSchedule() {
      output.clear();
      machines.updateAll((key, value) => []);
    }

  double _averageProcessingTime(ParallelInput job) {
    return job.durationsInMachines.values.fold(0, (s, d) => s + d.inMinutes) /
        job.durationsInMachines.length;
  }

  int _slack(ParallelInput job) {
    final remaining = job.dueDate.difference(job.availableDate).inMinutes;
    final processing = job.durationsInMachines.values.fold(0, (s, d) => s + d.inMinutes);
    return remaining - processing;
  }



  double _criticalRatio(ParallelInput job) {
    final remaining = job.dueDate.difference(job.availableDate).inMinutes;
    final processing = job.durationsInMachines.values.fold(0, (s, d) => s + d.inMinutes);
    return processing == 0 ? double.infinity : remaining / processing;
  }

  double _atcPriority(ParallelInput job, DateTime currentTime) {
    const k = 2.0;
    final avg = _averageProcessingTime(job);
    final processing = job.durationsInMachines.values.fold(0, (s, d) => s + d.inMinutes);
    final remaining = job.dueDate.difference(currentTime).inMinutes;
    final tardiness = remaining > 0 ? remaining / (k * avg) : 0;
    return (1 / processing) * exp(-tardiness);
  }

  double calculateWSPT(ParallelInput job) {
    final minMs = job.durationsInMachines.values
        .reduce((a, b) => a < b ? a : b)
        .inMilliseconds;
    return job.priority / minMs;
  }

  // ── Working-schedule helpers ───────────────────────────────────────────────

  DateTime _adjustForWorkingSchedule(DateTime start) {
    final ws = workingSchedule.value1;
    final we = workingSchedule.value2;
    if (start.hour < ws.hour || (start.hour == ws.hour && start.minute < ws.minute)) {
      return DateTime(start.year, start.month, start.day, ws.hour, ws.minute);
    } else if (start.hour > we.hour || (start.hour == we.hour && start.minute > we.minute)) {
      return DateTime(start.year, start.month, start.day + 1, ws.hour, ws.minute);
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, Duration duration) {
    final we = workingSchedule.value2;
    final ws = workingSchedule.value1;
    final endOfDay = DateTime(start.year, start.month, start.day, we.hour, we.minute);
    final endTime = start.add(duration);
    if (endTime.isAfter(endOfDay)) {
      final remaining = endTime.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, ws.hour, ws.minute).add(remaining);
    }
    return endTime;
  }

  void printOutput() {
    for (final out in output) {
      print('Job ${out.jobId} → Machine ${out.machineId} | '
          'Start: ${out.startDate} | End: ${out.endDate} | '
          'Delay: ${out.delay.inMinutes} min | Due: ${out.dueDate}');
    }
  }

  // ── Genetic algorithm ─────────────────────────────────────────────────────

  void geneticsRule() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN PARALLEL MACHINES");

    const int populationSize = 5; // Reduced from 10
    const int generations = 10; // Reduced from 25
    const double mutationRate = 0.1;

    List<List<ParallelInput>> population = _initializePopulation(populationSize);
    List<ParallelInput> bestIndividual = [];
    Duration bestFitness = const Duration(days: 9999);

    for (int generation = 0; generation < generations; generation++) {
      final evaluated = population.map((ind) => Tuple2(ind, _evaluateFitness(ind))).toList();
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    inputJobs = bestIndividual;
    _assignJobsToMachines();
  }

  List<List<ParallelInput>> _initializePopulation(int size) {
    return List.generate(size, (_) {
      final shuffled = List<ParallelInput>.from(inputJobs);
      shuffled.shuffle();
      return shuffled;
    });
  }

  /// Evaluates makespan for a candidate sequence, including setup times.
  ///
  /// Uses a local copy of last-states so that the evaluation is pure (it does
  /// not mutate [_machineLastState]).
  Duration _evaluateFitness(List<ParallelInput> jobSequence) {
    final Map<int, DateTime> machineAvail = {
      for (final id in machines.keys) id: startDate,
    };
    // Local tracking of last state per machine for this evaluation only.
    final Map<int, String?> localLastState = {
      for (final id in machines.keys) id: null,
    };

    DateTime latestEnd = startDate;

    for (final job in jobSequence) {
      DateTime bestEnd = DateTime(9999);
      int bestMachineId = -1;

      for (final entry in job.durationsInMachines.entries) {
        final machineId = entry.key;
        final processing = entry.value;

        DateTime candidateStart = job.availableDate.isAfter(machineAvail[machineId]!)
            ? job.availableDate
            : machineAvail[machineId]!;
        candidateStart = _adjustForWorkingSchedule(candidateStart);

        final toState = job.stateOnMachine(machineId);
        final setup = _setupDuration(machineId, localLastState[machineId], toState);
        final DateTime processStart = setup > Duration.zero
            ? _adjustForWorkingSchedule(candidateStart.add(setup))
            : candidateStart;

        final DateTime end = _adjustEndTimeForWorkingSchedule(processStart, processing);

        if (end.isBefore(bestEnd)) {
          bestEnd = end;
          bestMachineId = machineId;
        }
      }

      if (bestMachineId != -1) {
        machineAvail[bestMachineId] = bestEnd;
        localLastState[bestMachineId] = job.stateOnMachine(bestMachineId);
        if (bestEnd.isAfter(latestEnd)) latestEnd = bestEnd;
      }
    }

    return latestEnd.difference(startDate);
  }

  List<List<ParallelInput>> _generateNewPopulation(
    List<Tuple2<List<ParallelInput>, Duration>> evaluated,
    int size,
    double mutationRate,
  ) {
    return List.generate(size, (_) {
      final p1 = _selectParent(evaluated);
      final p2 = _selectParent(evaluated);
      var child = _crossover(p1, p2);
      if (Random().nextDouble() < mutationRate) child = _mutate(child);
      return child;
    });
  }

  List<ParallelInput> _selectParent(List<Tuple2<List<ParallelInput>, Duration>> evaluated) {
    const k = 5;
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<ParallelInput> _crossover(List<ParallelInput> p1, List<ParallelInput> p2) {
    final length = p1.length;
    final point = Random().nextInt(length);
    final taken = p1.sublist(0, point).map((j) => j.jobId).toSet();
    return [...p1.sublist(0, point), ...p2.where((j) => !taken.contains(j.jobId))];
  }

  List<ParallelInput> _mutate(List<ParallelInput> ind) {
    if (ind.length < 2) return ind;
    final i = Random().nextInt(ind.length);
    final j = Random().nextInt(ind.length);
    final tmp = ind[i];
    ind[i] = ind[j];
    ind[j] = tmp;
    return ind;
  }



   //[maquina donde procesa el trabajo]-[inico]-[final teorico]
  DateTime _adjustEndTimeWithInactivities(int machineId, DateTime start, DateTime naiveEnd) {
    final schedule = _engineByMachine[machineId]!.computeSegments(
      earliestStart: start,
      totalDuration: naiveEnd.difference(start),
      priorContinuousUsage: Duration.zero,
      interruptible: true, // se puede interumpir
    );
    return schedule.completionTime; // horario real de terminacion 
  }

  // Mejor solucion 
  List<List<ParallelInput>> _seedSolutions() {
    List<ParallelInput> sortedBy(
        int Function(ParallelInput, ParallelInput) cmp) {
      return List<ParallelInput>.from(inputJobs)..sort(cmp);
    }

    return [
      sortedBy((a, b) =>
          _averageProcessingTime(a).compareTo(_averageProcessingTime(b))),
      sortedBy((a, b) =>
          _averageProcessingTime(b).compareTo(_averageProcessingTime(a))),
      sortedBy((a, b) => a.dueDate.compareTo(b.dueDate)),
      sortedBy((a, b) => a.availableDate.compareTo(b.availableDate)),
      sortedBy((a, b) => _slack(a).compareTo(_slack(b))),
      sortedBy((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b))),
      sortedBy((a, b) =>
          _atcPriority(b, startDate).compareTo(_atcPriority(a, startDate))),
      sortedBy((a, b) => calculateWSPT(b).compareTo(calculateWSPT(a))),
      List<ParallelInput>.from(inputJobs),
    ];
  }

  // Total flow de una sola maquina Σ (Cj - rj)
  Duration _machineFlow(int machineId, List<ParallelInput> sequence) {
  DateTime available = startDate; // Fecha de inicio de la maquina 
  String? lastState; // ultimo estado 
  int processedCount = 0; // numero de procesos para ver lo de procesos continuos 
  Duration flow = Duration.zero; // calculo del flujo total 

  for (final job in sequence) {
    final Duration? processingTime = job.durationsInMachines[machineId]; // busca cuanto tarda y si se puede porcesar en esa maquina 
    if (processingTime == null) {
      continue; 
    }// permite revisar todos los trabajos

    DateTime candidateStart =job.availableDate.isAfter(available) ? job.availableDate : available;candidateStart = _adjustForWorkingSchedule(candidateStart); // Ajusta la hora de inico a las inactividades 

    final String toState = job.stateOnMachine(machineId);
    final Duration setup = _setupDuration(machineId, lastState, toState); // cuanto tarda en iniciar la maquina 
    final DateTime processStart = setup > Duration.zero  // incio real considerando inactivades 
        ? _adjustForWorkingSchedule(candidateStart.add(setup))
        : candidateStart;

    final DateTime endTime = _adjustEndTimeWithInactivities(
        machineId, processStart, processStart.add(processingTime));

    flow += endTime.difference(job.availableDate); // C_j − r_j se calcula el flujo total 

    DateTime finalEnd = endTime; // la desocupa 
    final capacity = machineContinueCapacity[machineId] ?? 0; // revisa proceamientos continuos 
    final restTime = machineRestTime[machineId];
    if (capacity > 0 && restTime != null) {
      processedCount++; // aumenta procesos continuos 
      if (processedCount >= capacity) {
        finalEnd = endTime.add(restTime); // se le aplica descanso 
        processedCount = 0;
      }
    }
    available = finalEnd; // ajuste de la disponibilidad 
    lastState = job.stateOnMachine(machineId);
  }

  return flow;
}


  /// Tardiness (vs. dueDate) of each job within a single machine's sequence,
  /// using the same simulation as [_machineFlow]. Used by the inter-machine
  /// branch to prioritise the most delayed jobs when choosing what to move.
  /// 
  /// 
  /// "¿Cuánto se retraso cada  trabajo?"
  Map<ParallelInput, Duration> _machineJobDelays(
    int machineId, List<ParallelInput> sequence) {
  DateTime available = startDate;
  String? lastState;
  int processedCount = 0;
  final Map<ParallelInput, Duration> delays = {};

  for (final job in sequence) {
    final Duration? processingTime = job.durationsInMachines[machineId];
    if (processingTime == null) continue;

    DateTime candidateStart =
        job.availableDate.isAfter(available) ? job.availableDate : available;
    candidateStart = _adjustForWorkingSchedule(candidateStart);

    final String toState = job.stateOnMachine(machineId);
    final Duration setup = _setupDuration(machineId, lastState, toState);
    final DateTime processStart = setup > Duration.zero
        ? _adjustForWorkingSchedule(candidateStart.add(setup))
        : candidateStart;

    final DateTime endTime = _adjustEndTimeWithInactivities(
        machineId, processStart, processStart.add(processingTime));

    delays[job] = endTime.isAfter(job.dueDate)
        ? endTime.difference(job.dueDate)
        : Duration.zero;

    DateTime finalEnd = endTime;
    final capacity = machineContinueCapacity[machineId] ?? 0;
    final restTime = machineRestTime[machineId];
    if (capacity > 0 && restTime != null) {
      processedCount++;
      if (processedCount >= capacity) {
        finalEnd = endTime.add(restTime);
        processedCount = 0;
      }
    }

    available = finalEnd;
    lastState = job.stateOnMachine(machineId);
  }

  return delays;
}

Duration _totalFlow(Map<int, List<ParallelInput>> assignment) {
  Duration total = Duration.zero;
  for (final entry in assignment.entries) {
    total += _machineFlow(entry.key, entry.value);
  }
  return total;
}

// ----------------------------------------------------------------------------
// Construye el output real (ParallelOutput por job) directamente desde una
// asignación por máquina ya decidida (bestAssignment). A diferencia de
// _assignJobsToMachines(), aquí NO se vuelve a elegir la máquina de cada
// job: se respeta la que decidió la búsqueda y solo se recalculan los
// tiempos (setup / horario laboral / inactividades / descanso), con la
// misma lógica que _machineFlow. Esto es lo que evita que las reubicaciones
// inter-máquina del TS se pierdan al comitear.
// ----------------------------------------------------------------------------


// mejor solucion encontrada por el tabu 
void _commitBestAssignment(Map<int, List<ParallelInput>> assignment) {
  for (final entry in assignment.entries) {
    final int machineId = entry.key;
    final List<ParallelInput> sequence = entry.value;

    DateTime available = startDate;
    String? lastState;
    int processedCount = 0;

    for (final job in sequence) {
      final Duration? processingTime = job.durationsInMachines[machineId];
      if (processingTime == null) continue; 

      DateTime candidateStart =
          job.availableDate.isAfter(available) ? job.availableDate : available;
      candidateStart = _adjustForWorkingSchedule(candidateStart);

      final String toState = job.stateOnMachine(machineId);
      final Duration setup = _setupDuration(machineId, lastState, toState);
      final DateTime processStart = setup > Duration.zero
          ? _adjustForWorkingSchedule(candidateStart.add(setup))
          : candidateStart;

      final DateTime endTime = _adjustEndTimeWithInactivities(
          machineId, processStart, processStart.add(processingTime));
      final Duration delay = endTime.isAfter(job.dueDate)
          ? endTime.difference(job.dueDate)
          : Duration.zero;

      output.add(ParallelOutput(
        job.jobId,
        machineId,
        processStart,
        endTime,
        delay,
        job.dueDate,
      ));

      DateTime finalEnd = endTime;
      final capacity = machineContinueCapacity[machineId] ?? 0;
      final restTime = machineRestTime[machineId];
      if (capacity > 0 && restTime != null) {
        processedCount++;
        if (processedCount >= capacity) {
          finalEnd = endTime.add(restTime);
          processedCount = 0;
        }
      }

      available = finalEnd;
      lastState = job.stateOnMachine(machineId);
    }
  }
}

// ----------------------------------------------------------------------------
// Asignación greedy por máquina a partir de una secuencia global — mismo
// criterio que evaluateFlujoTotalParallel (menor retraso, desempate por fin
// más temprano). Solo se usa para construir el punto de partida (semillas)
// en formato "assignment" (Map<int, List<ParallelInput>>).
// ----------------------------------------------------------------------------
Map<int, List<ParallelInput>> _greedyAssign(List<ParallelInput> sequence) {
  final Map<int, DateTime> machineAvailable = {
    for (final id in machines.keys) id: startDate,
  };
  final Map<int, String?> lastState = {
    for (final id in machines.keys) id: null,
  };
  final Map<int, int> processedCount = {
    for (final id in machines.keys) id: 0,
  };
  final Map<int, List<ParallelInput>> assignment = {
    for (final id in machines.keys) id: <ParallelInput>[], // Se guardan los jobs asigandos a cada maquina 
  };

  for (final job in sequence) {
    int bestMachineId = -1;
    DateTime bestEndTime = startDate;
    Duration bestDelay = const Duration(days: 99999);

    for (final entry in job.durationsInMachines.entries) { // probar todas las maquinas donde se puede procesar el job 
      final int machineId = entry.key;
      final Duration processingTime = entry.value;
      final DateTime? freeAt = machineAvailable[machineId];
      if (freeAt == null) continue;

      DateTime candidateStart =
          job.availableDate.isAfter(freeAt) ? job.availableDate : freeAt; // Cuando esta  disponible 
      candidateStart = _adjustForWorkingSchedule(candidateStart); // ajusta los horarios 

      final String toState = job.stateOnMachine(machineId); 
      final Duration setup =
          _setupDuration(machineId, lastState[machineId], toState); // setup hace referencia a el tiempo entre estados que tarda 
      final DateTime processStart = setup > Duration.zero
          ? _adjustForWorkingSchedule(candidateStart.add(setup)) // comprueba horaio laboral 
          : candidateStart;
      final DateTime endTime = _adjustEndTimeWithInactivities(machineId, processStart, processStart.add(processingTime)); // cuando termina 
      final Duration delay = endTime.isAfter(job.dueDate) // retraso 
          ? endTime.difference(job.dueDate)
          : Duration.zero;

      if (bestMachineId == -1 || delay < bestDelay || (delay == bestDelay && endTime.isBefore(bestEndTime))) { // revisa el delay y el criterio de desempate es el flow 
        bestMachineId = machineId;
        bestEndTime = endTime;
        bestDelay = delay;
      }
    }

    if (bestMachineId == -1) continue;

    assignment[bestMachineId]!.add(job); // se le asigna el job a esa maquina 

    DateTime finalEnd = bestEndTime;
    final capacity = machineContinueCapacity[bestMachineId] ?? 0;
    final restTime = machineRestTime[bestMachineId];
    if (capacity > 0 && restTime != null) { // compureba el descanso 
      processedCount[bestMachineId] = processedCount[bestMachineId]! + 1; // aumenta la capacidad y revisa si llego 
      if (processedCount[bestMachineId]! >= capacity) {
        finalEnd = bestEndTime.add(restTime); // añade descanso pertienente 
        processedCount[bestMachineId] = 0;
      }
    }

    machineAvailable[bestMachineId] = finalEnd;
    lastState[bestMachineId] = job.stateOnMachine(bestMachineId);
  }

  return assignment;
}

Map<int, List<ParallelInput>> _deepCopyAssignment(
    Map<int, List<ParallelInput>> assignment) {
  return {
    for (final entry in assignment.entries)
      entry.key: List<ParallelInput>.from(entry.value),
  };
}

bool _sameOrder(List<ParallelInput> a, List<ParallelInput> b) {
  if (a.length != b.length) return false;
  for (int k = 0; k < a.length; k++) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

// ----------------------------------------------------------------------------
// RAMA INTRA-MÁQUINA — estrategia de primera mejora.
// Reubica un job dentro de la misma máquina y se detiene en el primer
// movimiento admisible que mejore el F(current) actual.
// ----------------------------------------------------------------------------




//Primera mejora No busca obligatoriamente el mejor movimiento posible.Busca el primer movimiento válido que mejore la solución actual.
_TabuCandidate? _bestIntraMove({
  required Map<int, List<ParallelInput>> assignment, // trabajos de cada maquina 
  required Map<int, Duration> flowCache, // tiempo de cada maquina 
  required int currentTotalMinutes,
  required Map<String, int> tabuList,
  required int iter, 
  required int bestTotalMinutes,
  required Map<ParallelInput, int> uid, //Asigna un identificador único a cada trabaj
  required Random random,
  required int maxAttempts, // maximo numero que se puede probar 
}) {
  final machineIds =
      assignment.keys.where((m) => assignment[m]!.length > 1).toList() // Filtra únicamente las máquinas que tienen más de un trabajo. y mezla el orden de las maquinas 
        ..shuffle(random);
  if (machineIds.isEmpty) return null;

  int attempts = 0;
  for (final machineId in machineIds) {
    final List<ParallelInput> seq = assignment[machineId]!; // obtiene los jobs de la maquina actual 
    final positions = List<int>.generate(seq.length, (i) => i)..shuffle(random); // revuelve los jobs 

    for (final i in positions) { // apenas encuntra una mejora deja esa iteracion 
      final ParallelInput moved = seq[i]; // elige mover un job extra ese job 
      final List<ParallelInput> without = List<ParallelInput>.from(seq) // crea una copia donde de los jobs y elimina el seq[i]
        ..removeAt(i);
      final slots = List<int>.generate(without.length + 1, (k) => k)..shuffle(random); // lista de las posiciones donde se podria insertar 

      for (final j in slots) {
        attempts++;
        if (attempts > maxAttempts) return null;

        final List<ParallelInput> trial = List<ParallelInput>.from(without) // guarda la secuencia en trial 
          ..insert(j, moved); // se inserta el job en la posicion indicada 
        if (_sameOrder(trial, seq)) continue; // revisa que no esten en el mismo campo 

        final Duration newFlow = _machineFlow(machineId, trial); // calculo el flow de la maquina 
        final int deltaMinutes = newFlow.inMinutes - (flowCache[machineId]?.inMinutes ?? 0); // compara los tiempos de las soluciones 
        final int candidateTotal = currentTotalMinutes + deltaMinutes; // considera tambien el tiempo general de la solucion de las otras maquinas para que sea efectiva del = a negativa 

        // Primera mejora: solo interesa si supera al current, no al best.
        if (candidateTotal >= currentTotalMinutes) continue; // revisa el total de la mejor y la actual 

        final int jobA = uid[moved]!; // conseguir el id 
        final int jobB = j > 0
            ? uid[trial[j - 1]]! // busca un trabajo adyacente  si es mayor el de atras si es menos y si es 0 el de adelante 
            : (trial.length > 1 ? uid[trial[1]]! : jobA);
        final String attribute =
            jobA < jobB ? 'intra:${jobA}_$jobB' : 'intra:${jobB}_$jobA'; // crea movimento tabu 

        final bool isTabu = (tabuList[attribute] ?? -1) > iter;  // revisa si es un mov tabu 
        final bool aspiration = candidateTotal < bestTotalMinutes; // permite aunque sea tabu 
        if (isTabu && !aspiration) continue;
        // devuelve el candidato 
        // los movimientos tabu son una mezcla entre jb movido y le adyacente 
        return _TabuCandidate(
          isIntra: true,
          machineA: machineId,
          newSequenceA: trial,
          newFlowA: newFlow,
          attribute: attribute,
          totalMinutesAfter: candidateTotal,
        );
      }
    }
  }
  return null;
}

// ----------------------------------------------------------------------------
// RAMA INTER-MÁQUINA — estrategia de mejor mejora.
// Saca un job de su máquina origen, prueba las máquinas destino elegibles
// ordenadas por apalancamiento (menor carga primero) y, para cada una,
// todos los k+1 huecos de inserción. Se queda con el mejor candidato
// admisible; si todos están vetados, aplica la aspiración de "todo es tabú".
// ----------------------------------------------------------------------------
_TabuCandidate? _bestInterMove({
  required Map<int, List<ParallelInput>> assignment,
  required Map<int, Duration> flowCache, // duracion de las maquinas previas 
  required int currentTotalMinutes,
  required Map<String, int> tabuList,
  required int iter,
  required int bestTotalMinutes,
  required Map<ParallelInput, int> uid,
  required Map<ParallelInput, int> currentMachineOf,
  required Map<ParallelInput, Duration> jobDelay,
  required Random random,
  required int jobSamples,
  required int maxDestinations,
}) {
  final allJobs = currentMachineOf.keys.toList()..shuffle(random); // saca todos los jobs y los mezcla 
  allJobs.sort((a, b) =>
      (jobDelay[b] ?? Duration.zero).compareTo(jobDelay[a] ?? Duration.zero)); // ordena por retraso de mayor a menor 
  final sampled = allJobs.take(jobSamples); //  toma alguno de los jobs con mayor retraso

  _TabuCandidate? bestAdmissible;
  _TabuCandidate? bestOverall; // ignorando tabú, para el fallback "todo es tabú"

  for (final job in sampled) {
    final int machineFrom = currentMachineOf[job]!; // de que maquina viene 
    final List<ParallelInput> seqFrom = assignment[machineFrom]!; // secuencia de orrigen 
    final List<ParallelInput> without = List<ParallelInput>.from(seqFrom) // quita el job 
      ..remove(job);
    final Duration newFlowFrom = _machineFlow(machineFrom, without); // calcula el flow de la maquina 

    final eligible = job.durationsInMachines.keys.where((m) => m != machineFrom && assignment.containsKey(m)).toList()..sort((a, b) => (flowCache[a]?.inMinutes ?? 0)
          .compareTo(flowCache[b]?.inMinutes ?? 0)); // apalancamiento encotrar las maquinas donde puede procesarse (Revisar )  y ordena las maqiinas difernetes por flow 

    for (final machineTo in eligible.take(maxDestinations)) { // cuantas maquinas de destino probar 
      final List<ParallelInput> seqTo = assignment[machineTo]!; // obtiene la secuencia de destino 
 // prueba todas las combinaciones del job extraido 
      for (int slot = 0; slot <= seqTo.length; slot++) {
        final List<ParallelInput> trialTo = List<ParallelInput>.from(seqTo) // crear la secuencia final
          ..insert(slot, job);
        final Duration newFlowTo = _machineFlow(machineTo, trialTo); // se calcula el flow 

        final int deltaMinutes = (newFlowFrom.inMinutes -
                (flowCache[machineFrom]?.inMinutes ?? 0)) +  // compara el flow de la nueva y viaja con y sin job 
            (newFlowTo.inMinutes - (flowCache[machineTo]?.inMinutes ?? 0));
        final int candidateTotal = currentTotalMinutes + deltaMinutes; // el total del candidato y ompara con lo que le llega 

        final String attribute =
            'inter:${uid[job]}:${machineFrom}_$machineTo';
        final bool isTabu = (tabuList[attribute] ?? -1) > iter; // se guarda como la id maquina y id job 
        final bool aspiration = candidateTotal < bestTotalMinutes;

        final candidate = _TabuCandidate(
          isIntra: false,
          machineA: machineFrom,
          machineB: machineTo,
          newSequenceA: without,
          newSequenceB: trialTo,
          newFlowA: newFlowFrom,
          newFlowB: newFlowTo,
          attribute: attribute,
          totalMinutesAfter: candidateTotal,
        );

        if (bestOverall == null ||
            candidate.totalMinutesAfter < bestOverall.totalMinutesAfter) {
          bestOverall = candidate;
        }
        if ((!isTabu || aspiration) &&
            (bestAdmissible == null ||
                candidate.totalMinutesAfter < bestAdmissible.totalMinutesAfter)) {
          bestAdmissible = candidate;
        }
      }
    }
  }

  // Aspiración por "todo es tabú".
  return bestAdmissible ?? bestOverall;
}

// ----------------------------------------------------------------------------
// BUCLE PRINCIPAL
// ----------------------------------------------------------------------------
void tabuSearchRule({int seed = 20260806, int timeBudgetMs = 4000}) { // busacr hasta 4 segundos 
  if (inputJobs.length < 2) {
    _clearSchedule();
    _assignJobsToMachines();  // busac donde hayan varios trabajo
    return;
  }

  final int n = inputJobs.length; // tamalno de jobs 
  final Random random = Random(seed);
  final Stopwatch watch = Stopwatch()..start(); // cuenta el tiempo de ejecucion del tabu search 

  final int maxIterations = min(1000, max(300, 20 * n)); // es el calculo de tamaño por el numero de jobs 
  final int intraAttempts = max(20, 4 * n);
  final int interJobSamples = max(3, n ~/ 8); // cuantos jobs se considran
  const int maxDestinations = 3; // destinos que prueba el job 

  final int tenureBase = sqrt(n).round().clamp(2, n); // cuanto un movimiento permanece tabu 
  final int minTenure = max(2, tenureBase - 1);
  final int maxTenure = tenureBase + 2;
  final int shortTenure = max(1, tenureBase ~/ 2);

  final int s1 = max(15, n); // estancamiento -> intensificar
  final int s2 = max(30, 3 * n); // estancamiento -> diversificar

  final Map<ParallelInput, int> uid = {
    for (int k = 0; k < n; k++) inputJobs[k]: k, // se le asigan ids unicos a cada trabajos 
  };

  // --- Semillas: se evalúan las 9 reglas de despacho + orden recibido ---
  Map<int, List<ParallelInput>> bestAssignment = _greedyAssign(inputJobs);
  int bestTotalMinutes = _totalFlow(bestAssignment).inMinutes;
  final int initialFitness = bestTotalMinutes;

  for (final seedSequence in _seedSolutions()) {
    final candidateAssignment = _greedyAssign(seedSequence); // se evalua cada solucion en greeedy
    final candidateTotal = _totalFlow(candidateAssignment).inMinutes; // se le saca el flujo total 
    if (candidateTotal < bestTotalMinutes) {
      bestAssignment = candidateAssignment;
      bestTotalMinutes = candidateTotal; // toma la mejor solucion de reglas 
    }
  }

  Map<int, List<ParallelInput>> currentAssignment = // copia 
      _deepCopyAssignment(bestAssignment);
  int currentTotalMinutes = bestTotalMinutes;

  final Map<int, Duration> flowCache = { 
    for (final entry in currentAssignment.entries)
      entry.key: _machineFlow(entry.key, entry.value),
  }; // el flujo tootal de cada maquina 

  final Map<ParallelInput, int> currentMachineOf = {
    for (final entry in currentAssignment.entries)
      for (final job in entry.value) job: entry.key,
  };
// en que job esta cada maquina 
  final Map<ParallelInput, Duration> jobDelay = {};
  for (final entry in currentAssignment.entries) {
    jobDelay.addAll(_machineJobDelays(entry.key, entry.value));
  }
  // calculo del retraso de cada Job

  final Map<String, int> tabuList = {};
  final Map<String, int> moveFrequency = {}; // memoria de largo plazo
  int noImprove = 0;
  int iter = 0;
  bool intensifying = false;

  while (iter < maxIterations && watch.elapsedMilliseconds < timeBudgetMs) { // tiempo menor y iteraciones menor misma iteracion saca dos rams 
    final intraCandidate = _bestIntraMove(
      assignment: currentAssignment,
      flowCache: flowCache,
      currentTotalMinutes: currentTotalMinutes,
      tabuList: tabuList,
      iter: iter,
      bestTotalMinutes: bestTotalMinutes,
      uid: uid,
      random: random,
      maxAttempts: intraAttempts,
    );

    final interCandidate = _bestInterMove(
      assignment: currentAssignment,
      flowCache: flowCache,
      currentTotalMinutes: currentTotalMinutes,
      tabuList: tabuList,
      iter: iter,
      bestTotalMinutes: bestTotalMinutes,
      uid: uid,
      currentMachineOf: currentMachineOf,
      jobDelay: jobDelay,
      random: random,
      jobSamples: interJobSamples,
      maxDestinations: maxDestinations,
    );

    _TabuCandidate? chosen;
    if (intraCandidate != null && interCandidate != null) { // escoje el menor de ambos candidatos 
      chosen = intraCandidate.totalMinutesAfter <= interCandidate.totalMinutesAfter
          ? intraCandidate
          : interCandidate;
    } else {
      chosen = intraCandidate ?? interCandidate;
    }

    if (chosen == null) { // si no hay mejora iteracion . improve +1 
      iter++;
      noImprove++;
      continue;
    }

    // --- Aplicar el movimiento elegido ---
    currentAssignment[chosen.machineA] = chosen.newSequenceA; // Actualiza la maquina 
    flowCache[chosen.machineA] = chosen.newFlowA; // actualiza el flow 
    jobDelay.addAll(_machineJobDelays(chosen.machineA, chosen.newSequenceA)); // Actualiza los retrasos 
    if (!chosen.isIntra) {
      currentAssignment[chosen.machineB!] = chosen.newSequenceB!;
      flowCache[chosen.machineB!] = chosen.newFlowB!; // Actualiza la lamquina a la que se le saca 
      jobDelay.addAll(_machineJobDelays(chosen.machineB!, chosen.newSequenceB!));
      for (final job in chosen.newSequenceB!) {
        currentMachineOf[job] = chosen.machineB!;
      }
    }
    currentTotalMinutes = chosen.totalMinutesAfter; // actualiza el total de la solcion global 

    // --- Registrar atributo tabú (tenencia dinámica ~ √n) ---
    final int tenure = intensifying // verifica si esta intensificando 
        ? shortTenure
        : minTenure + random.nextInt(maxTenure - minTenure + 1); // en el ternure puede salir cualquiera entre maximo y minimo 
    tabuList[chosen.attribute] = iter + tenure;
    moveFrequency[chosen.attribute] =(moveFrequency[chosen.attribute] ?? 0) + 1; //  Guardar la frecuencia de los moviminetos tabu 
    if (iter % 25 == 0) {
      tabuList.removeWhere((_, expiration) => expiration <= iter);
    } // eliminan movimientso tabu expirados 

    // --- ¿F(S') < F(best)? ---
    if (currentTotalMinutes < bestTotalMinutes) {
      // Recalcular exacto antes de aceptar (protege contra deriva de caché).
      final verified = _totalFlow(currentAssignment).inMinutes; // revisa el nuevo flujo ganadador 
      currentTotalMinutes = verified;
      if (verified < bestTotalMinutes) {
        bestTotalMinutes = verified; // guarda la nueva solucion 
        bestAssignment = _deepCopyAssignment(currentAssignment);
        noImprove = 0;
        intensifying = false;
      } else {
        noImprove++;
      }
    } else {
      noImprove++;
    }

    // --- Control de estancamiento ---
    if (noImprove == s1) {
      // Intensificar: current <- best, tenencia corta.
      currentAssignment = _deepCopyAssignment(bestAssignment);
      currentTotalMinutes = bestTotalMinutes;
      for (final entry in currentAssignment.entries) {
        flowCache[entry.key] = _machineFlow(entry.key, entry.value);
        jobDelay.addAll(_machineJobDelays(entry.key, entry.value));
        for (final job in entry.value) {
          currentMachineOf[job] = entry.key;
        }
      }
      intensifying = true;
    } else if (noImprove >= s2) { 
      // Diversificar: penaliza los atributos más frecuentes y perturba.
      final frequentAttributes = moveFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in frequentAttributes.take(5)) { // penaliza los 5 movimiento mas usados 
        tabuList[entry.key] = iter + maxTenure * 2;
      } // penaliza los movimientos muy frecuentes 

      currentAssignment = _deepCopyAssignment(bestAssignment);
      final machineIds = currentAssignment.keys.toList();
      for (int p = 0; p < max(2, n ~/ 6); p++) { // perturba la solucion  saca y mete jobs de usu maquinas en otras 
        final from = machineIds[random.nextInt(machineIds.length)];// maquinas 
        if (currentAssignment[from]!.isEmpty) continue;
        final job = currentAssignment[from]! // los jobs 
            .removeAt(random.nextInt(currentAssignment[from]!.length)); // remueve uno 
        final eligibleTargets =
            job.durationsInMachines.keys.where((m) => m != from).toList(); // mauinas donde se pueda trabajar 
        if (eligibleTargets.isEmpty) {
          currentAssignment[from]!.add(job);
          continue;
        }
        final to = eligibleTargets[random.nextInt(eligibleTargets.length)]; // eleige una mauina destino aleatoriamente 
        final insertAt = random.nextInt(currentAssignment[to]!.length + 1); // posicion aleatoria 
        currentAssignment[to]!.insert(insertAt, job); // inserta 
      }

      for (final entry in currentAssignment.entries) { // actualiza todo 
        flowCache[entry.key] = _machineFlow(entry.key, entry.value); 
        jobDelay.addAll(_machineJobDelays(entry.key, entry.value));
        for (final job in entry.value) {
          currentMachineOf[job] = entry.key;
        }
      }
      // recalcula el total 
      currentTotalMinutes = _totalFlow(currentAssignment).inMinutes;
      // borra la lisat tabu  (REVISAR )
      tabuList.clear();
      noImprove = 0;
      intensifying = false;
    }

    iter++;
  }

  // _assignJobsToMachines() would re-pick each job's machine on its own
  // greedy logic, discarding the inter-machine moves the search just made —
  // so the output is built directly from bestAssignment instead.
  _clearSchedule();
  jobsInMachines = bestAssignment;
  inputJobs = [
    for (final machineId in bestAssignment.keys) ...bestAssignment[machineId]!
  ];
  _commitBestAssignment(bestAssignment);

  watch.stop();
  final String mejora = initialFitness == 0
      ? '0.0'
      : ((initialFitness - bestTotalMinutes) * 100 / initialFitness)
          .toStringAsFixed(1);
  print('[TABU parallel intra/inter] n=$n · iteraciones=$iter · '
      '${watch.elapsedMilliseconds} ms');
  print('[TABU parallel intra/inter] flujo total: $initialFitness min → '
      '$bestTotalMinutes min ($mejora% de mejora)');
}
}