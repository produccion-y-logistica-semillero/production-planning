import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/schedule_calendar_utils.dart';
import 'package:production_planning/services/scheduling/setup_duration_utils.dart';
import 'package:production_planning/services/scheduling/task_scheduling_utils.dart';
import 'dart:math';

class SingleMachineInput {
  final int jobId;
  final int sequenceId;
  final Duration machineDuration;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;

  SingleMachineInput(
    this.jobId,
    this.sequenceId,
    this.machineDuration,
    this.dueDate,
    this.priority,
    this.availableDate,
  );
}

class SingleMachineOutput {

  final int jobId;
  final Duration processingTime;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final Duration delay;
  SingleMachineOutput(this.jobId, this.processingTime, this.startDate, this.endDate, this.dueDate, this.delay);
}

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  final Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix;
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;
  final Map<int, JobInterruptionPolicy> jobInterruptionPolicies;
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final int machineContinueCapacity;
  final Duration? machineRestTime;
  int _machineProcessedCount = 0;
  int? _lastSequenceId;
  int? _lastJobId;
  late final ScheduleCalendarUtils _calendar;
  List<SingleMachineInput> input = [];
  //the input comes like a table of type
  //  job id   |     unique machine duration   |     due date        |       priority    |     Available date
  //  1         |         15:30                 |   2024/8/30/6:00    |         1         |     2024/8/28/6:00 

  //  2         |         20:41                 |   2024/8/30/6:00    |         3         |     2024/8/28/6:00
  //  3         |         01:25                 |   2024/8/30/6:00    |         2         |     2024/8/28/6:00

  //List<Tuple6<int, Duration, DateTime, DateTime, DateTime, Duration>> output = [];
  List<SingleMachineOutput> output = [];
  //the output goes like a table of type
  //  job id   |   processing time   |   start date    |     End date    |     due date        |     Delay (Retraso)    

  //  1         |       01:30         |  26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       02:30         |  26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule, {
    this.changeoverMatrix = const {},
    this.stateSetupMatrix,
    this.jobStates,
    this.jobInterruptionPolicies = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = 0,
    this.machineRestTime,
  }) {
    _calendar = ScheduleCalendarUtils(
      workingSchedule: workingSchedule,
      machineInactivities: machineInactivities,
    );
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

    }
  }

  
  DateTime _getStartTime(DateTime availableDate) {
    DateTime workStart = DateTime(startDate.year, startDate.month, startDate.day,
        workingSchedule.value1.hour, workingSchedule.value1.minute);

    return availableDate.isBefore(workStart) ? workStart : availableDate;
  }

  void _runOrderedSchedule() {
    if (input.isEmpty) return;
    DateTime scheduleTime = _getStartTime(input.first.availableDate);
    for (final job in input) {
      final earliest = job.availableDate.isAfter(scheduleTime)
          ? job.availableDate
          : scheduleTime;
      final placed = _placeJob(job, earliest);
      final delay = placed.taskEnd.isAfter(job.dueDate)
          ? placed.taskEnd.difference(job.dueDate)
          : Duration.zero;
      output.add(SingleMachineOutput(
        job.jobId,
        job.machineDuration,
        placed.taskStart,
        placed.taskEnd,
        job.dueDate,
        delay,
      ));
      scheduleTime = placed.machineAvailable;
    }
  }

  MachineTaskScheduleResult _placeJob(
      SingleMachineInput job, DateTime earliestStart) {
    final setupDuration = resolveSetupDuration(
      machineId: machineId,
      currentSequenceId: job.sequenceId,
      previousSequenceId: _lastSequenceId,
      currentJobId: job.jobId,
      previousJobId: _lastJobId,
      changeoverMatrix: changeoverMatrix,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
    );
    final policy =
        jobInterruptionPolicies[job.jobId] ?? JobInterruptionPolicy.legacyDefault;
    final result = scheduleMachineTask(
      calendar: _calendar,
      machineId: machineId,
      earliestStart: earliestStart,
      setupDuration: setupDuration,
      processingDuration: job.machineDuration,
      policy: policy,
      continueCapacity: machineContinueCapacity,
      restTime: machineRestTime,
      machineProcessedCount: _machineProcessedCount,
    );
    _machineProcessedCount = result.machineProcessedCount;
    _lastSequenceId = job.sequenceId;
    _lastJobId = job.jobId;
    return result;
  }

  void eddRule() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    _runOrderedSchedule();
  }

  void sptRule() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    _runOrderedSchedule();
  }

  void lptRule() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    _runOrderedSchedule();
  }

  void fifoRule() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    _runOrderedSchedule();
  }

  void wsptRule() {
    input.sort((a, b) => (b.priority / b.machineDuration.inMinutes)
        .compareTo(a.priority / a.machineDuration.inMinutes));
    _runOrderedSchedule();
  }

  void eddRuleAdapted() {
    _runOrderedSchedule();
  }

  void sptRuleAdapted() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    eddRuleAdapted();
  }

  void lptRuleAdapted() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    eddRuleAdapted();
  }


  void fifoRuleAdapted() {

    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    eddRuleAdapted();
  }

  void wsptRuleAdapted() {

    input.sort((a, b) => (b.priority / b.machineDuration.inMinutes)
        .compareTo(a.priority / a.machineDuration.inMinutes));

    eddRuleAdapted();
  }

  ///////////////////////////////////////////////////
