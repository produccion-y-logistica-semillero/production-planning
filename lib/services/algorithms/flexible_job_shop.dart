import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
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

  FlexibleJobOutput(
      this.jobId, this.dbJobId, this.dueDate, this.startDate, this.endTime,
      this.scheduling,
      {Map<int, List<ProcessingSegment>>? segmentsByTask})
      : segmentsByTask = segmentsByTask ??
            scheduling.map((taskId, entry) => MapEntry(
                taskId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
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
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};
  List<FlexibleJobOutput> output = [];

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
      case "ATCS":
        scheduleFlexibleJobShopATCS();
        break;
      case "MS":
        scheduleFlexibleJobShopMS();
        break;
      case "CR":
        scheduleFlexibleJobShopCR();
        break;
      case "GENETICS":
        scheduleFlexibleJobShopGENETICS();
        break;
    }
  }
 
  void scheduleFlexibleJobShopGENETICS() {
    // Simple genetics-like heuristic: combine CR and WSPT into a score
    print('FlexibleJobShop: starting scheduling (GENETICS)');
    _schedule((a, b) {
      final scoreA = _geneticsScore(a.job, a.duration);
      final scoreB = _geneticsScore(b.job, b.duration);
      return scoreB.compareTo(scoreA);
    });
    print('FlexibleJobShop: scheduling finished (GENETICS)');
  }

  int _safeMinutes(Duration duration) => max(duration.inMinutes, 1);

  double _geneticsScore(FlexibleJobInput job, Duration duration) {
    final cr = _calculateCR(job, duration, 0);
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

    if (previousJobId != null &&
        previousJobId > 0 &&
        stateSetupMatrix != null &&
        jobStates != null) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        final previousState = jobStates![previousJobId]?[machineId];
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

  late Map<int, int> jobOperationIndex;

  void scheduleFlexibleJobShopFIFO() {
    _schedule((a, b) => a.job.jobId
        .compareTo(b.job.jobId)); // FIFO basado en el orden de llegada
  }

  void scheduleFlexibleJobShopSPT() {
    _schedule((a, b) => a.duration.compareTo(b.duration));
  }

  void scheduleFlexibleJobShopLPT() {
    _schedule((a, b) => b.duration.compareTo(a.duration));
  }

  void scheduleFlexibleJobShopEDD() {
    _schedule((a, b) => a.job.dueDate.compareTo(b.job.dueDate));
  }

  void scheduleFlexibleJobShopWSPT() {
    _schedule((a, b) {
      final wsptA = a.job.priority / _safeMinutes(a.duration);
      final wsptB = b.job.priority / _safeMinutes(b.duration);
      return wsptB.compareTo(wsptA); // mayor primero
    });
  }

  void scheduleFlexibleJobShopMWR() {
    _schedule((a, b) {
      final remainingA = _remainingWork(a.job, jobOperationIndex[a.job.jobId]!);
      final remainingB = _remainingWork(b.job, jobOperationIndex[b.job.jobId]!);
      return remainingB.compareTo(remainingA); // más trabajo primero
    });
  }

  int _remainingWork(FlexibleJobInput job, int currentOpIndex) {
    int totalMinutes = 0;

    for (int i = currentOpIndex; i < job.taskSequence.length; i++) {
      final task = job.taskSequence[i];
      if (task.value2.isEmpty) continue;
      final sum = task.value2.values.fold<int>(0, (total, duration) => total + duration.inMinutes);
      final avgDuration = task.value2.isEmpty ? 0 : sum ~/ task.value2.length;
      totalMinutes += avgDuration;
    }

    return totalMinutes;
  }

  void scheduleFlexibleJobShopMS() {

    int accumulatedProcessingTime = 0; // Acumulamos el tiempo aquí

    _schedule((a, b) {
      final accumulatedProcessingTimeA =
          _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB =
          _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final slackA =
          _calculateSlack(a.job, a.duration, accumulatedProcessingTimeA);
      final slackB =
          _calculateSlack(b.job, b.duration, accumulatedProcessingTimeB);

      return slackA.compareTo(slackB);
    });
  }

  int _accumulatedProcessingTimeForJob(
      FlexibleJobInput job, int currentAccumulatedTime) {
    int totalProcessingTime = currentAccumulatedTime; // Empezamos desde el tiempo acumulado

    final opIndex = jobOperationIndex[job.jobId]!;

    for (int i = 0; i < opIndex; i++) {
      final task = job.taskSequence[i];
      if (task.value2.isEmpty) continue;
      final sum = task.value2.values.fold<int>(0, (total, duration) => total + duration.inMinutes);
      final avgDuration = task.value2.isEmpty ? 0 : sum ~/ task.value2.length;
      totalProcessingTime += avgDuration;
    }

    return totalProcessingTime;
  }


  double _calculateSlack(
      FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final slack = dj.difference(DateTime.now()).inMinutes -
        _safeMinutes(pj) -
        accumulatedProcessingTime;
    return slack < 0 ? 0 : slack.toDouble();
  }

  void scheduleFlexibleJobShopCR() {

    int accumulatedProcessingTime =
        0; // Inicializamos el acumulado en cada llamada

    _schedule((a, b) {
      final accumulatedProcessingTimeA =
          _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB =
          _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final crA = _calculateCR(a.job, a.duration, accumulatedProcessingTimeA);
      final crB = _calculateCR(b.job, b.duration, accumulatedProcessingTimeB);

      return crA.compareTo(crB);
    });
  }


  double _calculateCR(
      FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final cr =
        (dj.difference(DateTime.now()).inMinutes - accumulatedProcessingTime) /
            _safeMinutes(pj);
    return cr < 0 ? 0 : cr;
  }

  void scheduleFlexibleJobShopATCS() {
    int accumulatedProcessingTime =
        0; // Inicializamos el acumulado en cada llamada

    _schedule((a, b) {
      final accumulatedProcessingTimeA =
          _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB =
          _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final atcsA =
          _calculateATCS(a.job, a.duration, accumulatedProcessingTimeA);
      final atcsB =
          _calculateATCS(b.job, b.duration, accumulatedProcessingTimeB);

      return atcsB
          .compareTo(atcsA); // Invertido para asignar el mayor ATCS primero
    });
  }

  double _calculateATCS(
      FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final wj = job.priority
        .toDouble(); // Asumimos que el "peso" es el valor de la prioridad del trabajo
    final pPromedio =
        _averageProcessingTime(); // Promedio de tiempos de procesamiento

    final maxSlack = max(
        dj.difference(DateTime.now()).inMinutes -
            _safeMinutes(pj) -
            accumulatedProcessingTime,
        0);
    const k = 1.0; // Este parámetro k puede ser ajustado
    final exponent = -(maxSlack / (k * pPromedio));
    final atcs = (wj / _safeMinutes(pj)) * exp(exponent);

    return atcs;
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

  DateTime _getJobReadyTime(FlexibleJobInput job, int taskId, Map<int, DateTime> compTimes) {
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

  void _schedule(int Function(dynamic, dynamic) comparator) {
    print('FlexibleJobShop._schedule: entering main loop');
    jobOperationIndex = {
      for (var job in inputJobs) job.jobId: 0,
    };

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

    int _iter = 0;
    const int _maxIter = 1000000; // safety cap
    int lastCompletedCount = 0;
    int stallIterations = 0;

    while (completedTasks.entries.any((entry) {
      final job = inputJobs.firstWhere((j) => j.jobId == entry.key);
      return entry.value.length < job.taskSequence.length;
    })) {
      _iter++;
      if (_iter % 10000 == 0) {
        print('FlexibleJobShop._schedule: iter=$_iter, remainingJobs=${completedTasks.values.map((s) => s.length).join(',')}');
      }
      if (_iter > _maxIter) {
        print('FlexibleJobShop._schedule: reached max iterations ($_maxIter), aborting to avoid freeze');
        break;
      }
      final currentCompletedCount = completedTasks.values.fold<int>(0, (sum, set) => sum + set.length);
      if (currentCompletedCount == lastCompletedCount) {
        stallIterations += 1;
      } else {
        stallIterations = 0;
      }
      lastCompletedCount = currentCompletedCount;
      if (stallIterations > 1000) {
        print('FlexibleJobShop._schedule: no progress after $stallIterations iterations, aborting to avoid freeze');
        break;
      }

      List<
          ({
            FlexibleJobInput job,
            int taskId,
            int machineId,
            Duration duration,
            DateTime earliestStart
          })> candidates = [];

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
            final machineAvailable = machinesAvailability[machineId] ?? startDate;

            final earliestStart = machineAvailable.isAfter(jobReadyTime)
                ? machineAvailable
                : jobReadyTime;
            final adjustedStart = _adjustForWorkingSchedule(earliestStart);

            candidates.add((
              job: job,
              taskId: taskId,
              machineId: machineId,
              duration: duration,
              earliestStart: adjustedStart
            ));
          }
        }
      }

      if (candidates.isEmpty) {
        print('FlexibleJobShop._schedule: no schedulable candidates remaining, aborting loop');
        break;
      }

      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      final selected = candidates.first;
      final start = selected.earliestStart;

      // Calcular tiempo de alistamiento
      final int? previousJob =
          _machineLastJob.putIfAbsent(selected.machineId, () => null);
      final Duration setupDuration = _getSetupDuration(
          selected.machineId, selected.job.jobId, previousJob);

      // Split setup+processing into segments wherever the work-shift end, a
      // maintenance window, or the continuous-use rest cap would otherwise
      // fall inside this task's span on this machine.
      final schedule = _engineFor(selected.machineId).computeSegments(
        earliestStart: start,
        totalDuration: setupDuration + selected.duration,
        priorContinuousUsage:
            _machineContinuousUsage[selected.machineId] ?? Duration.zero,
        interruptible: selected.job.isTaskInterruptible(selected.taskId),
      );
      final DateTime taskStart = schedule.startDate;
      final DateTime adjustedEnd = schedule.completionTime;

      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(taskStart, adjustedEnd));
      jobSegments[selected.job.jobId]![selected.taskId] = schedule.segments;

      machinesAvailability[selected.machineId] = adjustedEnd;
      _machineContinuousUsage[selected.machineId] = schedule.segments.length > 1
          ? schedule.segments.last.duration
          : (_machineContinuousUsage[selected.machineId] ?? Duration.zero) +
              schedule.segments.single.duration;
      completedTasks[selected.job.jobId]!.add(selected.taskId);
      taskCompletionTimes[selected.job.jobId]![selected.taskId] = adjustedEnd;
      jobOperationIndex[selected.job.jobId] =
          (jobOperationIndex[selected.job.jobId] ?? 0) + 1;
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
      _machineLastJob[selected.machineId] = selected.job.dbJobId;
    }
    print('FlexibleJobShop._schedule: exiting main loop after iter=$_iter');

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
      ));
    }
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
    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }
    return end;
  }


  int calcularCmax(List<FlexibleJobOutput> output) {
    if (output.isEmpty) return 0;
    final startTimes = output.map((job) => job.startDate).toList();
    final endTimes = output.map((job) => job.endTime).toList();

    final earliestStart = startTimes.fold<DateTime>(startTimes.first,
        (a, b) => a.isBefore(b) ? a : b);
    final latestEnd = endTimes.fold<DateTime>(endTimes.first,
        (a, b) => a.isAfter(b) ? a : b);

    final duration = latestEnd.difference(earliestStart);
    return duration.inHours;
  }
}

