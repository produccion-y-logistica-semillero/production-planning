import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/schedule_calendar_utils.dart';
import 'package:production_planning/services/scheduling/setup_duration_utils.dart';
import 'package:production_planning/services/scheduling/task_scheduling_utils.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlowShopInput {
  final int jobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // this list has the order of the tasks, it has a tuple of 2 <task id, machine id>
  final List<Tuple2<int, int>> taskSequence;
  // in this map we have the durations, the id is the task id, and the duration is how long it takes
  final Map<int, Duration> taskTimesInMachines;

  FlowShopInput(
    this.jobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.taskSequence,
    this.taskTimesInMachines,
  );
}

class FlowShopOutput {
  final int jobId;
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime endTime;
  // the output, the map has the key the machine id, the value is a tuple of <task id, range start to end time>
  final Map<int, Tuple2<int, Range>> machinesScheduling;

  FlowShopOutput(
    this.jobId,
    this.startDate,
    this.dueDate,
    this.endTime,
    this.machinesScheduling,
  );
}

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // like 8-17

  List<FlowShopInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability = {};
  List<FlowShopOutput> output = [];

  /// changeoverMatrix:
  /// { machineId : { previousSequenceId_or_null : { currentSequenceId : Duration } } }
  final Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix;
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;
  final Map<int, JobInterruptionPolicy> jobInterruptionPolicies;
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;
  final Map<int, int> machineProcessedCount = {};
  late final ScheduleCalendarUtils _calendar;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};

  FlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    Map<int, Map<int?, Map<int, Duration>>>? changeoverMatrix,
    this.stateSetupMatrix,
    this.jobStates,
    this.jobInterruptionPolicies = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) : changeoverMatrix = changeoverMatrix ?? {} {
    _calendar = ScheduleCalendarUtils(
      workingSchedule: workingSchedule,
      machineInactivities: machineInactivities,
    );
    for (final machineId in machinesAvailability.keys) {
      machineProcessedCount[machineId] = 0;
    }
    _initializeMachineLastSequence();
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
      case "JOHNSON":
        _applyJohnsonRule(inputJobs);
        break;
      case "CDS":
        cdsAlgorithm();
        break;
      case "MINSLACK":
        msRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "GENETICS":
        scheduleGeneticAlgorithm();
        break;
      default:
        // no-op: unknown rule
        break;
    }
  }

  void _initializeMachineLastSequence() {
    for (final job in inputJobs) {
      for (final task in job.taskSequence) {
        _machineLastSequence.putIfAbsent(task.value2, () => null);
        _machineLastJob.putIfAbsent(task.value2, () => null);
      }
    }
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
    for (final machineId in changeoverMatrix.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
  }

  /* ---------- Rules (dispatching / sequencing) ---------- */

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
      );
  void lptRule() => _schedule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
      );
  void fifoRule() => _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule() => _schedule((a, b) {
        double wsptA = a.priority / max(1, _totalProcessingTime(a));
        double wsptB = b.priority / max(1, _totalProcessingTime(b));
        return wsptB.compareTo(wsptA);
      });

  void eddaRule() => dynamicRule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptaRule() => dynamicRule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
      );
  void lptaRule() => dynamicRule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
      );
  void fifoaRule() => dynamicRule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptaRule() => dynamicRule((a, b) {
        double wsptA = a.priority / max(1, _totalProcessingTime(a));
        double wsptB = b.priority / max(1, _totalProcessingTime(b));
        return wsptB.compareTo(wsptA);
      });

  void msRule() {
    int totalProcessingTimeAccumulated = 0;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        int slackA = _calculateSlack(a, totalProcessingTimeAccumulated);
        int slackB = _calculateSlack(b, totalProcessingTimeAccumulated);
        return slackA.compareTo(slackB);
      });

      FlowShopInput selectedJob = remainingJobs.first;
      _assignJobToMachines(selectedJob);
      totalProcessingTimeAccumulated += _totalProcessingTime(selectedJob);
      remainingJobs.remove(selectedJob);
    }
  }

  void crRule() {
    int totalProcessingTimeAccumulated = 0;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        double crA = _calculateCR(a, totalProcessingTimeAccumulated);
        double crB = _calculateCR(b, totalProcessingTimeAccumulated);
        return crA.compareTo(crB);
      });

      FlowShopInput selectedJob = remainingJobs.first;
      _assignJobToMachines(selectedJob);
      totalProcessingTimeAccumulated += _totalProcessingTime(selectedJob);
      remainingJobs.remove(selectedJob);
    }
  }

  void atcRule() {
    DateTime currentTime = startDate;
    List<FlowShopInput> remainingJobs = List.from(inputJobs);
    output.clear();
    int elapsedTime = 0;
    double K = 3.0;

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(
        (a, b) => _calculateATCPriority(
          b,
          currentTime,
          elapsedTime,
          K,
        ).compareTo(_calculateATCPriority(a, currentTime, elapsedTime, K)),
      );
      FlowShopInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
      elapsedTime += _totalProcessingTime(selectedJob);
      currentTime = output.last.endTime;
    }
  }

  double _calculateATCPriority(
    FlowShopInput job,
    DateTime currentTime,
    int elapsedTime,
    double k,
  ) {
    int processingTime = _totalProcessingTime(job);
    double avgProcessingTime = max(1, processingTime) / job.taskSequence.length;
    double timeDiff = job.dueDate.difference(currentTime).inMinutes.toDouble();
    double slackTime = (timeDiff - processingTime - elapsedTime).clamp(0, double.infinity);
    double expFactor = exp(-slackTime / (k * avgProcessingTime));
    return (job.priority / max(1, processingTime)) * expFactor;
  }

  void _schedule(int Function(FlowShopInput, FlowShopInput) comparator) {
    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void dynamicRule(int Function(FlowShopInput, FlowShopInput) comparator) {
    List<FlowShopInput> remainingJobs = List.from(inputJobs);
    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(comparator);
      FlowShopInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
    }
  }

  /* ---------- Core scheduling (assignment) ---------- */

  void _assignJobToMachines(FlowShopInput job) {
    DateTime jobStartTime = job.availableDate;
    DateTime? actualStartTime;
    Map<int, Tuple2<int, Range>> scheduling = {};

    for (var task in job.taskSequence) {
      int taskId = task.value1;
      int machineId = task.value2;
      Duration duration = job.taskTimesInMachines[taskId]!;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
      final earliestStart =
          jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;

      final int? previousSequence =
          _machineLastSequence.putIfAbsent(machineId, () => null);
      final int? previousJob = _machineLastJob.putIfAbsent(machineId, () => null);
      final setupDuration = resolveSetupDuration(
        machineId: machineId,
        currentSequenceId: job.sequenceId,
        previousSequenceId: previousSequence,
        currentJobId: job.jobId,
        previousJobId: previousJob,
        changeoverMatrix: changeoverMatrix,
        stateSetupMatrix: stateSetupMatrix,
        jobStates: jobStates,
      );

      final policy = jobInterruptionPolicies[job.jobId] ??
          JobInterruptionPolicy.legacyDefault;
      final result = scheduleMachineTask(
        calendar: _calendar,
        machineId: machineId,
        earliestStart: earliestStart,
        setupDuration: setupDuration,
        processingDuration: duration,
        policy: policy,
        continueCapacity: machineContinueCapacity[machineId] ?? 0,
        restTime: machineRestTime[machineId],
        machineProcessedCount: machineProcessedCount[machineId] ?? 0,
      );
      machineProcessedCount[machineId] = result.machineProcessedCount;

      actualStartTime ??= result.taskStart;
      scheduling[machineId] =
          Tuple2(taskId, Range(result.taskStart, result.taskEnd));
      machinesAvailability[machineId] = result.machineAvailable;
      _machineLastSequence[machineId] = job.sequenceId;
      _machineLastJob[machineId] = job.jobId;
      jobStartTime = result.machineAvailable;
    }

    output.add(
      FlowShopOutput(
        job.jobId,
        actualStartTime ?? job.availableDate,
        job.dueDate,
        jobStartTime,
        scheduling,
      ),
    );
  }

  Duration _getSetupDuration(
    int machineId,
    int currentSequenceId,
    int? previousSequenceId, {
    int? currentJobId,
    int? previousJobId,
  }) {
    // Try state-based setup matrix first (if all data is available)
    if (stateSetupMatrix != null && 
        jobStates != null && 
        currentJobId != null && 
        previousJobId != null &&
        previousJobId > 0) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        final previousState = jobStates![previousJobId]?[machineId];
        final currentState = jobStates![currentJobId]?[machineId];
        if (previousState != null && currentState != null) {
          final setupMinutes = machineStates[previousState]?[currentState];
          if (setupMinutes != null) {
            return Duration(minutes: setupMinutes);
          }
        }
      }
    }

    // Fallback to changeover matrix (sequence-based)
    final machineMatrix = changeoverMatrix[machineId];
    if (machineMatrix == null) return Duration.zero;

    // Try specific previous sequence
    if (previousSequenceId != null) {
      final previousDurations = machineMatrix[previousSequenceId];
      if (previousDurations != null && previousDurations.containsKey(currentSequenceId)) {
        return previousDurations[currentSequenceId]!;
      }
    }

    // Try default (null) mapping
    final defaultDurations = machineMatrix[null];
    if (defaultDurations != null && defaultDurations.containsKey(currentSequenceId)) {
      return defaultDurations[currentSequenceId]!;
    }

    return Duration.zero;
  }


  int _totalProcessingTime(FlowShopInput job) {
    return job.taskTimesInMachines.values.fold(0, (sum, duration) => sum + duration.inMinutes);
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour || (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    } else if (start.hour > workingEnd.hour || (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  DateTime _calculateEndWithSchedule(DateTime start, Duration duration) {
    if (duration <= Duration.zero) return start;

    final TimeOfDay workingStart = workingSchedule.value1;
    final TimeOfDay workingEnd = workingSchedule.value2;

    DateTime current = start;
    Duration remaining = duration;

    while (remaining > Duration.zero) {
      final DateTime dayStart = DateTime(current.year, current.month, current.day, workingStart.hour, workingStart.minute);
      final DateTime dayEnd = DateTime(current.year, current.month, current.day, workingEnd.hour, workingEnd.minute);

      if (current.isBefore(dayStart)) {
        current = dayStart;
        continue;
      }

      if (!current.isBefore(dayEnd)) {
        current = DateTime(current.year, current.month, current.day + 1, workingStart.hour, workingStart.minute);
        continue;
      }

      final Duration availableToday = dayEnd.difference(current);
      if (remaining <= availableToday) {
        return current.add(remaining);
      } else {
        remaining -= availableToday;
        current = DateTime(current.year, current.month, current.day + 1, workingStart.hour, workingStart.minute);
      }
    }

    return current;
  }

  int _calculateSlack(FlowShopInput job, int accumulatedTime) {
    int totalProcessingTime = _totalProcessingTime(job);
    DateTime currentTime = DateTime.now();
    int slack = job.dueDate.difference(currentTime).inMinutes - totalProcessingTime - accumulatedTime;
    return slack < 0 ? 0 : slack;
  }

  double _calculateCR(FlowShopInput job, int accumulatedTime) {
    int remainingTime = max(job.dueDate.difference(DateTime.now()).inMinutes - accumulatedTime, 0);
    int processingTime = _totalProcessingTime(job);
    return processingTime > 0 ? remainingTime / processingTime : double.infinity;
  }

  /* ---------- CDS & Johnson helpers ---------- */

  void cdsAlgorithm() {
    if (inputJobs.isEmpty) return;

    int numMachines = inputJobs.first.taskSequence.length;

    if (numMachines == 2) {
      _applyJohnsonRule(inputJobs);
      return;
    }

    List<FlowShopInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numMachines; k++) {
      List<FlowShopInput> tempJobs = inputJobs.map((job) {
        Duration sumA = Duration.zero;
        Duration sumB = Duration.zero;

        for (int i = 0; i < k; i++) {
          int taskId = job.taskSequence[i].value1;
          sumA += job.taskTimesInMachines[taskId]!;
        }

        for (int i = k; i < numMachines; i++) {
          int taskId = job.taskSequence[i].value1;
          sumB += job.taskTimesInMachines[taskId]!;
        }

        Map<int, Duration> reducedTimes = {0: sumA, 1: sumB};

        return FlowShopInput(
          job.jobId,
          job.sequenceId,
          job.dueDate,
          job.priority,
          job.availableDate,
          [const Tuple2(0, 0), const Tuple2(1, 1)],
          reducedTimes,
        );
      }).toList();

      List<FlowShopInput> ordered = _getJohnsonOrderedJobs(tempJobs);
      List<int> orderedIds = ordered.map((e) => e.jobId).toList();

      List<FlowShopInput> orderedOriginal = orderedIds.map((id) => inputJobs.firstWhere((job) => job.jobId == id)).toList();

      int makespan = _calculateMakespan(orderedOriginal);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = orderedOriginal;
      }
    }

    inputJobs = bestSequence;
    _schedule((a, b) => 0);
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  void _applyJohnsonRule(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[job.taskSequence[0].value1]!;
      Duration b = job.taskTimesInMachines[job.taskSequence[1].value1]!;
      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => a.taskTimesInMachines[a.taskSequence[0].value1]!.compareTo(b.taskTimesInMachines[b.taskSequence[0].value1]!));
    conjuntoII.sort((a, b) => b.taskTimesInMachines[b.taskSequence[1].value1]!.compareTo(a.taskTimesInMachines[a.taskSequence[1].value1]!));

    inputJobs = [...conjuntoI, ...conjuntoII];
    _schedule((a, b) => 0);
  }

  List<FlowShopInput> _getJohnsonOrderedJobs(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[0]!;
      Duration b = job.taskTimesInMachines[1]!;
      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => a.taskTimesInMachines[0]!.compareTo(b.taskTimesInMachines[0]!));
    conjuntoII.sort((a, b) => b.taskTimesInMachines[1]!.compareTo(a.taskTimesInMachines[1]!));
    return [...conjuntoI, ...conjuntoII];
  }

  int _calculateMakespan(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> currentMachineAvailability = {};
    Map<int, int?> currentMachineSequence = {};
    Map<int, int?> currentMachineJob = {};

    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int machineId = task.value2;
        currentMachineAvailability[machineId] = startDate;
        currentMachineSequence[machineId] = null;
        currentMachineJob[machineId] = null;
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable = currentMachineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);

        final int? previousSequence = currentMachineSequence.putIfAbsent(machineId, () => null);
        final int? previousJob = currentMachineJob.putIfAbsent(machineId, () => null);
        final Duration setupDuration = _getSetupDuration(
          machineId,
          job.sequenceId,
          previousSequence,
          currentJobId: job.jobId,
          previousJobId: previousJob,
        );
        final Duration totalDuration = duration + setupDuration;

        DateTime endTime = _calculateEndWithSchedule(startTime, totalDuration);

        currentMachineAvailability[machineId] = endTime;
        currentMachineSequence[machineId] = job.sequenceId;
        currentMachineJob[machineId] = job.jobId;
        jobStartTime = endTime;
      }

      makespanEndTime = jobStartTime.isAfter(makespanEndTime) ? jobStartTime : makespanEndTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

  /* ---------- Genetic algorithm (Flow Shop sequencing) ---------- */

  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN FLOW SHOP");

    const int populationSize = 50;
    const int generations = 100;
    const double mutationRate = 0.1;

    if (inputJobs.isEmpty) return;

    List<List<FlowShopInput>> population = _initializePopulation(populationSize);

    List<FlowShopInput> bestIndividual = List.from(inputJobs);
    int bestFitness = _evaluateFitnessFlowShop(bestIndividual);

    for (int generation = 0; generation < generations; generation++) {
      List<Tuple2<List<FlowShopInput>, int>> evaluated = population.map((individual) {
        return Tuple2(individual, _evaluateFitnessFlowShop(individual));
      }).toList();

      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = List.from(evaluated.first.value1);
        print("Generación $generation: Mejor makespan = $bestFitness minutos");
      }

      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    print("Mejor secuencia encontrada: ${bestIndividual.map((j) => j.jobId).toList()}");
    print("Makespan óptimo: $bestFitness minutos");

    inputJobs = bestIndividual;
    _schedule((a, b) => 0);
  }

  List<List<FlowShopInput>> _initializePopulation(int size) {
    List<List<FlowShopInput>> population = [];
    for (int i = 0; i < size; i++) {
      List<FlowShopInput> shuffled = List.from(inputJobs);
      shuffled.shuffle();
      population.add(shuffled);
    }
    return population;
  }

  int _evaluateFitnessFlowShop(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> machineAvailability = {};
    Map<int, int?> machineSequence = {};

    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int machineId = task.value2;
        machineAvailability[machineId] = startDate;
        machineSequence[machineId] = null;
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable = machineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);

        final int? previousSequence = machineSequence.putIfAbsent(machineId, () => null);
        final Duration setupDuration = _getSetupDuration(machineId, job.sequenceId, previousSequence);
        final Duration totalDuration = duration + setupDuration;

        DateTime endTime = _calculateEndWithSchedule(startTime, totalDuration);

        machineAvailability[machineId] = endTime;
        machineSequence[machineId] = job.sequenceId;
        jobStartTime = endTime;
      }

      if (jobStartTime.isAfter(makespanEndTime)) makespanEndTime = jobStartTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

  List<List<FlowShopInput>> _generateNewPopulation(
    List<Tuple2<List<FlowShopInput>, int>> evaluated,
    int size,
    double mutationRate,
  ) {
    List<List<FlowShopInput>> newPop = [];

    for (int i = 0; i < size; i++) {
      final parent1 = _selectParent(evaluated);
      final parent2 = _selectParent(evaluated);
      List<FlowShopInput> child = _crossover(parent1, parent2);
      if (Random().nextDouble() < mutationRate) {
        child = _mutate(child);
      }
      newPop.add(child);
    }

    return newPop;
  }

  List<FlowShopInput> _selectParent(List<Tuple2<List<FlowShopInput>, int>> evaluated) {
    int k = min(5, evaluated.length);
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<FlowShopInput> _crossover(List<FlowShopInput> p1, List<FlowShopInput> p2) {
    final length = p1.length;
    if (length == 0) return [];

    final int point = Random().nextInt(length);
    final Set<int> jobIds = p1.sublist(0, point).map((j) => j.jobId).toSet();

    final List<FlowShopInput> child = [
      ...p1.sublist(0, point),
      ...p2.where((j) => !jobIds.contains(j.jobId)),
    ];

    // if child shorter (shouldn't) fill with remaining from p1
    if (child.length < length) {
      for (var j in p1) {
        if (!child.contains(j)) child.add(j);
        if (child.length == length) break;
      }
    }

    return child;
  }

  List<FlowShopInput> _mutate(List<FlowShopInput> individual) {
    if (individual.length < 2) return individual;
    int i = Random().nextInt(individual.length);
    int j = Random().nextInt(individual.length);
    final temp = individual[i];
    individual[i] = individual[j];
    individual[j] = temp;
    return individual;
  }
}

