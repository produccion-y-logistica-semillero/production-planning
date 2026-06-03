import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/schedule_calendar_utils.dart';
import 'package:production_planning/services/scheduling/setup_duration_utils.dart';
import 'package:production_planning/services/scheduling/task_scheduling_utils.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlexibleFlowInput {
  final int jobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //tuple2 <task id, Map<machineId, Duration of task in machine>>
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  FlexibleFlowInput(
    this.jobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.taskSequence,
  );
}

class FlexibleFlowOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //map<task id, tuple2<machineId, range scheuled>>
  final Map<int, Tuple2<int, Range>> scheduling;


  FlexibleFlowOutput(
      this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling);
}

class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleFlowInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  List<FlexibleFlowOutput> output = [];
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;
  final Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix;
  final Map<int, JobInterruptionPolicy> jobInterruptionPolicies;
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;
  final Map<int, int> machineProcessedCount = {};
  late final ScheduleCalendarUtils _calendar;
  final Map<int, int?> _machineLastJob = {};
  final Map<int, int?> _machineLastSequence = {};

  FlexibleFlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.stateSetupMatrix,
    this.jobStates,
    this.changeoverMatrix = const {},
    this.jobInterruptionPolicies = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) {
    _calendar = ScheduleCalendarUtils(
      workingSchedule: workingSchedule,
      machineInactivities: machineInactivities,
    );
    for (final machineId in machinesAvailability.keys) {
      machineProcessedCount[machineId] = 0;
    }
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
      case "JOHNSON":
        _applyJohnsonRuleFlexible(inputJobs);
        break;

      case "CDS":
        cdsAlgorithm();
        break;
      case "GENETICS":
        // Fallback genetics: order by combined score
        _schedule((a, b) {
          final scoreA = (a.priority / max(1, _totalProcessingTime(a))) + (1 / max(1, _totalProcessingTime(a)));
          final scoreB = (b.priority / max(1, _totalProcessingTime(b))) + (1 / max(1, _totalProcessingTime(b)));
          return scoreB.compareTo(scoreA);
        });
        break;
    }
  }

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
      );
  void lptRule() => _schedule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
      );
  void fifoRule() =>
      _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule() => _schedule((a, b) {
        double wsptA = a.priority / _totalProcessingTime(a);
        double wsptB = b.priority / _totalProcessingTime(b);
        return wsptB.compareTo(wsptA);
      });

  void _schedule(
      int Function(FlexibleFlowInput, FlexibleFlowInput) comparator) {

    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void _assignJobToMachines(FlexibleFlowInput job) {
    DateTime jobStartTime = job.availableDate;
    DateTime? actualStartTime;
    DateTime? finalEndTime;

    Map<int, Tuple2<int, Range>> scheduling = {};

    for (var task in job.taskSequence) {
      int stationId = task.value1;
      Map<int, Duration> machinesInStation = task.value2;

      Tuple2<int, int> selectedMachine =
          _selectBestMachine(stationId, machinesInStation, job.jobId, jobStartTime);
      int machineId = selectedMachine.value2;
      Duration processingTime = machinesInStation[machineId]!;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
      final earliestStart = jobStartTime.isAfter(machineAvailable)
          ? jobStartTime
          : machineAvailable;

      final int? previousJob = _machineLastJob.putIfAbsent(machineId, () => null);
      final int? previousSequence =
          _machineLastSequence.putIfAbsent(machineId, () => null);
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
        processingDuration: processingTime,
        policy: policy,
        continueCapacity: machineContinueCapacity[machineId] ?? 0,
        restTime: machineRestTime[machineId],
        machineProcessedCount: machineProcessedCount[machineId] ?? 0,
      );
      machineProcessedCount[machineId] = result.machineProcessedCount;

      actualStartTime ??= result.taskStart;
      finalEndTime = result.taskEnd;

      scheduling[stationId] =
          Tuple2(machineId, Range(result.taskStart, result.taskEnd));
      machinesAvailability[machineId] = result.machineAvailable;
      _machineLastJob[machineId] = job.jobId;
      _machineLastSequence[machineId] = job.sequenceId;

      jobStartTime = result.machineAvailable;
    }

    output.add(FlexibleFlowOutput(
      job.jobId,
      job.dueDate,
      actualStartTime!,
      finalEndTime!,
      scheduling,
    ));
  }


  Tuple2<int, int> _selectBestMachine(
      int stationId,
      Map<int, Duration> machinesInStation,
      int jobId,
      DateTime jobStartTime,
  ) {
    int bestMachineId = -1;
    DateTime bestEndTime = DateTime(9999);
    DateTime bestStartTime = DateTime(9999);

    for (var entry in machinesInStation.entries) {
      final machineId = entry.key;
      final processingTime = entry.value;
      final machineAvailable = machinesAvailability[machineId] ?? startDate;
      DateTime startTime = jobStartTime.isAfter(machineAvailable)
          ? jobStartTime
          : machineAvailable;
      startTime = _adjustForWorkingSchedule(startTime);

      final int? previousJob = _machineLastJob.putIfAbsent(machineId, () => null);
      final int? previousSequence =
          _machineLastSequence.putIfAbsent(machineId, () => null);
      final job = inputJobs.firstWhere((j) => j.jobId == jobId);
      final Duration setupDuration = _getSetupDuration(
        machineId,
        job.sequenceId,
        previousSequence,
        currentJobId: jobId,
        previousJobId: previousJob,
      );
      DateTime setupEnd = _adjustEndTimeForWorkingSchedule(
        startTime,
        startTime.add(setupDuration),
      );
      DateTime taskStart = _adjustForWorkingSchedule(setupEnd);
      DateTime endTime = _adjustEndTimeForWorkingSchedule(
        taskStart,
        taskStart.add(processingTime),
      );

      if (bestMachineId == -1 ||
          endTime.isBefore(bestEndTime) ||
          (endTime.isAtSameMomentAs(bestEndTime) && taskStart.isBefore(bestStartTime))) {
        bestMachineId = machineId;
        bestEndTime = endTime;
        bestStartTime = taskStart;
      }
    }

    return Tuple2(stationId, bestMachineId);
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
    int currentSequenceId,
    int? previousSequenceId, {
    int? currentJobId,
    int? previousJobId,
  }) {
    if (previousJobId != null &&
        previousJobId > 0 &&
        stateSetupMatrix != null &&
        jobStates != null &&
        currentJobId != null) {
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

    final machineMatrix = changeoverMatrix[machineId];
    if (machineMatrix == null) return Duration.zero;

    if (previousSequenceId != null) {
      final previousDurations = machineMatrix[previousSequenceId];
      if (previousDurations != null &&
          previousDurations.containsKey(currentSequenceId)) {
        return previousDurations[currentSequenceId]!;
      }
    }

    final defaultDurations = machineMatrix[null];
    if (defaultDurations != null &&
        defaultDurations.containsKey(currentSequenceId)) {
      return defaultDurations[currentSequenceId]!;
    }

    return Duration.zero;
  }

  void eddaRule() => _dynamicSchedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptaRule() => _dynamicSchedule(
      (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)));
  void lptaRule() => _dynamicSchedule(
      (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)));
  void fifoaRule() =>
      _dynamicSchedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptaRule() => _dynamicSchedule((a, b) {
        double wsptA = a.priority / _totalProcessingTime(a);
        double wsptB = b.priority / _totalProcessingTime(b);
        return wsptB.compareTo(wsptA);
      });


  void msRule() {
    int accumulatedProcessingTime = 0;
    DateTime currentTime = startDate;
    List<FlexibleFlowInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        int slackA = _calculateSlack(a, accumulatedProcessingTime, currentTime);
        int slackB = _calculateSlack(b, accumulatedProcessingTime, currentTime);
        return slackA.compareTo(slackB);
      });

      FlexibleFlowInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
      accumulatedProcessingTime += _totalProcessingTime(selectedJob);
      currentTime = output.last.endTime;
    }
  }

  void crRule() {
    int accumulatedProcessingTime = 0;
    DateTime currentTime = startDate;
    List<FlexibleFlowInput> remainingJobs = List.from(inputJobs);

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort((a, b) {
        double crA = _calculateCR(a, accumulatedProcessingTime, currentTime);
        double crB = _calculateCR(b, accumulatedProcessingTime, currentTime);
        return crA.compareTo(crB);
      });

      FlexibleFlowInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
      accumulatedProcessingTime += _totalProcessingTime(selectedJob);
      currentTime = output.last.endTime;
    }
  }

  void atcRule() {
    DateTime currentTime = startDate;
    List<FlexibleFlowInput> remainingJobs = List.from(inputJobs);
    output.clear();
    int elapsedTime = 0;

    double K = 3.0;

    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(
        (a, b) => _calculateATCPriority(b, currentTime, elapsedTime, K)
            .compareTo(_calculateATCPriority(a, currentTime, elapsedTime, K)),

      );
      FlexibleFlowInput selectedJob = remainingJobs.removeAt(0);
      _assignJobToMachines(selectedJob);
      elapsedTime += _totalProcessingTime(selectedJob);
      currentTime = output.last.endTime;
    }
  }

  double _calculateATCPriority(
    FlexibleFlowInput job,
    DateTime currentTime,
    int elapsedTime,
    double K,
  ) {
    int processingTime = _totalProcessingTime(job);
    double avgProcessingTime = processingTime / job.taskSequence.length;
    double timeDiff = job.dueDate.difference(currentTime).inMinutes.toDouble();
    return (job.priority / processingTime) *
        (exp(
          -max(timeDiff - processingTime - elapsedTime, 0) /
              (K * avgProcessingTime),
        ));
  }


  void _dynamicSchedule(
      int Function(FlexibleFlowInput, FlexibleFlowInput) comparator) {

    List<FlexibleFlowInput> remainingJobs = List.from(inputJobs);
    while (remainingJobs.isNotEmpty) {
      remainingJobs.sort(comparator);
      FlexibleFlowInput job = remainingJobs.removeAt(0);
      _assignJobToMachines(job);
    }
  }

  double _calculateCR(
      FlexibleFlowInput job, int accumulatedTime, DateTime currentTime) {
    int remainingTime =
        job.dueDate.difference(currentTime).inMinutes - accumulatedTime;
    int processingTime = _totalProcessingTime(job);
    return processingTime > 0
        ? (remainingTime > 0 ? remainingTime / processingTime : double.infinity)
        : double.infinity;
  }

  int _calculateSlack(
      FlexibleFlowInput job, int accumulatedTime, DateTime currentTime) {
    int totalProcessingTime = _totalProcessingTime(job);
    int slack = job.dueDate.difference(currentTime).inMinutes -
        totalProcessingTime -
        accumulatedTime;

    return slack < 0 ? 0 : slack;
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
          job.sequenceId,
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
    _schedule((a, b) => 0); // Puedes usar una regla dummy o alguna prioridad
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
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
    _schedule((a, b) => 0);
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
}

