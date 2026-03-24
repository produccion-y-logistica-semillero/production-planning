import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class OpenShopInput {
  final int jobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // Lista de operaciones sin orden específico: <taskId, Map<machineId, Duration>>
  final List<Tuple2<int, Map<int, Duration>>> operations;

  OpenShopInput(
    this.jobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.operations,
  );
}

class OpenShopOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  // Scheduling: taskId -> (machineId, Range)
  final Map<int, Tuple2<int, Range>> scheduling;

  OpenShopOutput(
    this.jobId,
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
  final Map<int, int?> _machineLastSequence = {};
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
  }) {
    // Inicializar contador de procesamiento por máquina
    for (final machineId in machinesAvailability.keys) {
      machineProcessedCount[machineId] = 0;
    }
    _initializeMachineLastSequence();
    switch (rule) {
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
      case "CR":
        scheduleOpenShopCR();
        break;
      case "ATCS":
        scheduleOpenShopATCS();
        break;
      default:
        scheduleOpenShopSPT();
    }
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
    }
    for (final machineId in changeoverMatrix.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
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

  DateTime _adjustForWorkingSchedule(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final currentMinutes = hour * 60 + minute;
    final startMinutes =
        workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;
    final endMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (currentMinutes < startMinutes) {
      return DateTime(
        dt.year,
        dt.month,
        dt.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    } else if (currentMinutes >= endMinutes) {
      final nextDay = dt.add(const Duration(days: 1));
      return DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    }
    return dt;
  }

  // Obtener las inactividades de una máquina para un día específico
  List<Range> _getInactivitiesForDay(int machineId, DateTime day) {
    final inactivities = machineInactivities[machineId] ?? [];
    final weekday = day.weekday; // 1=Monday, 7=Sunday
    final List<Range> dayInactivities = [];

    for (final inactivity in inactivities) {
      // Convertir Weekday enum a int (Weekday.monday.index = 0, pero DateTime usa 1=Monday)
      final inactivityWeekdays =
          inactivity.weekdays.map((wd) => wd.index + 1).toSet();

      if (inactivityWeekdays.contains(weekday)) {
        final startHour = inactivity.startTime.inHours;
        final startMinute = inactivity.startTime.inMinutes % 60;

        final inactivityStart = DateTime(
          day.year,
          day.month,
          day.day,
          startHour,
          startMinute,
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

      // Obtener inactividades del día actual
      final dayInactivities = _getInactivitiesForDay(machineId, current);

      final dayEnd = DateTime(
        current.year,
        current.month,
        current.day,
        workingSchedule.value2.hour,
        workingSchedule.value2.minute,
      );

      // Verificar si hay una inactividad que intersecta con el tiempo disponible
      DateTime nextAvailable = current;
      for (final inactivity in dayInactivities) {
        if (nextAvailable.isBefore(inactivity.end) &&
            inactivity.start.isBefore(dayEnd)) {
          // Hay una inactividad en el camino
          if (nextAvailable.isBefore(inactivity.start)) {
            // Podemos trabajar hasta el inicio de la inactividad
            final availableBeforeInactivity =
                inactivity.start.difference(nextAvailable);

            if (remaining <= availableBeforeInactivity) {
              // La tarea termina antes de la inactividad
              return nextAvailable.add(remaining);
            } else {
              // La tarea se interrumpe por la inactividad
              remaining -= availableBeforeInactivity;
              nextAvailable = inactivity.end;
            }
          } else {
            // Estamos dentro o después de la inactividad
            if (nextAvailable.isBefore(inactivity.end)) {
              nextAvailable = inactivity.end;
            }
          }
        }
      }

      // Calcular tiempo disponible restante en el día (después de inactividades)
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
      final remainingA = _remainingWork(a.job, a.taskId);
      final remainingB = _remainingWork(b.job, b.taskId);
      return remainingB.compareTo(remainingA);
    });
  }

  void scheduleOpenShopCR() {
    _schedule((a, b) {
      final crA = _calculateCR(a.job, a.duration);
      final crB = _calculateCR(b.job, b.duration);
      return crA.compareTo(crB);
    });
  }

  void scheduleOpenShopATCS() {
    _schedule((a, b) {
      final atcsA = _calculateATCS(a.job, a.duration);
      final atcsB = _calculateATCS(b.job, b.duration);
      return atcsB.compareTo(atcsA);
    });
  }

  int _remainingWork(OpenShopInput job, int currentTaskId) {
    // Calcula el trabajo restante para un job (excluyendo la tarea actual)
    int totalMinutes = 0;
    for (var operation in job.operations) {
      if (operation.value1 != currentTaskId) {
        final avgDuration = operation.value2.values
                .map((d) => d.inMinutes)
                .reduce((a, b) => a + b) ~/
            operation.value2.length;
        totalMinutes += avgDuration;
      }
    }
    return totalMinutes;
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

    // Mientras haya operaciones sin completar
    while (completedOperations.values.any((set) =>
        set.length <
        inputJobs
            .firstWhere((j) => j.jobId == completedOperations.keys.first)
            .operations
            .length)) {
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

        for (var operation in job.operations) {
          final taskId = operation.value1;

          // Si ya se completó esta operación, skip
          if (completed.contains(taskId)) continue;

          // Verificar cada máquina posible para esta operación
          for (var entry in operation.value2.entries) {
            final machineId = entry.key;
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;
            final jobAvail = jobAvailability[job.jobId]!;

            final earliestStart = machineAvailable.isAfter(jobAvail)
                ? machineAvailable
                : jobAvail;
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

      if (candidates.isEmpty) break;

      // Ordenar candidatos según la regla de despacho
      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      // Seleccionar el mejor candidato
      final selected = candidates.first;
      final start = selected.earliestStart;

      // Calcular setup time
      final int? previousSequence =
          _machineLastSequence.putIfAbsent(selected.machineId, () => null);
      final Duration setupDuration = _getSetupDuration(
          selected.machineId, selected.job.sequenceId, previousSequence);
      final Duration totalDuration = selected.duration + setupDuration;

      final end = start.add(totalDuration);
      final adjustedEnd =
          _adjustEndTimeWithInactivities(selected.machineId, start, end);

      // Aplicar descanso por continueCapacity
      DateTime finalEnd = adjustedEnd;
      final capacity = machineContinueCapacity[selected.machineId] ?? 0;
      final restTime = machineRestTime[selected.machineId];

      if (capacity > 0 && restTime != null) {
        machineProcessedCount[selected.machineId] =
            (machineProcessedCount[selected.machineId] ?? 0) + 1;

        if (machineProcessedCount[selected.machineId]! >= capacity) {
          // Aplicar descanso
          finalEnd = adjustedEnd.add(restTime);
          machineProcessedCount[selected.machineId] = 0;
        }
      }

      // Programar la operación
      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(start, adjustedEnd));

      // Actualizar disponibilidades
      machinesAvailability[selected.machineId] = finalEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      completedOperations[selected.job.jobId]!.add(selected.taskId);
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
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
