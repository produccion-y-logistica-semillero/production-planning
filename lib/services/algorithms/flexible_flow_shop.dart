import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlexibleFlowInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //tuple2 <task id, Map<machineId, Duration of task in machine>>
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;


  FlexibleFlowInput(this.jobId, this.dueDate, this.priority, this.availableDate,
      this.taskSequence);

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
  final Map<int, int?> _machineLastJob = {};

  // Machine inactivity support
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;
  Map<int, int> machineProcessedCount = {};

  FlexibleFlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) {
    // Inicializar contador de procesamiento por máquina
    for (final machineId in machinesAvailability.keys) {
      machineProcessedCount[machineId] = 0;
    }
    switch (rule) {
    this.stateSetupMatrix,
    this.jobStates,
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
      DateTime startTime = jobStartTime.isAfter(machineAvailable)
          ? jobStartTime
          : machineAvailable;

      startTime = _adjustForWorkingSchedule(startTime);
      final end = startTime.add(processingTime);
      DateTime endTime = _adjustEndTimeWithInactivities(machineId, startTime, end);

      // Aplicar descanso por continueCapacity
      DateTime finalEnd = endTime;
      final capacity = machineContinueCapacity[machineId] ?? 0;
      final restTime = machineRestTime[machineId];

      if (capacity > 0 && restTime != null) {
        machineProcessedCount[machineId] =
            (machineProcessedCount[machineId] ?? 0) + 1;

        if (machineProcessedCount[machineId]! >= capacity) {
          finalEnd = endTime.add(restTime);
          machineProcessedCount[machineId] = 0;
        }
      }

      final int? previousJob = _machineLastJob.putIfAbsent(machineId, () => null);
      final Duration setupDuration = _getSetupDuration(
        machineId,
        job.jobId,
        previousJob,
      );

      DateTime setupEnd = _adjustEndTimeForWorkingSchedule(
          startTime, startTime.add(setupDuration));
      DateTime taskStart = _adjustForWorkingSchedule(setupEnd);
      DateTime endTime = _adjustEndTimeForWorkingSchedule(
          taskStart, taskStart.add(processingTime));

      // Guarda el primer tiempo real de inicio
      actualStartTime ??= taskStart;
      // Guarda el último tiempo de finalización
      finalEndTime = endTime;

      scheduling[stationId] = Tuple2(machineId, Range(startTime, endTime));
      machinesAvailability[machineId] = finalEnd;
      scheduling[stationId] = Tuple2(machineId, Range(taskStart, endTime));
      machinesAvailability[machineId] = endTime;
      _machineLastJob[machineId] = job.jobId;

      jobStartTime = endTime;
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
      final Duration setupDuration = _getSetupDuration(machineId, jobId, previousJob);
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

  // Obtener las inactividades de una máquina para un día específico
  List<Range> _getInactivitiesForDay(int machineId, DateTime day) {
    final inactivities = machineInactivities[machineId] ?? [];
    final weekday = day.weekday;
    final List<Range> dayInactivities = [];

    for (final inactivity in inactivities) {
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
  DateTime _adjustEndTimeWithInactivities(
      int machineId, DateTime start, DateTime end) {
    DateTime current = start;
    Duration remaining = end.difference(start);

    while (remaining > Duration.zero) {
      current = _adjustForWorkingSchedule(current);

      final dayInactivities = _getInactivitiesForDay(machineId, current);

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

  Duration _getSetupDuration(
    int machineId,
    int currentJobId,
    int? previousJobId,
  ) {
    // Only apply state-based setup if we have previous job and both matrices
    if (previousJobId != null && 
        previousJobId > 0 && 
        stateSetupMatrix != null && 
        jobStates != null) {
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

  final output = FlexibleFlowShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
  ).output;

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
    };
  }).toList();
}

}


