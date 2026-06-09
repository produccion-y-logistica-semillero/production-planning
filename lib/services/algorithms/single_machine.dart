import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/shared/types/rnage.dart';
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

  // Machine inactivity support
  final List<MachineInactivityEntity> machineInactivities;
  final int continueCapacity;
  final Duration? restTime;
  int processedCount = 0;

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule, {
    this.machineInactivities = const [],
    this.continueCapacity = 0,
    this.restTime,
    this.stateSetupMatrix,
  }) {
    switch (rule) {
      //case "JHONSON":jhonsonRule();break;
      case "EDD": eddRule(); break;
      case "SPT": sptRule(); break;
      case "LPT": lptRule(); break;
      case "FIFO": fifoRule(); break;
      case "WSPT": wsptRule(); break;
      case "EDD_ADAPTADO": eddRuleAdapted(); break;
      case "SPT_ADAPTADO": sptRuleAdapted(); break;
      case "LPT_ADAPTADO": lptRuleAdapted(); break;
      case "FIFO_ADAPTADO": fifoRuleAdapted(); break;
      case "WSPT_ADAPTADO": wsptRuleAdapted(); break;
      case "MINSLACK": scheduleMinimumSlack(); break;
      case "CR": scheduleCriticalRatio(); break;
      case "GENETICS": scheduleGeneticAlgorithm(); break;
      case "TABU": scheduleTabuSearch(); break;
      

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

  // Obtener las inactividades para un día específico
  List<Range> _getInactivitiesForDay(DateTime day) {
    final weekday = day.weekday;
    final List<Range> dayInactivities = [];

    for (final inactivity in machineInactivities) {
      final inactivityWeekdays =
          inactivity.weekdays.map((wd) => wd.index + 1).toSet();

      if (inactivityWeekdays.contains(weekday)) {
        final startHour = inactivity.startTime.inHours;
        final startMinute = inactivity.startTime.inMinutes % 60;

        final inactivityStart = DateTime(
          day.year, day.month, day.day, startHour, startMinute,
        );

        final inactivityEnd = inactivityStart.add(inactivity.duration);
        dayInactivities.add(Range(inactivityStart, inactivityEnd));
      }
    }

    return dayInactivities;
  }

  // Ajustar el tiempo de finalización considerando inactividades programadas
  DateTime _adjustEndTimeWithInactivities(DateTime start, DateTime end) {
    DateTime current = start;
    Duration remaining = end.difference(start);

    while (remaining > Duration.zero) {
      current = _getStartTime(current);

      final dayInactivities = _getInactivitiesForDay(current);

      final dayEnd = DateTime(
        current.year, current.month, current.day,
        workingSchedule.value2.hour, workingSchedule.value2.minute,
      );

      DateTime nextAvailable = current;
      for (final inactivity in dayInactivities) {
        if (nextAvailable.isBefore(inactivity.end) &&
            inactivity.start.isBefore(dayEnd)) {
          if (nextAvailable.isBefore(inactivity.start)) {
            final availableBeforeInactivity =
                inactivity.start.difference(nextAvailable);

            if (remaining <= availableBeforeInactivity) {
              return nextAvailable.add(remaining);
            } else {
              remaining -= availableBeforeInactivity;
              nextAvailable = inactivity.end;
            }
          } else {
            if (nextAvailable.isBefore(inactivity.end)) {
              nextAvailable = inactivity.end;
            }
          }
        }
      }

      final availableToday = dayEnd.difference(nextAvailable);

      if (availableToday > Duration.zero && remaining <= availableToday) {
        return nextAvailable.add(remaining);
      } else {
        if (availableToday > Duration.zero) {
          remaining -= availableToday;
        }
        current = current.add(const Duration(days: 1));
      }
    }

    return current;
  }

  // Aplicar descanso por continueCapacity y devolver el end time ajustado
  DateTime _applyRestIfNeeded(DateTime endTime) {
    if (continueCapacity > 0 && restTime != null) {
      processedCount++;
      if (processedCount >= continueCapacity) {
        processedCount = 0;
        return endTime.add(restTime!);
      }
    }
    return endTime;
  }

  void eddRule() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    DateTime startWorkDateTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      workingSchedule.value1.hour,
      workingSchedule.value1.minute,
    );

    DateTime earliestJobAvailableTime = input[0].availableDate;
    DateTime scheduleTime = earliestJobAvailableTime.isBefore(startWorkDateTime)
        ? startWorkDateTime
        : earliestJobAvailableTime;

    for (var job in input) {
      DateTime start = _getStartTime(scheduleTime);
      start = _getAvailableStartTime(start, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);

      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = _applyRestIfNeeded(end);
    }
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

    for (var job in input) {
      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = _applyRestIfNeeded(end);
    }
  }

  void lptRule() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);

    for (var job in input) {
      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));

      scheduleTime = _applyRestIfNeeded(end);
    }
  }

  void fifoRule() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);
    for (var job in input) {
      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;
      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));

      scheduleTime = _applyRestIfNeeded(end);
    }
  }

  void wsptRule() {
    input.sort((a, b) => (b.priority / b.machineDuration.inMinutes).compareTo(a.priority / a.machineDuration.inMinutes));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);
    for (var job in input) {
      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;
      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));

      scheduleTime = _applyRestIfNeeded(end);
    }
  }

  // The *Adapted variants re-sort and then call _runSequence directly.
  void eddRuleAdapted() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);

    for (var job in input) {
      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      final rawEnd = start.add(job.machineDuration);
      DateTime end = _adjustEndTimeWithInactivities(start, rawEnd);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

      output.add(SingleMachineOutput(job.jobId, job.machineDuration, start, end, job.dueDate, delay));

      scheduleTime = _applyRestIfNeeded(end);
    }
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
  Duration calcularMakespanTabuSingle(List<SingleMachineInput> jobSequence) {
  DateTime current = _getStartTime(jobSequence.first.availableDate);

  for (var job in jobSequence) {
    current = _getAvailableStartTime(current, job.machineDuration);
    current = current.add(job.machineDuration);
  }

  return current.difference(_getStartTime(jobSequence.first.availableDate));
}

