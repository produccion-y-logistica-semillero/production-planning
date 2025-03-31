import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'dart:math';
// Clase que representa el intervalo de programación de una tarea en una máquina.
class TimeRange {
 final DateTime start;
 final DateTime end;
 TimeRange(this.start, this.end);
}
// Entrada para cada trabajo
class FlexibleFlowInput {
 final int jobId;
 final DateTime dueDate;
 final int priority;
 final DateTime availableDate;
 // Tupla que representa una secuencia de tareas y su asignación de máquinas con duración
 final List<Tuple2<int, Map<int, Duration>>> taskSequence;
 FlexibleFlowInput(this.jobId, this.dueDate, this.priority, this.availableDate, this.taskSequence);
}
// Salida del programa de producción
class FlexibleFlowOutput {
 final int jobId;
 final DateTime dueDate;
 final DateTime startDate;
 final DateTime endTime;
 // Mapeo de tarea -> (Máquina asignada, Rango de programación)
 final Map<int, Tuple2<int, TimeRange>> scheduling;
 FlexibleFlowOutput(this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling);
}
class FlexibleFlowShop {
 final DateTime startDate;
 final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
 List<FlexibleFlowInput> inputJobs = [];
 Map<int, DateTime> machinesAvailability = {};
 List<FlexibleFlowOutput> output = [];
 FlexibleFlowShop(
   this.startDate,
   this.workingSchedule,
   this.inputJobs,
   this.machinesAvailability,
   String rule,
 ) {
   switch (rule) {
     case "JOHNSON_2_MACHINES":
       johnsonRule(2);
       break;
     case "JOHNSON_3_MACHINES":
       johnsonRule(3);
       break;
     case "JOHNSON_CDS":
       johnsonCDS();
       break;
     case "ATCS":
       atcRule();
       break;
      case "WSPT":
        wsptRule();
        break;
      case "WSPTA":
        wsptaRule();
        break;
      case "FIFO":
        fifoRule();
        break;
      case "FIFOA":
        fifoaRule();
        break;
      case "SPT":
        sptRule();
        break;
      case "SPTA":
        sptaRule();
        break;
      case "EDD":
        eddRule();
        break;
      case "EDDA":
        eddaRule();
        break;
      case "CR":
        criticalRatioRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "LPTA":
        lptaRule();
        break;
      case "MS":
        minimumSlackRule();
   }
 }
 void wsptRule() {
    inputJobs.sort((a, b) {
      double scoreA = a.priority / (_totalProcessingTime(a) + 1);
      double scoreB = b.priority / (_totalProcessingTime(b) + 1);
      return scoreB.compareTo(scoreA);
    });
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void wsptaRule() {
    inputJobs.sort((a, b) => (a.priority / _totalProcessingTime(a)).compareTo(b.priority / _totalProcessingTime(b)));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void fifoRule() {
    inputJobs.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void fifoaRule() {
    inputJobs.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void sptRule() {
    inputJobs.sort((a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void sptaRule() {
    inputJobs.sort((a, b) => (_totalProcessingTime(a) / a.priority).compareTo(_totalProcessingTime(b) / b.priority));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void eddRule() {
    inputJobs.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void eddaRule() {
    inputJobs.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void criticalRatioRule() {
    inputJobs.sort((a, b) {
      double crA = (a.dueDate.difference(startDate).inSeconds + 1) / (_totalProcessingTime(a) + 1);
      double crB = (b.dueDate.difference(startDate).inSeconds + 1) / (_totalProcessingTime(b) + 1);
      return crA.compareTo(crB);
    });
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void lptRule() {
    inputJobs.sort((a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void lptaRule() {
    inputJobs.sort((a, b) => (_totalProcessingTime(b) / b.priority).compareTo(_totalProcessingTime(a) / a.priority));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void minimumSlackRule() {
    inputJobs.sort((a, b) => (a.dueDate.difference(startDate).inSeconds - _totalProcessingTime(a)).compareTo(
        b.dueDate.difference(startDate).inSeconds - _totalProcessingTime(b)));
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }
 void johnsonRule(int numMachines) {
   _scheduleJohnsonRule(numMachines);
 }
 void johnsonCDS() {
   int bestPartition = -1;
   int bestMakespan = double.maxFinite.toInt();
   List<FlexibleFlowOutput> bestOutput = [];
   for (int i = 1; i < inputJobs.first.taskSequence.length; i++) {
     _scheduleJohnsonRule(i);
     int makespan = _calculateMakespan();
     if (makespan < bestMakespan) {
       bestMakespan = makespan;
       bestPartition = i;
       bestOutput = List.from(output);
     }
   }
   output = bestOutput;
   print("Optimal CDS partition: $bestPartition, Makespan: $bestMakespan");
 }
 void atcRule() {
   DateTime currentTime = startDate;
   List<FlexibleFlowInput> remainingJobs = List.from(inputJobs);
   output.clear();
   
   while (remainingJobs.isNotEmpty) {
     remainingJobs.sort((a, b) => _calculateATCPriority(b, currentTime).compareTo(_calculateATCPriority(a, currentTime)));
     FlexibleFlowInput selectedJob = remainingJobs.removeAt(0);
     _assignJobToMachines(selectedJob);
     currentTime = output.last.endTime;
   }
 }

 void _assignJobToMachines(FlexibleFlowInput job) {
   DateTime jobStartTime = job.availableDate;
   Map<int, Tuple2<int, TimeRange>> scheduling = {};
   for (var task in job.taskSequence) {
     int taskId = task.value1;
     Tuple2<int, Duration> selectedMachine = _selectMachine(task.value2);
     int machineId = selectedMachine.value1;
     Duration duration = selectedMachine.value2;
     DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
     DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
     DateTime endTime = startTime.add(duration);
     scheduling[taskId] = Tuple2(machineId, TimeRange(startTime, endTime));
     machinesAvailability[machineId] = endTime;
     jobStartTime = endTime;
   }
   output.add(FlexibleFlowOutput(job.jobId, job.dueDate, job.availableDate, jobStartTime, scheduling));
 }
 Tuple2<int, Duration> _selectMachine(Map<int, Duration> availableMachines) {
   final map = availableMachines.entries.reduce((a, b) => a.value < b.value ? a : b);
   return Tuple2(map.key, map.value);
 }
 int _totalProcessingTime(FlexibleFlowInput job) {
   return job.taskSequence.map((t) => t.value2.values.reduce((a, b) => a + b)).reduce((a, b) => a + b).inMinutes;
 }
 double _calculateATCPriority(FlexibleFlowInput job, DateTime currentTime) {
   int totalProcessingTime = _totalProcessingTime(job);
   int numTasks = job.taskSequence.length;
   double avgProcessingTime = totalProcessingTime / numTasks.toDouble();
   int timeRemaining = job.dueDate.difference(currentTime).inMinutes;
   double weight = job.priority.toDouble();
   double k = 3.0; // Parámetro de ajuste
   
   return (weight / totalProcessingTime) *
       (exp(-max(timeRemaining - totalProcessingTime, 0) / (k * avgProcessingTime)));
 }
 int _calculateMakespan() {
   return output.map((o) => o.endTime.difference(startDate).inMinutes).reduce((a, b) => a > b ? a : b);
 }
}

// ignore: camel_case_types
class _scheduleJohnsonRule {
  _scheduleJohnsonRule(int numMachines);
}
