import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/shared/types/rnage.dart';

class FlexibleFlowInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //tuple2 <task id, Map<machineId, Duration of task in machine>>
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  FlexibleFlowInput(this.jobId, this.dueDate, this.priority, this.availableDate, this.taskSequence);
}

class FlexibleFlowOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //map<task id, tuple2<machineId, range scheuled>>
  final Map<int, Tuple2<int, Range>> scheduling;

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
      case "JHONSON_2_MACHINES":johnsonRule2();break;
      case "JHONSON_3_MACHINES":johnsonRule3();break;
      case "JHONSON_CDS":johnsonCDS();break;
    }
  }

  void johnsonRule2() {
    _scheduleJohnsonRule(2);
  }

  void johnsonRule3() {
    _scheduleJohnsonRule(3);
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

  void _scheduleJohnsonRule(int partitionSize) {
    List<FlexibleFlowInput> sortedJobs = _applyJohnsonRule(partitionSize);
    for (var job in sortedJobs) {
      _assignJobToMachines(job);
    }
  }

  List<FlexibleFlowInput> _applyJohnsonRule(int partitionSize) {
    List<FlexibleFlowInput> conjuntoI = [];
    List<FlexibleFlowInput> conjuntoII = [];

    for (var job in inputJobs) {
      int firstTaskId = job.taskSequence.first.value1;
      int lastTaskId = job.taskSequence.last.value1;
      Duration firstPartitionTime = job.taskSequence.sublist(0, partitionSize)
          .map((t) => t.value2.values.reduce((a, b) => a + b))
          .reduce((a, b) => a + b);
      Duration secondPartitionTime = job.taskSequence.sublist(partitionSize)
          .map((t) => t.value2.values.reduce((a, b) => a + b))
          .reduce((a, b) => a + b);

      if (firstPartitionTime <= secondPartitionTime) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)));
    conjuntoII.sort((a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)));

    return [...conjuntoI, ...conjuntoII];
  }

  void _assignJobToMachines(FlexibleFlowInput job) {
    DateTime jobStartTime = job.availableDate;
    Map<int, Tuple2<int, Range>> scheduling = {};

    for (var task in job.taskSequence) {
      int taskId = task.value1;
      Tuple2<int, Duration> selectedMachine = _selectMachine(task.value2);
      int machineId = selectedMachine.value1;
      Duration duration = selectedMachine.value2;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
      DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
      startTime = _adjustForWorkingSchedule(startTime);
      DateTime endTime = startTime.add(duration);
      endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

      scheduling[taskId] = Tuple2(machineId, Range(startTime, endTime));
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

  int _calculateMakespan() {
    return output.map((o) => o.endTime.difference(startDate).inMinutes).reduce((a, b) => a > b ? a : b);
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    if (start.hour < workingStart.hour || (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);
    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingSchedule.value1.hour, workingSchedule.value1.minute).add(remainingTime);
    }
    return end;
  }
}