Duration evaluateFlujoTotal(List<SingleMachineInput> seq) {

  DateTime current = _getStartTime(seq.first.availableDate);
  DateTime origin  = current; 

  Duration sumCompletions = Duration.zero;
  for (var job in seq) {
    current = _getAvailableStartTime(current, job.machineDuration);
    current = current.add(job.machineDuration);
    sumCompletions += current.difference(origin); // ← origin en vez de startDate
  }
  return sumCompletions;
}


void _generateOutput(List<SingleMachineInput> solution) {
  output.clear();
  var time = evaluateFlujoTotal(solution);
  print("Tiempo del tabu: $time");

  if (solution.isEmpty) return;

  DateTime scheduleTime = _getStartTime(solution.first.availableDate);

  for (var job in solution) {
    print("job ${job.jobId} → duración: ${job.machineDuration} | available: ${job.availableDate} | due: ${job.dueDate}");

    DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
    DateTime end = start.add(job.machineDuration);
    Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

    output.add(
      SingleMachineOutput(
        job.jobId,
        job.machineDuration,
        start,
        end,
        job.dueDate,
        delay,
      ),
    );

    scheduleTime = end;
  }
}


void scheduleTabuSearch() { 

  if (input.length < 2) {
    _generateOutput(input);
    return;
  }
const int maxIterations       = 200;  // maximas iteraciones 
const int tabuTenure          = 10;   // cuántas iteraciones permanece prohibido un movimiento.
const int maxNoImprove        = 20;  //  Numero de maximo de iteraciones sin mejora 
const int vecinosPorIteracion = 7;   // Cantidad  de swaps por iteracion 

  // Solución inicial aleatoria
  List<SingleMachineInput> currentSolution =List.from(input)..shuffle();

  Duration currentFitness =evaluateFlujoTotal(currentSolution);
  // Guarda la mejor en una lista independiente 
  List<SingleMachineInput> bestSolution =List.from(currentSolution);

  Duration bestFitness = currentFitness;
  // movimiento prohibidos
  Map<String, int> tabuMap = {};

  int sinMejora = 0;

  final random = Random();

  int n = currentSolution.length;
  // ciclo de revison 
  for (int iter = 0; iter < maxIterations; iter++) {


    // Limpiar movimientos tabú vencidos
    tabuMap.removeWhere((_, exp) => exp <= iter);

    List<SingleMachineInput>? bestNeighbor; // Lista de Maquinas 

    Duration bestNeighborFitness = const Duration(days: 9999); // Inicializacion del flujo 

    int bestI = -1; // Asegura los indices 
    int bestJ = -1;

    // Explorar solo algunos vecinos aleatorios
    for (int k = 0; k < vecinosPorIteracion; k++) {

      int i = random.nextInt(n); // dos posiciones al azar 
      int j = random.nextInt(n);

      while (i == j) {
        j = random.nextInt(n);
      }
      // Copia de la lista 
      List<SingleMachineInput> neighbor = List.from(currentSolution);
      // swap 
      final temp = neighbor[i];
      neighbor[i] = neighbor[j];
      neighbor[j] = temp;

      Duration neighborFitness =evaluateFlujoTotal(neighbor); // Evalua al vecino 

      String key = '${i}_$j';

      bool isTabu =tabuMap.containsKey(key); // revisa si esta prohibido 

      // Criterio de aspiración
      bool aspiracion = isTabu && neighborFitness < bestFitness;
      // Actualizar la mejor solución
      if ((!isTabu || aspiracion) && neighborFitness <bestNeighborFitness) {

        bestNeighborFitness = neighborFitness;

        bestNeighbor = neighbor;

        bestI = i;
        bestJ = j;
      }
    }

    if (bestNeighbor == null) {
      continue;
    }

    // Moverse al mejor vecino(el mejor swap) encontrado y seguir 
    currentSolution = bestNeighbor;
    currentFitness = bestNeighborFitness;

    // Registrar movimiento tabú
    tabuMap['${bestI}_$bestJ'] = iter + tabuTenure +random.nextInt(6) -2;

    // Actualizar mejor global
    if (currentFitness < bestFitness) {

      bestFitness = currentFitness;

      bestSolution =  List.from(currentSolution);

      sinMejora = 0;

    } else {

      sinMejora++;

    }


    // Diversificación (Escapar de optimos locales)
    if (sinMejora >= maxNoImprove) {

      currentSolution =List.from(bestSolution)..shuffle();

      currentFitness = evaluateFlujoTotal(currentSolution);

      tabuMap.clear();

      sinMejora = 0;
    }
  }

  // Mejor solución encontrada
  input = bestSolution; // mejor secuencia 
  // Falta esto :
  output.clear();

  var time = evaluateFlujoTotal(bestSolution) ;


  print("Tiempo del tabu: $time");


  DateTime scheduleTime = _getStartTime(input.first.availableDate);

  for (var job in input) {

     print("job ${job.jobId} → duración: ${job.machineDuration} | available: ${job.availableDate} | due: ${job.dueDate}");


    DateTime start = _getAvailableStartTime(scheduleTime,job.machineDuration);

    DateTime end =start.add(job.machineDuration);

    Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate): Duration.zero;

    output.add(
      SingleMachineOutput(
        job.jobId,
        job.machineDuration,
        start,
        end,
        job.dueDate,
        delay,
      ),
    );

    scheduleTime = end;
  }
}

}