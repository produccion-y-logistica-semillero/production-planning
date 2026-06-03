import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
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

  ParallelInput(
    this.jobId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.durationsInMachines, {
    this.jobState = 'A',
    this.jobStatesByMachine,
  });

  String stateOnMachine(int machineId) =>
      jobStatesByMachine?[machineId] ?? jobState;
}

class ParallelOutput {
  final int jobId;
  final int machineId;
  final DateTime startDate;
  final DateTime endDate;
  final Duration delay;
  final DateTime dueDate;

  ParallelOutput(
    this.jobId,
    this.machineId,
    this.startDate,
    this.endDate,
    this.delay,
    this.dueDate,
  );
}

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<ParallelInput> inputJobs = [];
  Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
  List<ParallelOutput> output = [];

  // ── Setup-time state ──────────────────────────────────────────────────────
  // stateSetupMatrix: machineId → fromState → toState → minutes
  // Mirrors the structure used by Flow Shop / Flexible Job Shop / Open Shop.
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;

  // Tracks which job-state each machine processed last (null = cold start).
  final Map<int, String?> _machineLastState = {};

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule, {
    this.stateSetupMatrix,
  }) {
    // Initialise cold-start tracking for every machine.
    for (final machineId in machines.keys) {
      _machineLastState[machineId] = null;
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
      DateTime bestEndTime = DateTime.now();
      Duration bestDelay = const Duration(days: 99999);

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

        final DateTime endTime = _adjustEndTimeForWorkingSchedule(processStart, processingTime);
        final Duration delay = endTime.isAfter(job.dueDate)
            ? endTime.difference(job.dueDate)
            : Duration.zero;

        // Choose the machine that minimises delay, breaking ties on end time.
        if (delay < bestDelay || (delay == bestDelay && endTime.isBefore(bestEndTime))) {
          bestMachineId = machineId;
          bestProcessStart = processStart;
          bestEndTime = endTime;
          bestDelay = delay;
        }
      }

      if (bestMachineId != -1) {
        machineAvailable[bestMachineId] = bestEndTime;
        machines[bestMachineId]?.add(Tuple2(bestProcessStart, bestEndTime));
        // ── Update last-state so the next job on this machine sees the correct
        //    "from" state in the setup matrix.
        _machineLastState[bestMachineId] = job.stateOnMachine(bestMachineId);

        output.add(ParallelOutput(
          job.jobId,
          bestMachineId,
          bestProcessStart,
          bestEndTime,
          bestDelay,
          job.dueDate,
        ));
      }
    }
  }

  // ── Fitness / metric helpers ───────────────────────────────────────────────

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

    const int populationSize = 50;
    const int generations = 100;
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
      DateTime bestProcessStart = DateTime(9999);

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
          bestProcessStart = processStart;
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
}