import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class SingleMachineInput {
  final int jobId;
  final Duration machineDuration;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;

  /// Product family / job-type label used as the row/column key in the
  /// state-based setup matrix (e.g. "A", "B", "C").
  final String jobState;

  SingleMachineInput(
    this.jobId,
    this.machineDuration,
    this.dueDate,
    this.priority,
    this.availableDate, {
    this.jobState = 'A',
  });
}

class SingleMachineOutput {
  final int jobId;
  final Duration processingTime;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final Duration delay;

  SingleMachineOutput(
    this.jobId,
    this.processingTime,
    this.startDate,
    this.endDate,
    this.dueDate,
    this.delay,
  );
}

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // like 8-17

  List<SingleMachineInput> input = [];
  List<SingleMachineOutput> output = [];

  // ── Setup-time state ──────────────────────────────────────────────────────
  // stateSetupMatrix: machineId → fromState → toState → minutes.
  // Only the entry for [machineId] is used; the map wrapper is kept so the
  // structure is identical to every other environment and the same
  // buildMachineStateSetupMatrix helper can populate it.
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;

  // Tracks the job-state of the job that last ran on the machine.
  // Starts as null (cold start → no setup cost for the first job).
  String? _lastJobState;

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule, {
    this.stateSetupMatrix,
  }) {
    switch (rule) {
      case "EDD":           eddRule();              break;
      case "SPT":           sptRule();              break;
      case "LPT":           lptRule();              break;
      case "FIFO":          fifoRule();             break;
      case "WSPT":          wsptRule();             break;
      case "EDD_ADAPTADO":  eddRuleAdapted();       break;
      case "SPT_ADAPTADO":  sptRuleAdapted();       break;
      case "LPT_ADAPTADO":  lptRuleAdapted();       break;
      case "FIFO_ADAPTADO": fifoRuleAdapted();      break;
      case "WSPT_ADAPTADO": wsptRuleAdapted();      break;
      case "MINSLACK":      scheduleMinimumSlack(); break;
      case "CR":            scheduleCriticalRatio(); break;
      case "GENETICS":      scheduleGeneticAlgorithm(); break;
    }
  }

  // ── Setup-time helper ─────────────────────────────────────────────────────

  /// Returns s_{fromState → toState} for [machineId].
  /// Returns [Duration.zero] on cold start (null fromState) or missing cell.
  Duration _setupDuration(String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  // ── Working-schedule helpers ───────────────────────────────────────────────

  DateTime _getStartTime(DateTime availableDate) {
    final workStart = DateTime(
      startDate.year, startDate.month, startDate.day,
      workingSchedule.value1.hour, workingSchedule.value1.minute,
    );
    return availableDate.isBefore(workStart) ? workStart : availableDate;
  }

  /// Pushes [current] to the next working-day start if adding [duration]
  /// would exceed the end of the current working day.
  DateTime _getAvailableStartTime(DateTime current, Duration duration) {
    final endMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;
    final currentMinutes =
        current.hour * 60 + current.minute + duration.inMinutes;
    if (currentMinutes > endMinutes) {
      final next = current.add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day,
          workingSchedule.value1.hour, workingSchedule.value1.minute);
    }
    return current;
  }

  // ── Core assignment ───────────────────────────────────────────────────────

  /// Schedules [job] at [scheduleTime], prepending the setup duration
  /// s_{_lastJobState → job.jobState} before processing.
  ///
  /// Returns the updated schedule pointer (= end of this job's processing).
  DateTime _assignJob(SingleMachineInput job, DateTime scheduleTime) {
    // 1. Compute setup duration for this transition.
    final setup = _setupDuration(_lastJobState, job.jobState);

    // 2. If there is a setup cost, advance the pointer past it (and
    //    re-check working-schedule boundaries after the setup period).
    DateTime processStart = scheduleTime;
    if (setup > Duration.zero) {
      processStart = _getAvailableStartTime(scheduleTime, setup);
      processStart = processStart.add(setup);
      // Re-align to working hours in case the setup pushed us past day-end.
      processStart = _alignToWorkingHours(processStart);
    }

    // 3. Schedule processing after setup.
    processStart = _getAvailableStartTime(processStart, job.machineDuration);
    final DateTime end = processStart.add(job.machineDuration);
    final Duration delay = end.isAfter(job.dueDate)
        ? end.difference(job.dueDate)
        : Duration.zero;

    output.add(SingleMachineOutput(
      job.jobId, job.machineDuration, processStart, end, job.dueDate, delay,
    ));

    // 4. Remember this job's state for the next iteration.
    _lastJobState = job.jobState;

    return end;
  }

  /// Pushes [dt] to the start of the next working day if it falls outside
  /// working hours (i.e. at or after day-end).
  DateTime _alignToWorkingHours(DateTime dt) {
    final endH = workingSchedule.value2.hour;
    final endM = workingSchedule.value2.minute;
    if (dt.hour > endH || (dt.hour == endH && dt.minute >= endM)) {
      final next = dt.add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day,
          workingSchedule.value1.hour, workingSchedule.value1.minute);
    }
    return dt;
  }

  // ── Dispatching rules ─────────────────────────────────────────────────────

  void eddRule() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    _runSequence();
  }

  void sptRule() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    _runSequence();
  }

  void lptRule() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    _runSequence();
  }

  void fifoRule() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    _runSequence();
  }

  void wsptRule() {
    input.sort((a, b) =>
        (b.priority / b.machineDuration.inMinutes)
            .compareTo(a.priority / a.machineDuration.inMinutes));
    _runSequence();
  }

  // The *Adapted variants re-sort and then call _runSequence directly.
  void eddRuleAdapted() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    _runSequence();
  }

  void sptRuleAdapted() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    _runSequence();
  }

  void lptRuleAdapted() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    _runSequence();
  }

  void fifoRuleAdapted() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    _runSequence();
  }

  void wsptRuleAdapted() {
    input.sort((a, b) =>
        (b.priority / b.machineDuration.inMinutes)
            .compareTo(a.priority / a.machineDuration.inMinutes));
    _runSequence();
  }

  void scheduleMinimumSlack() {
    input.sort((a, b) => _slack(a).compareTo(_slack(b)));
    _runSequence();
  }

  void scheduleCriticalRatio() {
    input.sort((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
    _runSequence();
  }

  // ── Sequential runner ─────────────────────────────────────────────────────

  /// Walks the (already-sorted) [input] list in order, calling [_assignJob]
  /// for each job and threading the schedule-time pointer through.
  ///
  /// This is the single place where setup times are injected: [_assignJob]
  /// prepends s_{prev → current} before every job's processing window.
  void _runSequence() {
    // Reset state tracking so re-entrant calls (e.g. from genetics) start clean.
    _lastJobState = null;
    output.clear();

    if (input.isEmpty) return;
    DateTime scheduleTime = _getStartTime(input.first.availableDate);

    for (final job in input) {
      scheduleTime = _assignJob(job, scheduleTime);
    }
  }

  // ── Metric helpers ────────────────────────────────────────────────────────

  int _slack(SingleMachineInput job) =>
      job.dueDate.difference(job.availableDate).inMinutes -
      job.machineDuration.inMinutes;

  double _criticalRatio(SingleMachineInput job) {
    final remaining = job.dueDate.difference(job.availableDate).inMinutes;
    return remaining / job.machineDuration.inMinutes;
  }

  // ── Genetic algorithm ─────────────────────────────────────────────────────

  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN SINGLE MACHINE");

    const int populationSize = 50;
    const int generations = 100;
    const double mutationRate = 0.1;

    List<List<SingleMachineInput>> population =
        _initializePopulation(populationSize);
    List<SingleMachineInput> bestIndividual = [];
    Duration bestFitness = const Duration(days: 9999);

    for (int generation = 0; generation < generations; generation++) {
      final evaluated = population
          .map((ind) => Tuple2(ind, _evaluateFitness(ind)))
          .toList();
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      population =
          _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    input = bestIndividual;
    _runSequence();
  }

  List<List<SingleMachineInput>> _initializePopulation(int size) {
    return List.generate(size, (_) {
      final shuffled = List<SingleMachineInput>.from(input);
      shuffled.shuffle();
      return shuffled;
    });
  }

  /// Pure fitness evaluation — does NOT mutate [output] or [_lastJobState].
  /// Simulates [_runSequence] internally with a local state tracker so that
  /// concurrent genetic evaluations don't interfere with each other.
  Duration _evaluateFitness(List<SingleMachineInput> sequence) {
    if (sequence.isEmpty) return Duration.zero;

    String? localLastState;
    DateTime current = _getStartTime(sequence.first.availableDate);
    Duration totalTime = Duration.zero;

    for (final job in sequence) {
      // Mirror _assignJob logic without writing to output.
      final setup = _setupDurationRaw(localLastState, job.jobState);

      DateTime processStart = current;
      if (setup > Duration.zero) {
        processStart = _getAvailableStartTime(current, setup);
        processStart = processStart.add(setup);
        processStart = _alignToWorkingHours(processStart);
      }

      processStart = _getAvailableStartTime(processStart, job.machineDuration);
      final end = processStart.add(job.machineDuration);
      totalTime += end.difference(startDate);
      localLastState = job.jobState;
      current = end;
    }

    return totalTime;
  }

  /// Raw setup lookup that doesn't touch instance state — safe to call from
  /// fitness evaluations running over different candidate sequences.
  Duration _setupDurationRaw(String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  List<List<SingleMachineInput>> _generateNewPopulation(
    List<Tuple2<List<SingleMachineInput>, Duration>> evaluated,
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

  List<SingleMachineInput> _selectParent(
      List<Tuple2<List<SingleMachineInput>, Duration>> evaluated) {
    const k = 5;
    final selected =
        List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<SingleMachineInput> _crossover(
      List<SingleMachineInput> p1, List<SingleMachineInput> p2) {
    final length = p1.length;
    final point = Random().nextInt(length);
    final taken = p1.sublist(0, point).map((j) => j.jobId).toSet();
    return [
      ...p1.sublist(0, point),
      ...p2.where((j) => !taken.contains(j.jobId)),
    ];
  }

  List<SingleMachineInput> _mutate(List<SingleMachineInput> individual) {
    if (individual.length < 2) return individual;
    final i = Random().nextInt(individual.length);
    final j = Random().nextInt(individual.length);
    final tmp = individual[i];
    individual[i] = individual[j];
    individual[j] = tmp;
    return individual;
  }
}