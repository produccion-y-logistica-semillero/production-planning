import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class JobShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // Horas de trabajo

  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  // job id | due date | priority | available date

  Map<int, List<Tuple2<int, Duration>>> jobRoutes = {};
  // job id -> List of <machine id, duration>
  // Cada trabajo tiene su propia ruta y duración en las máquinas

  Map<int, DateTime> machineAvailability = {};
  // Registro de disponibilidad de cada máquina por machineId

  List<Tuple3<int, int, Tuple2<DateTime, DateTime>>> output = [];
  // job id | machine id | <start, end time>

  JobShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.jobRoutes,
    String rule,
  ) {
    // Inicializar la disponibilidad de las máquinas
    for (final machineId in _getMachineIds()) {
      machineAvailability[machineId] = startDate;
    }

    _applyRule(rule);
    printOutput();
  }

  // Obtiene el conjunto de máquinas en uso
  Set<int> _getMachineIds() {
    return jobRoutes.values
        .expand((routes) => routes.map((route) => route.value1))
        .toSet();
  }

  void _applyRule(String rule) {
    switch (rule.toUpperCase()) {
      case 'EDD':
        scheduleWithRule((a, b) => a.jobDue.compareTo(b.jobDue));
        break;
      case 'SPT':
        scheduleWithRule((a, b) => a.duration.compareTo(b.duration));
        break;
      case 'LPT':
        scheduleWithRule((a, b) => b.duration.compareTo(a.duration));
        break;
      case 'FIFO':
        scheduleWithRule((a, b) => a.jobAvailable.compareTo(b.jobAvailable));
        break;
      case 'WSPT':
        scheduleWithRule((a, b) => _wsptValue(b).compareTo(_wsptValue(a)));
        break;
      case 'CR':
        scheduleWithRule((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
        break;
      case 'ATCS':
        scheduleWithRule((a, b) => _atcsScore(b).compareTo(_atcsScore(a)));
        break;
      case 'GENETICS':
        scheduleWithRule((a, b) {
          final scoreA = _geneticsScore(a);
          final scoreB = _geneticsScore(b);
          if (scoreA != scoreB) return scoreB.compareTo(scoreA);
          return _criticalRatio(a).compareTo(_criticalRatio(b));
        });
        break;
      default:
        print('JobShop: regla desconocida "$rule", usando FIFO como fallback');
        scheduleWithRule((a, b) => a.jobAvailable.compareTo(b.jobAvailable));
    }
  }

  // Regla EDD: Ordena trabajos por fecha de entrega más cercana
  void eddRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      return jobA.value2.compareTo(jobB.value2);
    });
  }

  // Regla SPT: Ordena trabajos por tiempo total de procesamiento más corto
  void sptRule() {
    scheduleWithRule((a, b) => a.duration.compareTo(b.duration));
  }

  // Regla LPT: Ordena trabajos por tiempo total de procesamiento más largo
  void lptRule() {
    scheduleWithRule((a, b) => b.duration.compareTo(a.duration));
  }

  // Regla FIFO: Ordena trabajos por fecha de disponibilidad
  void fifoRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      final result = jobA.value4.compareTo(jobB.value4);
      if (result != 0) return result;
      return jobA.value1.compareTo(jobB.value1);
    });
  }

  // Regla WSPT: Ordena trabajos por tiempo / prioridad
  void wsptRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      final wspta = _wsptValue(jobA);
      final wsptb = _wsptValue(jobB);
      if (wspta != wsptb) return wspta.compareTo(wsptb);
      return jobA.value4.compareTo(jobB.value4);
    });
  }

  // Regla CR: Critical Ratio
  void crRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      final result = _criticalRatio(jobA).compareTo(_criticalRatio(jobB));
      if (result != 0) return result;
      return jobA.value2.compareTo(jobB.value2);
    });
  }

  // Regla ATCS: Terminally acute scheduling heuristics
  void atcsRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      final result = _atcsScore(jobB).compareTo(_atcsScore(jobA));
      if (result != 0) return result;
      return jobA.value4.compareTo(jobB.value4);
    });
  }

  // Regla GENETICS: heurística aproximada basada en múltiples criterios
  void geneticsRule() {
    scheduleWithRule((a, b) {
      final jobA = inputJobs.firstWhere((j) => j.value1 == a.jobId);
      final jobB = inputJobs.firstWhere((j) => j.value1 == b.jobId);
      final scoreA = _geneticsScore(jobA);
      final scoreB = _geneticsScore(jobB);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return _criticalRatio(jobA).compareTo(_criticalRatio(jobB));
    });
  }

  double _wsptValue(Tuple4<int, DateTime, int, DateTime> job) {
    final time = max(_calculateTotalProcessingTime(job.value1), 1);
    final priority = max(job.value3, 1);
    return time / (1.0 / priority);
  }

  double _criticalRatio(Tuple4<int, DateTime, int, DateTime> job) {
    final remainingMinutes = _calculateTotalProcessingTime(job.value1);
    final slack = max(job.value2.difference(job.value4).inMinutes, 0);
    return slack / max(remainingMinutes, 1);
  }

  double _atcsScore(Tuple4<int, DateTime, int, DateTime> job) {
    final processingMinutes = max(_calculateTotalProcessingTime(job.value1), 1);
    final slack = job.value2.difference(job.value4).inMinutes - processingMinutes;
    final urgency = exp(-max(slack, 0) / (20 * processingMinutes));
    final priorityWeight = 1 / max(job.value3, 1);
    return priorityWeight / processingMinutes * urgency;
  }

  double _geneticsScore(Tuple4<int, DateTime, int, DateTime> job) {
    final ratio = _criticalRatio(job);
    final wspt = _wsptValue(job);
    return 1 / max(ratio, 0.0001) + 1 / max(wspt, 0.0001);
  }

  // Calcula el tiempo total de procesamiento de un trabajo
  int _calculateTotalProcessingTime(int jobId) {
    final routes = jobRoutes[jobId]!;
    if (routes.isEmpty) return 0;
    return routes.map((route) => route.value2.inMinutes).fold<int>(0, (a, b) => a + b);
  }
  
  // Scheduler Non-delay: genera candidatos por operación y asigna según la regla
  late Map<int, int> jobOperationIndex;

  void scheduleWithRule(int Function(dynamic a, dynamic b) comparator) {
    print('JobShop: scheduleWithRule start for ${inputJobs.length} jobs');
    jobOperationIndex = {for (var job in inputJobs) job.value1: 0};

    Map<int, Set<int>> completed = {for (var job in inputJobs) job.value1: <int>{}};
    Map<int, DateTime> jobAvailable = {for (var job in inputJobs) job.value1: job.value4};
    Map<int, List<Tuple3<int, int, Tuple2<DateTime, DateTime>>>> sched = {for (var job in inputJobs) job.value1: []};

    // Total operations to schedule
    final totalOps = inputJobs.fold<int>(0, (acc, j) => acc + jobRoutes[j.value1]!.length);

    int _iter = 0;
    const int _maxIter = 1000000;

    while (completed.values.fold<int>(0, (s, set) => s + set.length) < totalOps) {
      _iter++;
      if (_iter % 10000 == 0) print('JobShop.scheduleWithRule: iter=$_iter');
      if (_iter > _maxIter) {
        print('JobShop.scheduleWithRule: reached max iterations ($_maxIter), aborting');
        break;
      }
      List<({int jobId, int opIndex, int machineId, Duration duration, DateTime earliestStart})> candidates = [];

      for (var job in inputJobs) {
        final jid = job.value1;
        final idx = jobOperationIndex[jid]!;
        if (idx >= jobRoutes[jid]!.length) continue;

        final route = jobRoutes[jid]![idx];
        final machineId = route.value1;
        final duration = route.value2;

        final machineFree = machineAvailability[machineId] ?? startDate;
        final avail = jobAvailable[jid]!;
        final earliest = machineFree.isAfter(avail) ? machineFree : avail;
        final adjusted = adjustForWorkingSchedule(earliest);

        candidates.add((jobId: jid, opIndex: idx, machineId: machineId, duration: duration, earliestStart: adjusted));
      }

      if (candidates.isEmpty) {
        print('JobShop.scheduleWithRule: no schedulable candidates remaining, aborting loop');
        break;
      }

      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      final sel = candidates.first;
      final start = sel.earliestStart;
      final end = sel.earliestStart.add(sel.duration);
      final adjEnd = adjustEndTimeForWorkingSchedule(start, end);

      // Save schedule
      sched[sel.jobId]!.add(Tuple3(sel.jobId, sel.machineId, Tuple2(start, adjEnd)));

      // Update availability
      machineAvailability[sel.machineId] = adjEnd;
      jobAvailable[sel.jobId] = adjEnd;
      completed[sel.jobId]!.add(sel.opIndex);
      jobOperationIndex[sel.jobId] = sel.opIndex + 1;
    }

    // Flatten output
    for (var entry in sched.entries) {
      for (var t in entry.value) {
        output.add(t);
      }
    }
  }

  // Ajusta el inicio del trabajo para respetar las horas laborales
  DateTime adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour,
          workingStart.minute);
    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1,
          workingStart.hour, workingStart.minute);
    }
    return start;
  }

  // Ajusta el final del trabajo según el horario laboral
  DateTime adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
        start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1,
              workingSchedule.value1.hour, workingSchedule.value1.minute)
          .add(remainingTime);
    }

    return end;
  }

  // Imprime los resultados del programa
  void printOutput() {
    print("Resultados del Job Shop:");
    for (var result in output) {
      print(
          "Job ${result.value1} on Machine ${result.value2}: Start ${result.value3.value1}, End ${result.value3.value2}");
    }
  }
}
