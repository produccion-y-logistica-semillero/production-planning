import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/scheduling/schedule_calendar_utils.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class OpenShopInput {
  final int jobId;
  final int dbJobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // Lista de operaciones sin orden específico: <taskId, Map<machineId, Duration>>
  final List<Tuple2<int, Map<int, Duration>>> operations;
  final List<TaskDependencyEntity> dependencies;

  OpenShopInput(
    this.jobId,
    this.dbJobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.operations, {
    this.dependencies = const [],
  }
  );
}

class OpenShopOutput {
  final int jobId;
  final int dbJobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  // Scheduling: taskId -> (machineId, Range)
  final Map<int, Tuple2<int, Range>> scheduling;

  OpenShopOutput(
    this.jobId,
    this.dbJobId,
    this.dueDate,
    this.startDate,
    this.endTime,
    this.scheduling,
  );
}

class OpenShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<OpenShopInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;
  Map<int, int> machineProcessedCount = {};
  final Map<int, Map<int?, Map<int, Duration>>> changeoverMatrix;
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;
  final Map<int, JobInterruptionPolicy> jobInterruptionPolicies;
  late final ScheduleCalendarUtils _calendar;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};
  List<OpenShopOutput> output = [];

  OpenShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
    this.changeoverMatrix = const {},
    this.stateSetupMatrix,
    this.jobStates,
    this.jobInterruptionPolicies = const {},
  }) {
    _calendar = ScheduleCalendarUtils(
      workingSchedule: workingSchedule,
      machineInactivities: machineInactivities,
    );
    // Inicializar contador de procesamiento por máquina
    for (final machineId in machinesAvailability.keys) {
      machineProcessedCount[machineId] = 0;
    }
    _initializeMachineLastSequence();
    final r = rule.toUpperCase();
    print('OpenShop: starting scheduling rule=$r for ${inputJobs.length} jobs');
    switch (r) {
      case "FIFO":
        scheduleOpenShopFIFO();
        break;
      case "SPT":
        scheduleOpenShopSPT();
        break;
      case "LPT":
        scheduleOpenShopLPT();
        break;
      case "EDD":
        scheduleOpenShopEDD();
        break;
      case "WSPT":
        scheduleOpenShopWSPT();
        break;
      case "MS":
        scheduleOpenShopMS();
        break;
      case "MWR":
        scheduleOpenShopMWR();
        break;
      case "CR":
        scheduleOpenShopCR();
        break;
      case "ATCS":
        scheduleOpenShopATCS();
        break;
      case "GENETICS":
        // Simple genetics-like ordering based on CR and WSPT
        _schedule((a, b) {
          final crA = _calculateCR(a.job as OpenShopInput, a.duration as Duration);
          final crB = _calculateCR(b.job as OpenShopInput, b.duration as Duration);
          final durationMinutesA = (a.duration as Duration).inMinutes;
          final durationMinutesB = (b.duration as Duration).inMinutes;
          final wsptA = a.job.priority / max(1, durationMinutesA);
          final wsptB = b.job.priority / max(1, durationMinutesB);
          final scoreA = (1 / max(crA, 0.0001)) + wsptA;
          final scoreB = (1 / max(crB, 0.0001)) + wsptB;
          return scoreB.compareTo(scoreA);
        });
        break;
      default:
        scheduleOpenShopSPT();
    }
    print('OpenShop: constructor finished (scheduling started/completed)');
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
    for (final machineId in changeoverMatrix.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
  }

  Duration _getSetupDuration(
    int machineId,
    int currentSequenceId,
    int? previousSequenceId,
  ) {
    final machineMatrix = changeoverMatrix[machineId];
    if (machineMatrix == null) return Duration.zero;

    final previousDurations = machineMatrix[previousSequenceId];
    if (previousDurations != null &&
        previousDurations.containsKey(currentSequenceId)) {
      return previousDurations[currentSequenceId]!;
    }

    final defaultDurations = machineMatrix[null];
    if (defaultDurations != null &&
        defaultDurations.containsKey(currentSequenceId)) {
      return defaultDurations[currentSequenceId]!;
    }

    return Duration.zero;
  }

  JobInterruptionPolicy _policyForJob(int dbJobId) =>
      jobInterruptionPolicies[dbJobId] ?? JobInterruptionPolicy.legacyDefault;

  void scheduleOpenShopFIFO() {
    _schedule((a, b) => a.job.availableDate.compareTo(b.job.availableDate));
  }

  void scheduleOpenShopSPT() {
    _schedule((a, b) => a.duration.compareTo(b.duration));
  }

  void scheduleOpenShopLPT() {
    _schedule((a, b) => b.duration.compareTo(a.duration));
  }

  void scheduleOpenShopEDD() {
    _schedule((a, b) => a.job.dueDate.compareTo(b.job.dueDate));
  }

  void scheduleOpenShopWSPT() {
    _schedule((a, b) {
      final wsptA = a.job.priority / a.duration.inMinutes;
      final wsptB = b.job.priority / b.duration.inMinutes;
      return wsptB.compareTo(wsptA);
    });
  }

  void scheduleOpenShopMS() {
    _schedule((a, b) {
      final slackA = _calculateSlack(a.job as OpenShopInput);
      final slackB = _calculateSlack(b.job as OpenShopInput);
      return slackA.compareTo(slackB);
    });
  }

  void scheduleOpenShopMWR() {
    _schedule((a, b) {
      final remainingA = _remainingWork(a.job as OpenShopInput, a.taskId as int);
      final remainingB = _remainingWork(b.job as OpenShopInput, b.taskId as int);
      return remainingB.compareTo(remainingA);
    });
  }

  void scheduleOpenShopCR() {
    _schedule((a, b) {
      final crA = _calculateCR(a.job as OpenShopInput, a.duration as Duration);
      final crB = _calculateCR(b.job as OpenShopInput, b.duration as Duration);
      return crA.compareTo(crB);
    });
  }

  void scheduleOpenShopATCS() {
    _schedule((a, b) {
      final atcsA = _calculateATCS(a.job as OpenShopInput, a.duration as Duration);
      final atcsB = _calculateATCS(b.job as OpenShopInput, b.duration as Duration);
      return atcsB.compareTo(atcsA);
    });
  }

  int _remainingWork(OpenShopInput job, int currentTaskId) {
    // Calcula el trabajo restante para un job (excluyendo la tarea actual)
    int totalMinutes = 0;
    for (var operation in job.operations) {
      if (operation.value1 != currentTaskId) {
        if (operation.value2.isEmpty) continue;
        final sum = operation.value2.values.map((d) => d.inMinutes).fold<int>(0, (a, b) => a + b);
        final avgDuration = sum ~/ operation.value2.length;
        totalMinutes += avgDuration;
      }
    }
    return totalMinutes;
  }

  double _calculateSlack(OpenShopInput job) {
    final dj = job.dueDate;
    final remainingWork = _remainingWork(job, -1);
    final slack = dj.difference(DateTime.now()).inMinutes - remainingWork;
    return slack < 0 ? 0 : slack.toDouble();
  }

  double _calculateCR(OpenShopInput job, Duration duration) {
    final dj = job.dueDate;
    final pj = duration;
    final cr = (dj.difference(DateTime.now()).inMinutes) / pj.inMinutes;
    return cr < 0 ? 0 : cr;
  }

  double _calculateATCS(OpenShopInput job, Duration duration) {
    const k = 2.0;
    final avgProcessingTime = _averageProcessingTime();
    final processingTime = duration.inMinutes;
    final remainingTime = job.dueDate.difference(DateTime.now()).inMinutes;

    final tardinessFactor =
        remainingTime > 0 ? remainingTime / (k * avgProcessingTime) : 0;

    return (job.priority / processingTime) * exp(-max(0, tardinessFactor));
  }

  double _averageProcessingTime() {
    double totalProcessingTime = 0;
    int taskCount = 0;

    for (var job in inputJobs) {
      for (var operation in job.operations) {
        for (var duration in operation.value2.values) {
          totalProcessingTime += duration.inMinutes.toDouble();
          taskCount++;
        }
      }
    }
    return taskCount > 0 ? totalProcessingTime / taskCount : 1;
  }

  void _schedule(int Function(dynamic, dynamic) comparator) {
    print('OpenShop._schedule: entering main loop for ${inputJobs.length} jobs');
    // Rastrear qué operaciones ya se completaron por job
    Map<int, Set<int>> completedOperations = {
      for (var job in inputJobs) job.jobId: <int>{},
    };

    Map<int, Map<int, Tuple2<int, Range>>> jobSchedulings = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, DateTime> jobAvailability = {
      for (var job in inputJobs) job.jobId: job.availableDate,
    };

    Map<int, Map<int, DateTime>> taskCompletionTimes = {
      for (var job in inputJobs) job.jobId: {},
    };

    bool _isTaskReady(OpenShopInput job, int taskId, Set<int> completed) {
      if (job.dependencies.isEmpty) {
        // Treat operations as unordered; allow first operation if no predecessor defined
        final idx = job.operations.indexWhere((t) => t.value1 == taskId);
        if (idx > 0) {
          final predId = job.operations[idx - 1].value1;
          return completed.contains(predId);
        }
        return true;
      } else {
        for (final dep in job.dependencies) {
          if (dep.successor_id == taskId) {
            if (!completed.contains(dep.predecessor_id)) return false;
          }
        }
        return true;
      }
    }

    DateTime _getJobReadyTime(OpenShopInput job, int taskId, Map<int, DateTime> compTimes) {
      if (job.dependencies.isEmpty) {
        final idx = job.operations.indexWhere((t) => t.value1 == taskId);
        if (idx > 0) {
          final predId = job.operations[idx - 1].value1;
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

    int _iter = 0;
    const int _maxIter = 1000000;

    // Mientras haya operaciones sin completar
    while (completedOperations.entries.any((entry) {
      final job = inputJobs.firstWhere((j) => j.jobId == entry.key);
      return entry.value.length < job.operations.length;
    })) {
      _iter++;
      if (_iter % 10000 == 0) {
        print('OpenShop._schedule: iter=$_iter');
      }
      if (_iter > _maxIter) {
        print('OpenShop._schedule: reached max iterations ($_maxIter), aborting loop');
        break;
      }
      List<
          ({
            OpenShopInput job,
            int taskId,
            int machineId,
            Duration duration,
            DateTime earliestStart
          })> candidates = [];

      // Recopilar todas las operaciones candidatas (no completadas)
      for (var job in inputJobs) {
        final completed = completedOperations[job.jobId]!;
        final compTimes = taskCompletionTimes[job.jobId]!;

        for (var operation in job.operations) {
          final taskId = operation.value1;

          // Si ya se completó esta operación, skip
          if (completed.contains(taskId)) continue;

          if (!_isTaskReady(job, taskId, completed)) continue;

          final jobReadyTime = _getJobReadyTime(job, taskId, compTimes);

          // Verificar cada máquina posible para esta operación
          for (var entry in operation.value2.entries) {
            final machineId = entry.key;
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;
            final jobAvail = jobReadyTime;

            final earliestStart = machineAvailable.isAfter(jobAvail)
                ? machineAvailable
                : jobAvail;
            final policy = _policyForJob(job.dbJobId);
            final adjustedStart = _calendar.adjustForWorkingSchedule(
              earliestStart,
              allowWorkHoursInterrupt: policy.allowWorkHoursInterrupt,
            );

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


      if (candidates.isEmpty) break;

      // Ordenar candidatos según earliestStart primero (Non-delay), luego por la regla de despacho
      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      // Seleccionar el mejor candidato
      final selected = candidates.first;
      final start = selected.earliestStart;

      // Calcular setup time
      final int? previousSequence = _machineLastSequence.putIfAbsent(selected.machineId, () => null);
      final int? previousJobId = _machineLastJob.putIfAbsent(selected.machineId, () => null);
      
      Duration setupDuration = Duration.zero;
      if (previousJobId != null && stateSetupMatrix != null && jobStates != null && previousJobId > 0) {
        final machineStates = stateSetupMatrix![selected.machineId];
        if (machineStates != null) {
          final previousState = jobStates![previousJobId]?[selected.machineId];
          final currentState = jobStates![selected.job.dbJobId]?[selected.machineId];
          if (previousState != null && currentState != null) {
            final setupMinutes = machineStates[previousState]?[currentState];
            if (setupMinutes != null) {
              setupDuration = Duration(minutes: setupMinutes);
            }
          }
        }
      } else {
        setupDuration = _getSetupDuration(selected.machineId, selected.job.sequenceId, previousSequence);
      }

      final policy = _policyForJob(selected.job.dbJobId);
      final taskStart = _calendar.adjustEndTimeWithInactivities(
        selected.machineId,
        start,
        start.add(setupDuration),
        policy,
      );
      final adjustedEnd = _calendar.adjustEndTimeWithInactivities(
        selected.machineId,
        taskStart,
        taskStart.add(selected.duration),
        policy,
      );

      // Aplicar descanso por continueCapacity
      DateTime finalEnd = adjustedEnd;
      final capacity = machineContinueCapacity[selected.machineId] ?? 0;
      final restTime = machineRestTime[selected.machineId];

      if (capacity > 0 && restTime != null) {
        machineProcessedCount[selected.machineId] =
            (machineProcessedCount[selected.machineId] ?? 0) + 1;

        if (machineProcessedCount[selected.machineId]! >= capacity) {
          if (policy.allowRestInterrupt) {
            finalEnd = adjustedEnd.add(restTime);
          }
          machineProcessedCount[selected.machineId] = 0;
        }
      }

      // Programar la operación con taskStart (así queda el gap de alistamiento)
      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(taskStart, adjustedEnd));

      // Actualizar disponibilidades
      machinesAvailability[selected.machineId] = finalEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      completedOperations[selected.job.jobId]!.add(selected.taskId);
      taskCompletionTimes[selected.job.jobId]![selected.taskId] = adjustedEnd;
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
      _machineLastJob[selected.machineId] = selected.job.dbJobId;
    }

    // Generar outputs
    for (var job in inputJobs) {
      final scheduling = jobSchedulings[job.jobId]!;
      if (scheduling.isEmpty) continue;

      DateTime? startDate;
      DateTime? endDate;

      for (var entry in scheduling.values) {
        final range = entry.value2;
        if (startDate == null || range.start.isBefore(startDate)) {
          startDate = range.start;
        }
        if (endDate == null || range.end.isAfter(endDate)) {
          endDate = range.end;
        }
      }

      output.add(OpenShopOutput(
        job.jobId,
        job.dbJobId,
        job.dueDate,
        startDate ?? job.availableDate,
        endDate ?? job.availableDate,
        scheduling,
      ));
    }
  }

  int calcularCmax(List<OpenShopOutput> outputs) {
    if (outputs.isEmpty) return 0;

    DateTime maxEndTime = outputs.first.endTime;
    for (var output in outputs) {
      if (output.endTime.isAfter(maxEndTime)) {
        maxEndTime = output.endTime;
      }
    }

    return maxEndTime.difference(startDate).inMinutes;
  }
}

List<Map<String, dynamic>> openShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(hour: payload['workingStartHour'] as int, minute: payload['workingStartMinute'] as int),
    TimeOfDay(hour: payload['workingEndHour'] as int, minute: payload['workingEndMinute'] as int),
  );

  final List<OpenShopInput> inputJobs = (payload['inputJobs'] as List<dynamic>)
      .map((jobData) {
        final jd = Map<String, dynamic>.from(jobData as Map);
        final operations = (jd['operations'] as List<dynamic>).map((opData) {
          final od = Map<String, dynamic>.from(opData as Map);
          final machineDurations = (od['machineDurations'] as Map<dynamic, dynamic>).map(
            (key, value) => MapEntry(key as int, Duration(milliseconds: value as int)),
          );
          return Tuple2(od['taskId'] as int, machineDurations);
        }).toList();

        final dependencies = (jd['dependencies'] as List<dynamic>)
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

        return OpenShopInput(
          jd['jobId'] as int,
          jd['dbJobId'] as int,
          jd['sequenceId'] as int,
          DateTime.fromMillisecondsSinceEpoch(jd['dueDate'] as int),
          jd['priority'] as int,
          DateTime.fromMillisecondsSinceEpoch(jd['availableDate'] as int),
          operations,
          dependencies: dependencies,
        );
      })
      .toList();

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

  final changeoverMatrix = <int, Map<int?, Map<int, Duration>>>{};
  for (final machineEntry in (payload['changeoverMatrix'] as Map<dynamic, dynamic>).entries) {
    final machineId = machineEntry.key as int;
    final map = Map<dynamic, dynamic>.from(machineEntry.value as Map);
    final inner = <int?, Map<int, Duration>>{};
    for (final prevEntry in map.entries) {
      final prevKey = prevEntry.key;
      final prevId = prevKey == 'null' ? null : prevKey as int;
      inner[prevId] = (Map<dynamic, dynamic>.from(prevEntry.value as Map)).map(
        (key, value) => MapEntry(key as int, Duration(minutes: value as int)),
      );
    }
    changeoverMatrix[machineId] = inner;
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

  final jobInterruptionPolicies = parseJobInterruptionPolicies(
    payload['jobInterruptionPolicies'],
  );

  final output = OpenShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    changeoverMatrix: changeoverMatrix,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    jobInterruptionPolicies: jobInterruptionPolicies,
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
    };
  }).toList();
}