List<Map<String, dynamic>> flexibleJobShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(hour: payload['workingStartHour'] as int, minute: payload['workingStartMinute'] as int),
    TimeOfDay(hour: payload['workingEndHour'] as int, minute: payload['workingEndMinute'] as int),
  );

  final inputJobs = (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jobMap = Map<String, dynamic>.from(jobData as Map);
    final Map<int, bool> interruptibleByTask = {};
    final taskSequence = (jobMap['taskSequence'] as List<dynamic>).map((taskData) {
      final taskMap = Map<String, dynamic>.from(taskData as Map);
      final durations = (taskMap['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) => MapEntry(key as int, Duration(milliseconds: value as int)),
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

  final machinesAvailability = (payload['machinesAvailability'] as Map<dynamic, dynamic>)
      .map((key, value) => MapEntry(key as int, DateTime.fromMillisecondsSinceEpoch(value as int)));

  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  for (final entry in (payload['machineInactivities'] as Map<dynamic, dynamic>).entries) {
    final machineId = entry.key as int;
    final list = (entry.value as List<dynamic>);
    machineInactivities[machineId] = list.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return MachineInactivityEntity(
        machineId: map['machineId'] as int,
        name: map['name'] as String,
        weekdays: (map['weekdays'] as List<dynamic>).map((w) => Weekday.values[w as int]).toSet(),
        startTime: Duration(minutes: map['startTimeMinutes'] as int),
        duration: Duration(minutes: map['durationMinutes'] as int),
      );
    }).cast<MachineInactivityEntity>().toList();
  }

  final machineContinueCapacity = (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
      .map((key, value) => MapEntry(key as int, value as int));

  final machineRestTime = <int, Duration?>{};
  for (final entry in (payload['machineRestTime'] as Map<dynamic, dynamic>).entries) {
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
                (Map<dynamic, dynamic>.from(curr as Map)).map((next, minutes) => MapEntry(next as String, minutes as int)),
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

  final output = FlexibleJobShop(
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
  ).output;

  return output.map((out) {
    return {
      'jobId': out.jobId,
      'dbJobId': out.dbJobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling': out.scheduling.map((key, value) => MapEntry(key.toString(), {
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
    };
  }).toList();
}