///////////////////Reglas DINÁMICAS////////////////////
  ///////////////////////////////////////////////////
  // Implementación de la regla de Minimum Slack

  void scheduleMinimumSlack() {

    input.sort((a, b) => _slack(a) < _slack(b) ? -1 : 1);
    eddRuleAdapted();
  }

  int _slack(SingleMachineInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    return remainingMinutes - job.machineDuration.inMinutes;
  }

  void scheduleCriticalRatio() {
    input.sort((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
    eddRuleAdapted();
  }

  double _criticalRatio(SingleMachineInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    return remainingMinutes / job.machineDuration.inMinutes;
  }


  //ALGORITMO DE GENÉTICA Y SUS FUNCIONAS AUXILIARES 

  //Busca el mejor orden posible de ejecución de trabajos para minimizar el makespan 
  //(minimiza tiempo total desde que se inicia hasta que termina el último trabajo)
  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN SINGLE MACHINE");

    //Soluciones por generación
    const int populationSize = 50; 
    //# veces que se repite el ciclo de evolución
    const int generations = 100;
    //probabilidad de que un hijo sufra una mutación
    const double mutationRate = 0.1;

    //Cada individuo es una lista ordenada de jobs
    List<List<SingleMachineInput>> population = _initializePopulation(populationSize);

    //Se guarda el mejor individuo y su valor
    List<SingleMachineInput> bestIndividual = [];
    Duration bestFitness = Duration(days: 9999);

    //para el numero de generaciones definido anteriormente
    for (int generation = 0; generation < generations; generation++) {
      //Se evalúa cada individuo de la población
      List<Tuple2<List<SingleMachineInput>, Duration>> evaluated = population.map((individual) {
        return Tuple2(individual, _evaluateFitness(individual));
      }).toList();

      //Se ordena -> primero los de menor duración
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));


      //Si el mejor de esta nueva generación es mejor que el de todas las anteriores, se cambia
      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      //Se genera nueva población con mejores individuos actuales
      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    // se asignan los trabajos en el orden del mejor individuo
    input = bestIndividual;
    eddRuleAdapted(); // para asignación de tiempos y mostrar en pantalla
  }


  //Genera secuencias aleatorias de los jobs para comenzar con la evolución
  List<List<SingleMachineInput>> _initializePopulation(int size) {
    List<List<SingleMachineInput>> population = [];

    for (int i = 0; i < size; i++) {
      List<SingleMachineInput> shuffled = List.from(input);
      shuffled.shuffle();
      population.add(shuffled);
    }

    return population;
  }

  //Evalúa cuando tiempo tarda una secuencia en completarse
  Duration _evaluateFitness(List<SingleMachineInput> jobSequence) {
    //representa hora a la que empieza a trabajar la máquina (dentro del horario laboral)
    DateTime current = _getStartTime(jobSequence.first.availableDate);
    //inicia tiempo total en 0 
    Duration totalTime = Duration.zero;

    //simula que los jobs se ejecutan uno por uno en el orden dado
    for (var job in jobSequence) {
      final placed = _placeJob(job, current);
      totalTime += placed.taskEnd.difference(startDate);
      current = placed.machineAvailable;
    }

    return totalTime; // menor makespan
  }

  //para cada individuo selecciona dos padres, los cruza para crear un hijo
  List<List<SingleMachineInput>> _generateNewPopulation(
  List<Tuple2<List<SingleMachineInput>, Duration>> evaluated,
    int size,
    double mutationRate,
  ) {
    List<List<SingleMachineInput>> newPop = [];

    for (int i = 0; i < size; i++) {
      final parent1 = _selectParent(evaluated);
      final parent2 = _selectParent(evaluated);

      List<SingleMachineInput> child = _crossover(parent1, parent2);

      if (Random().nextDouble() < mutationRate) {
        child = _mutate(child);
      }

      newPop.add(child);
    }

    return newPop;
  }

  //torneo binario para seleccionar individuo padre
  List<SingleMachineInput> _selectParent(List<Tuple2<List<SingleMachineInput>, Duration>> evaluated) {
    int k = 5;
    //elige k individuos aleatorios y forma una lista
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    //selecciona el de menor tiempo
    return selected.first.value1;
  }

  List<SingleMachineInput> _crossover(List<SingleMachineInput> p1, List<SingleMachineInput> p2) {
    final length = p1.length;
    //toma un punto de corte aleatorio 
    final int point = Random().nextInt(length);
    final Set<int> jobIds = p1.sublist(0, point).map((j) => j.jobId).toSet();

    //copia los trabajos de p1 desde 0 hasta el punto de corte
    final List<SingleMachineInput> child = [
      ...p1.sublist(0, point),
      //completa con los trabajos de p2 que no estén repetidos
      ...p2.where((j) => !jobIds.contains(j.jobId)),
    ];

    return child;
  }
  //intercambia de orden dos trabajos de un mismo individuio
  List<SingleMachineInput> _mutate(List<SingleMachineInput> individual) {
    if (individual.length < 2) return individual;
    //se escogen dos posiciones aleatorias
    int i = Random().nextInt(individual.length);
    int j = Random().nextInt(individual.length);
    //intercambia el orden de dos trabajos
    final temp = individual[i];
    individual[i] = individual[j];
    individual[j] = temp;
    return individual;
  }

}
