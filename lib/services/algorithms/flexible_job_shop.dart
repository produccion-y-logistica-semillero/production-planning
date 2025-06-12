import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';


class FlexibleJobInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  FlexibleJobInput(this.jobId, this.dueDate, this.priority, this.availableDate, this.taskSequence);
}

class FlexibleJobOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;

  FlexibleJobOutput(this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling);
}

class FlexibleJobShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleJobInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  List<FlexibleJobOutput> output = [];

  FlexibleJobShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule,
  ) {
    switch (rule) {
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
    }
  }

  late Map<int, int> jobOperationIndex;

  void scheduleFlexibleJobShopFIFO() {
    _schedule((a, b) => a.job.jobId.compareTo(b.job.jobId)); // FIFO basado en el orden de llegada
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
      final wsptA = a.job.priority / a.duration.inMinutes;
      final wsptB = b.job.priority / b.duration.inMinutes;
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
      final avgDuration = task.value2.values
          .map((d) => d.inMinutes)
          .reduce((a, b) => a + b) ~/ task.value2.length;
      totalMinutes += avgDuration;
    }

    return totalMinutes;
  }

  void scheduleFlexibleJobShopMS() {
    int accumulatedProcessingTime = 0;  // Acumulamos el tiempo aquí

    _schedule((a, b) {
      final accumulatedProcessingTimeA = _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB = _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final slackA = _calculateSlack(a.job, a.duration, accumulatedProcessingTimeA);
      final slackB = _calculateSlack(b.job, b.duration, accumulatedProcessingTimeB);

      return slackA.compareTo(slackB); 
    });
  }
  
  int _accumulatedProcessingTimeForJob(FlexibleJobInput job, int currentAccumulatedTime) {
    int totalProcessingTime = currentAccumulatedTime; // Empezamos desde el tiempo acumulado

    final opIndex = jobOperationIndex[job.jobId]!; 

    for (int i = 0; i < opIndex; i++) {
      final task = job.taskSequence[i];
      final avgDuration = task.value2.values
          .map((d) => d.inMinutes)
          .reduce((a, b) => a + b) ~/ task.value2.length;
      totalProcessingTime += avgDuration;
    }

    return totalProcessingTime;
  }

  double _calculateSlack(FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final slack = dj.difference(DateTime.now()).inMinutes - pj.inMinutes - accumulatedProcessingTime;
    return slack < 0 ? 0 : slack.toDouble();
  }

  void scheduleFlexibleJobShopCR() {
    int accumulatedProcessingTime = 0;  // Inicializamos el acumulado en cada llamada

    _schedule((a, b) {
      final accumulatedProcessingTimeA = _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB = _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final crA = _calculateCR(a.job, a.duration, accumulatedProcessingTimeA);
      final crB = _calculateCR(b.job, b.duration, accumulatedProcessingTimeB);

      return crA.compareTo(crB);
    });
  }
  
  double _calculateCR(FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final cr = (dj.difference(DateTime.now()).inMinutes - accumulatedProcessingTime) / pj.inMinutes;
    return cr < 0 ? 0 : cr;
  }
  
  void scheduleFlexibleJobShopATCS() {
    int accumulatedProcessingTime = 0;  // Inicializamos el acumulado en cada llamada

    _schedule((a, b) {
      final accumulatedProcessingTimeA = _accumulatedProcessingTimeForJob(a.job, accumulatedProcessingTime);
      final accumulatedProcessingTimeB = _accumulatedProcessingTimeForJob(b.job, accumulatedProcessingTime);

      final atcsA = _calculateATCS(a.job, a.duration, accumulatedProcessingTimeA);
      final atcsB = _calculateATCS(b.job, b.duration, accumulatedProcessingTimeB);

      return atcsB.compareTo(atcsA); // Invertido para asignar el mayor ATCS primero
    });
  }

  double _calculateATCS(FlexibleJobInput job, Duration duration, int accumulatedProcessingTime) {
    final dj = job.dueDate;
    final pj = duration;
    final wj = job.priority.toDouble();  // Asumimos que el "peso" es el valor de la prioridad del trabajo
    final pPromedio = _averageProcessingTime();  // Promedio de tiempos de procesamiento

    final maxSlack = max(dj.difference(DateTime.now()).inMinutes - pj.inMinutes - accumulatedProcessingTime, 0);
    final k = 1.0;  // Este parámetro k puede ser ajustado
    final exponent = -(maxSlack / (k * pPromedio));
    final atcs = (wj / pj.inMinutes) * exp(exponent);

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

  void _schedule(int Function(dynamic, dynamic) comparator) {
    jobOperationIndex = {
      for (var job in inputJobs) job.jobId: 0,
    };

    Map<int, Map<int, Tuple2<int, Range>>> jobSchedulings = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, DateTime> jobAvailability = {
      for (var job in inputJobs) job.jobId: job.availableDate,
    };

    while (jobOperationIndex.values.any((i) {
      final job = inputJobs.firstWhere((j) => j.jobId == jobOperationIndex.keys.firstWhere((id) => j.jobId == id));
      return i < job.taskSequence.length;
    })) {
      List<({
        FlexibleJobInput job,
        int taskId,
        int machineId,
        Duration duration,
        DateTime earliestStart
      })> candidates = [];

      for (var job in inputJobs) {
        final opIndex = jobOperationIndex[job.jobId]!;

        if (opIndex >= job.taskSequence.length) continue;

        final task = job.taskSequence[opIndex];
        final taskId = task.value1;

        for (var entry in task.value2.entries) {
          final machineId = entry.key;
          final duration = entry.value;
          final machineAvailable = machinesAvailability[machineId] ?? startDate;
          final available = jobAvailability[job.jobId]!;

          final earliestStart = machineAvailable.isAfter(available) ? machineAvailable : available;
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

      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      final selected = candidates.first;
      final start = selected.earliestStart;
      final end = start.add(selected.duration);
      final adjustedEnd = _adjustEndTimeForWorkingSchedule(start, end);

      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(start, adjustedEnd));

      machinesAvailability[selected.machineId] = adjustedEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      jobOperationIndex[selected.job.jobId] =
        (jobOperationIndex[selected.job.jobId] ?? 0) + 1;
    }

    for (var job in inputJobs) {
      final sched = jobSchedulings[job.jobId]!;
      final start = sched.values.map((t) => t.value2.start).reduce((a, b) => a.isBefore(b) ? a : b);
      final end = sched.values.map((t) => t.value2.end).reduce((a, b) => a.isAfter(b) ? a : b);

      output.add(FlexibleJobOutput(
        job.jobId,
        job.dueDate,
        start,
        end,
        sched,
      ));
    }
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
    final startTimes = output.map((job) => job.startDate).toList();
    final endTimes = output.map((job) => job.endTime).toList();

    final earliestStart = startTimes.reduce((a, b) => a.isBefore(b) ? a : b);
    final latestEnd = endTimes.reduce((a, b) => a.isAfter(b) ? a : b);

    final duration = latestEnd.difference(earliestStart);
    return duration.inHours;
  }
}

// ---------- MAIN ----------
void main() {
  final start = DateTime(2025, 1, 1, 8);
  final workingHours = Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0));

  final jobs = [
    FlexibleJobInput(
      1,
      start.add(Duration(days: 1)),
      1,
      start,
      [
        Tuple2(1, {1: Duration(hours: 3), 2: Duration(hours: 3)}),
        Tuple2(2, {3: Duration(hours: 3), 4: Duration(hours: 3)}),
        Tuple2(3, {5: Duration(hours: 2), 6: Duration(hours: 2)}),
      ],
    ),
    FlexibleJobInput(
      2,
      start.add(Duration(days: 1)),
      1,
      start,
      [
        Tuple2(1, {1: Duration(hours: 1), 2: Duration(hours: 1)}),
        Tuple2(2, {5: Duration(hours: 5), 6: Duration(hours: 5)}),
        Tuple2(3, {3: Duration(hours: 3), 4: Duration(hours: 3)}),
      ],
    ),
    FlexibleJobInput(
      3,
      start.add(Duration(days: 1)),
      1,
      start,
      [
        Tuple2(1, {3: Duration(hours: 3), 4: Duration(hours: 3)}),
        Tuple2(2, {1: Duration(hours: 2), 2: Duration(hours: 2)}),
        Tuple2(3, {5: Duration(hours: 3), 6: Duration(hours: 3)}),
      ],
    ),
  ];

  final machinesAvailability = {
    1: start,
    2: start,
    3: start,
    4: start,
    5: start,
    6: start,
  };

  final scheduler = FlexibleJobShop(start, workingHours, jobs, machinesAvailability, "LPT");
  // final scheduler = FlexibleJobShop(start, workingHours, jobs, machinesAvailability, "SPT");
  // final scheduler = FlexibleJobShop(start, workingHours, jobs, machinesAvailability, "EDD");
  // final scheduler = FlexibleJobShop(start, workingHours, jobs, machinesAvailability, "WSPT");


  for (var output in scheduler.output) {
    print('Job ${output.jobId}');
    output.scheduling.forEach((taskId, entry) {
      print(
        '  Task $taskId -> Machine ${entry.value1}, '
        'Start: ${entry.value2.start}, End: ${entry.value2.end}',
      );
    });
    print('  Job Start: ${output.startDate}, End: ${output.endTime}\n');
  }

  final cmax = scheduler.calcularCmax(scheduler.output);
  print('Cmax: $cmax horas');
}