List<Map<String, dynamic>> flexibleFlowShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(hour: payload['workingStartHour'] as int, minute: payload['workingStartMinute'] as int),
    TimeOfDay(hour: payload['workingEndHour'] as int, minute: payload['workingEndMinute'] as int),
  );

  int parseIntKey(dynamic key) {
    if (key is int) return key;
    return int.tryParse(key.toString()) ?? 0;
  }

  final inputJobs = (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jobMap = Map<String, dynamic>.from(jobData as Map);
    final taskSequence = (jobMap['taskSequence'] as List<dynamic>).map((taskData) {
      final taskMap = Map<String, dynamic>.from(taskData as Map);
      final machineDurations = (taskMap['machineDurations'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(parseIntKey(key), Duration(milliseconds: value as int)));
      return Tuple2(taskMap['taskId'] as int, machineDurations);
    }).toList();

    return FlexibleFlowInput(
      jobMap['jobId'] as int,
      jobMap['sequenceId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
      jobMap['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['availableDate'] as int),
      taskSequence,
    );
  }).toList();

  final machinesAvailability = (payload['machinesAvailability'] as Map<dynamic, dynamic>)
      .map((key, value) => MapEntry(parseIntKey(key), DateTime.fromMillisecondsSinceEpoch(value as int)));

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
                parseIntKey(key),
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
            parseIntKey(key),
            (Map<dynamic, dynamic>.from(value as Map)).map(
              (mKey, state) => MapEntry(parseIntKey(mKey), state as String),
            ),
          ),
        );

  final changeoverMatrix = <int, Map<int?, Map<int, Duration>>>{};
  if (payload['changeoverMatrix'] != null) {
    (payload['changeoverMatrix'] as Map<dynamic, dynamic>)
        .forEach((machineId, prevMap) {
      final machineKey = parseIntKey(machineId);
      final convertedPrevMap = <int?, Map<int, Duration>>{};
      (prevMap as Map<dynamic, dynamic>).forEach((prevSequence, currMap) {
        final previousKey = prevSequence == 'null'
            ? null
            : int.tryParse(prevSequence.toString());
        final convertedCurrMap = <int, Duration>{};
        (currMap as Map<dynamic, dynamic>).forEach((currSequence, minutes) {
          convertedCurrMap[parseIntKey(currSequence)] =
              Duration(minutes: minutes as int);
        });
        convertedPrevMap[previousKey] = convertedCurrMap;
      });
      changeoverMatrix[machineKey] = convertedPrevMap;
    });
  }

  final jobInterruptionPolicies = <int, JobInterruptionPolicy>{};
  if (payload['jobInterruptionPolicies'] != null) {
    (payload['jobInterruptionPolicies'] as Map<dynamic, dynamic>)
        .forEach((jobId, policyMap) {
      final parsedJobId = parseIntKey(jobId);
      final policy = Map<String, dynamic>.from(policyMap as Map);
      jobInterruptionPolicies[parsedJobId] = JobInterruptionPolicy(
        allowRestInterrupt: policy['allowRestInterrupt'] as bool? ?? false,
        allowScheduledInterrupt: policy['allowScheduledInterrupt'] as bool? ?? true,
        allowWorkHoursInterrupt: policy['allowWorkHoursInterrupt'] as bool? ?? true,
      );
    });
  }

  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  if (payload['machineInactivities'] != null) {
    (payload['machineInactivities'] as Map<dynamic, dynamic>)
        .forEach((machineId, inactivities) {
      final parsedMachineId = parseIntKey(machineId);
      final list = <MachineInactivityEntity>[];
      for (final rawActivity in (inactivities as List).cast<Map<String, dynamic>>()) {
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
  }

  final machineContinueCapacity = <int, int>{};
  if (payload['machineContinueCapacity'] != null) {
    (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
        .forEach((machineId, capacity) {
      machineContinueCapacity[parseIntKey(machineId)] = capacity as int;
    });
  }

  final machineRestTime = <int, Duration?>{};
  if (payload['machineRestTime'] != null) {
    (payload['machineRestTime'] as Map<dynamic, dynamic>)
        .forEach((machineId, restMinutes) {
      machineRestTime[parseIntKey(machineId)] = restMinutes == null
          ? null
          : Duration(minutes: restMinutes as int);
    });
  }

  final output = FlexibleFlowShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    changeoverMatrix: changeoverMatrix,
    jobInterruptionPolicies: jobInterruptionPolicies,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
  ).output;

  return output.map((out) {
    return {
      'jobId': out.jobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'availableDate': out.startDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling': out.scheduling.map((key, value) => MapEntry(key.toString(), {
            'machineId': value.value1,
            'startDate': value.value2.startDate.millisecondsSinceEpoch,
            'endDate': value.value2.endDate.millisecondsSinceEpoch,
          })),
    };
  }).toList();
}