List<Map<String, dynamic>> flowShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(
      hour: payload['workingStartHour'] as int,
      minute: payload['workingStartMinute'] as int,
    ),
    TimeOfDay(
      hour: payload['workingEndHour'] as int,
      minute: payload['workingEndMinute'] as int,
    ),
  );

  int parseIntKey(dynamic key) {
    if (key is int) return key;
    return int.tryParse(key.toString()) ?? 0;
  }

  final inputJobs = <FlowShopInput>[];
  for (final rawJob in (payload['inputJobs'] as List).cast<Map<String, dynamic>>()) {
    final taskSequence = (rawJob['taskSequence'] as List)
        .cast<Map<String, dynamic>>()
        .map((task) => Tuple2(task['taskId'] as int, task['machineId'] as int))
        .toList();

    final taskTimes = <int, Duration>{};
    (rawJob['taskTimes'] as Map<String, dynamic>)
        .forEach((taskId, durationMs) {
      taskTimes[int.parse(taskId)] = Duration(milliseconds: durationMs as int);
    });

    inputJobs.add(FlowShopInput(
      rawJob['jobId'] as int,
      rawJob['sequenceId'] as int,
      DateTime.fromMillisecondsSinceEpoch(rawJob['dueDate'] as int),
      rawJob['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(rawJob['availableDate'] as int),
      taskSequence,
      taskTimes,
    ));
  }

  final machinesAvailability = <int, DateTime>{};
  (payload['machinesAvailability'] as Map<String, dynamic>)
      .forEach((machineId, dateMs) {
    machinesAvailability[parseIntKey(machineId)] =
        DateTime.fromMillisecondsSinceEpoch(dateMs as int);
  });

  final changeoverMatrix = <int, Map<int?, Map<int, Duration>>>{};
  (payload['changeoverMatrix'] as Map<String, dynamic>)
      .forEach((machineId, prevMap) {
    final machineKey = parseIntKey(machineId);
    final convertedPrevMap = <int?, Map<int, Duration>>{};
    (prevMap as Map<String, dynamic>).forEach((prevSequence, currMap) {
      final previousKey = prevSequence == 'null'
          ? null
          : int.tryParse(prevSequence.toString());
      final convertedCurrMap = <int, Duration>{};
      (currMap as Map<String, dynamic>).forEach((currSequence, minutes) {
        convertedCurrMap[int.parse(currSequence)] =
            Duration(minutes: minutes as int);
      });
      convertedPrevMap[previousKey] = convertedCurrMap;
    });
    changeoverMatrix[machineKey] = convertedPrevMap;
  });

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<String, dynamic>).map(
          (machineId, stateMap) => MapEntry(
            parseIntKey(machineId),
            (stateMap as Map<String, dynamic>).map(
              (fromState, targetMap) => MapEntry(
                fromState as String,
                (targetMap as Map<String, dynamic>).map(
                  (toState, minutes) => MapEntry(
                    toState as String,
                    minutes as int,
                  ),
                ),
              ),
            ),
          ),
        );

  final jobStates = payload['jobStates'] == null
      ? null
      : (payload['jobStates'] as Map<String, dynamic>).map(
          (jobId, machineStates) => MapEntry(
            parseIntKey(jobId),
            (machineStates as Map<String, dynamic>).map(
              (machineId, state) => MapEntry(
                parseIntKey(machineId),
                state as String,
              ),
            ),
          ),
        );

  final jobInterruptionPolicies = <int, JobInterruptionPolicy>{};
  if (payload['jobInterruptionPolicies'] != null) {
    (payload['jobInterruptionPolicies'] as Map<String, dynamic>)
        .forEach((jobId, policyMap) {
      final parsedJobId = parseIntKey(jobId);
      final policy = policyMap as Map<String, dynamic>;
      jobInterruptionPolicies[parsedJobId] = JobInterruptionPolicy(
        allowRestInterrupt: policy['allowRestInterrupt'] as bool? ?? false,
        allowScheduledInterrupt:
            policy['allowScheduledInterrupt'] as bool? ?? true,
        allowWorkHoursInterrupt:
            policy['allowWorkHoursInterrupt'] as bool? ?? true,
      );
    });
  }

  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  (payload['machineInactivities'] as Map<String, dynamic>)
      .forEach((machineId, inactivities) {
    final parsedMachineId = parseIntKey(machineId);
    final list = <MachineInactivityEntity>[];
    for (final rawActivity in (inactivities as List)
        .cast<Map<String, dynamic>>()) {
      list.add(MachineInactivityEntity(
        machineId: parsedMachineId,
        name: rawActivity['name'] as String,
        weekdays: (rawActivity['weekdays'] as List)
            .cast<int>()
            .map((index) => Weekday.values[index])
            .toSet(),
        startTime: Duration(minutes: rawActivity['startTimeMinutes'] as int),
        duration: Duration(minutes: rawActivity['durationMinutes'] as int),
      ));
    }
    machineInactivities[parsedMachineId] = list;
  });

  final machineContinueCapacity = <int, int>{};
  (payload['machineContinueCapacity'] as Map<String, dynamic>)
      .forEach((machineId, capacity) {
    machineContinueCapacity[parseIntKey(machineId)] = capacity as int;
  });

  final machineRestTime = <int, Duration?>{};
  (payload['machineRestTime'] as Map<String, dynamic>)
      .forEach((machineId, restMinutes) {
    machineRestTime[parseIntKey(machineId)] = restMinutes == null
        ? null
        : Duration(minutes: restMinutes as int);
  });

  final output = FlowShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    changeoverMatrix: changeoverMatrix,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    jobInterruptionPolicies: jobInterruptionPolicies,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
  ).output;

  return output.map((job) {
    return {
      'jobId': job.jobId,
      'startDate': job.startDate.millisecondsSinceEpoch,
      'dueDate': job.dueDate.millisecondsSinceEpoch,
      'endTime': job.endTime.millisecondsSinceEpoch,
      'machinesScheduling': job.machinesScheduling.map(
        (machineId, scheduling) => MapEntry(
          machineId.toString(),
          {
            'taskId': scheduling.value1,
            'startDate': scheduling.value2.startDate.millisecondsSinceEpoch,
            'endDate': scheduling.value2.endDate.millisecondsSinceEpoch,
          },
        ),
      ),
    };
  }).toList();
}
