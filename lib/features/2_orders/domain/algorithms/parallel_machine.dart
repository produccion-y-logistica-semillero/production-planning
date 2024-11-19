import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<Tuple5<int, DateTime, int, DateTime, List<Duration>>> inputJobs = [];
  //  job id   | due date | priority | Available date | Times (durations for each machine)
  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = [];
  //  machine Id | Scheduling (list of start and end times)

  List<Tuple5<int, int, DateTime, DateTime, Duration>> output = [];
  // job id | machine id | start date | end date | delay

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule,
  ) {
    switch (rule) {
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "EDD":
        eddRule();
        break;
      case "FCFS":
        fcfsRule();
        break;
      case "MINSLACK":
        minimumSlackRule();
        break;
      case "CR":
        criticalRatioRule();
        break;
    }

    printOutput();
    printMachineSchedule();
  }

  // Reglas de asignación de trabajos
  void sptRule() {
    inputJobs.sort((a, b) {
      double avgTimeA = a.value5.reduce((v1, v2) => v1 + v2).inMinutes / a.value5.length;
      double avgTimeB = b.value5.reduce((v1, v2) => v1 + v2).inMinutes / b.value5.length;
      return avgTimeA.compareTo(avgTimeB);
    });
    assignJobsToMachines();
  }

  void lptRule() {
    inputJobs.sort((a, b) {
      double avgTimeA = a.value5.reduce((v1, v2) => v1 + v2).inMinutes / a.value5.length;
      double avgTimeB = b.value5.reduce((v1, v2) => v1 + v2).inMinutes / b.value5.length;
      return avgTimeB.compareTo(avgTimeA);
    });
    assignJobsToMachines();
  }

  void eddRule() {
    inputJobs.sort((a, b) => a.value2.compareTo(b.value2));
    assignJobsToMachines();
  }

  void fcfsRule() {
    inputJobs.sort((a, b) => a.value4.compareTo(b.value4));
    assignJobsToMachines();
  }

  void minimumSlackRule() {
    inputJobs.sort((a, b) {
      Duration slackA = a.value2.difference(a.value4) - a.value5.reduce((v1, v2) => v1 + v2);
      Duration slackB = b.value2.difference(b.value4) - b.value5.reduce((v1, v2) => v1 + v2);
      return slackA.compareTo(slackB);
    });
    assignJobsToMachines();
  }

  void criticalRatioRule() {
    inputJobs.sort((a, b) {
      double criticalRatioA = calculateCriticalRatio(a);
      double criticalRatioB = calculateCriticalRatio(b);
      return criticalRatioA.compareTo(criticalRatioB);
    });
    assignJobsToMachines();
  }

  // Cálculo del Critical Ratio para un trabajo
  double calculateCriticalRatio(Tuple5<int, DateTime, int, DateTime, List<Duration>> job) {
    DateTime dueDate = job.value2;
    DateTime availableDate = job.value4;
    Duration totalProcessingTime = job.value5.reduce((v1, v2) => v1 + v2);
    Duration timeRemaining = dueDate.difference(availableDate);
    double criticalRatio = timeRemaining.inHours / totalProcessingTime.inHours;

    // Si el ratio crítico es negativo o 0, el trabajo está muy atrasado
    return criticalRatio <= 0 ? double.negativeInfinity : criticalRatio;
  }

  // Asignar los trabajos a las máquinas disponibles
  void assignJobsToMachines() {
    List<DateTime> machineAvailable = List.generate(machines.length, (_) => startDate);

    for (var job in inputJobs) {
      int jobId = job.value1;
      DateTime dueDate = job.value2;
      DateTime availableDate = job.value4;
      List<Duration> processingTimes = job.value5;

      for (int i = 0; i < processingTimes.length; i++) {
        Duration processingTime = processingTimes[i];

        int bestMachineIndex = 0;
        DateTime earliestAvailable = machineAvailable[0];

        for (int j = 1; j < machineAvailable.length; j++) {
          if (machineAvailable[j].isBefore(earliestAvailable)) {
            bestMachineIndex = j;
            earliestAvailable = machineAvailable[j];
          }
        }

        DateTime machineStartTime = availableDate.isAfter(earliestAvailable)
            ? availableDate
            : earliestAvailable;

        machineStartTime = adjustForWorkingSchedule(machineStartTime);

        DateTime endTime = machineStartTime.add(processingTime);
        endTime = adjustEndTimeForWorkingSchedule(machineStartTime, endTime);

        Duration delay = endTime.isAfter(dueDate) ? endTime.difference(dueDate) : Duration.zero;

        machineAvailable[bestMachineIndex] = endTime;

        machines[bestMachineIndex].value2.add(Tuple2(machineStartTime, endTime));

        output.add(Tuple5(jobId, machines[bestMachineIndex].value1, machineStartTime, endTime, delay));

        break; // Asignar un trabajo a una máquina
      }
    }
  }

  // Ajustar el tiempo de inicio para cumplir con el horario laboral
  DateTime adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    } else if (start.hour > workingEnd.hour || (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  // Ajustar el tiempo de finalización según el horario laboral
  DateTime adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute).add(remainingTime);
    }

    return end;
  }

  // Imprimir el resultado de las asignaciones de trabajos
  void printOutput() {
    print("Resultado de la asignación de trabajos:");
    for (var result in output) {
      print(
          'Job ${result.value1} | Machine ${result.value2} | Start: ${result.value3} | End: ${result.value4} | Delay: ${result.value5}');
    }
  }

  // Imprimir el horario de las máquinas
  void printMachineSchedule() {
    print("Horarios de las máquinas:");
    for (var machine in machines) {
      print('Machine ${machine.value1} Schedule:');
      for (var schedule in machine.value2) {
        print('  Start: ${schedule.value1}, End: ${schedule.value2}');
      }
    }
  }
}
