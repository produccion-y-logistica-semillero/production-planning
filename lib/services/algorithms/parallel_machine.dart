import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class ParallelInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final Map<int, Duration> durationsInMachines;
  
  ParallelInput(this.jobId, this.dueDate, this.priority, this.availableDate, this.durationsInMachines);
}

class ParallelOutput {
  final int jobId;
  final int machineId;
  final DateTime startDate;
  final DateTime endDate;
  final Duration delay;
  final DateTime dueDate;
  
  ParallelOutput(this.jobId, this.machineId, this.startDate, this.endDate, this.delay, this.dueDate);
}

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<ParallelInput> inputJobs = [];
  Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
  List<ParallelOutput> output = [];

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule,
  ) {
    switch (rule) {
      case "SPT": sptRule(); break;
      case "LPT": lptRule(); break;
      case "EDD": eddRule(); break;
      case "FCFS":fcfsRule();break;
      case "MINSLACK": minslackRule(); break;
      case "CR": crRule(); break;
    }
  }

  void sptRule(){
    return _schedule((a, b) => _averageProcessingTime(a).compareTo(_averageProcessingTime(b)));
  }

  void lptRule(){
    return _schedule((a, b) => _averageProcessingTime(b).compareTo(_averageProcessingTime(a)));
  }

  void eddRule(){
    return _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  void fcfsRule(){
    return _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  }

  void minslackRule(){
    return  _schedule((a, b) => _slack(a).compareTo(_slack(b)));
  }

  void crRule(){
    return _schedule((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
  }

  void _schedule(int Function(ParallelInput, ParallelInput) comparator) {
    inputJobs.sort(comparator);
    _assignJobsToMachines();
  }

  double _averageProcessingTime(ParallelInput job) {
    return job.durationsInMachines.values.fold(0, (sum, d) => sum + d.inMinutes) / job.durationsInMachines.length;
  }

  int _slack(ParallelInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    int totalProcessingTime = job.durationsInMachines.values.fold(0, (sum, d) => sum + d.inMinutes);
    return remainingMinutes - totalProcessingTime;
  }

  double _criticalRatio(ParallelInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    int totalProcessingTime = job.durationsInMachines.values.fold(0, (sum, d) => sum + d.inMinutes);
    return totalProcessingTime == 0 ? double.infinity : remainingMinutes / totalProcessingTime;
  }

  void _assignJobsToMachines() {
    Map<int, DateTime> machineAvailable = {for (var id in machines.keys) id: startDate};
    
    for (var job in inputJobs) {
      int jobId = job.jobId;
      DateTime dueDate = job.dueDate;
      DateTime availableDate = job.availableDate;

      for (var entry in job.durationsInMachines.entries) {
        int machineId = entry.key;
        Duration processingTime = entry.value;
        DateTime machineStartTime = availableDate.isAfter(machineAvailable[machineId]!)
            ? availableDate
            : machineAvailable[machineId]!;
        
        machineStartTime = _adjustForWorkingSchedule(machineStartTime);
        DateTime endTime = _adjustEndTimeForWorkingSchedule(machineStartTime, processingTime);
        Duration delay = endTime.isAfter(dueDate) ? endTime.difference(dueDate) : Duration.zero;
        
        machineAvailable[machineId] = endTime;
        machines[machineId]?.add(Tuple2(machineStartTime, endTime));
        output.add(ParallelOutput(jobId, machineId, machineStartTime, endTime, delay, dueDate));
      }
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

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, Duration duration) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(start.year, start.month, start.day, workingEnd.hour, workingEnd.minute);
    DateTime endTime = start.add(duration);

    if (endTime.isAfter(endOfDay)) {
      Duration remainingTime = endTime.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute).add(remainingTime);
    }
    return endTime;
  }
}
