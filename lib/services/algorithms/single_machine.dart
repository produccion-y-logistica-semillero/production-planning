import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class SingleMachineInput {
  final int jobId;
  final Duration machineDuration;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  SingleMachineInput(this.jobId, this.machineDuration, this.dueDate,
      this.priority, this.availableDate);
}

class SingleMachineOutput {
  final int jobId;
  final Duration processingTime;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final Duration delay;
  SingleMachineOutput(this.jobId, this.processingTime, this.startDate,
      this.endDate, this.dueDate, this.delay);
}

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  //List<Tuple5<int, Duration, DateTime, int, DateTime>> input = [];
  List<SingleMachineInput> input = [];
  //the input comes like a table of type
  //  job id   |     unique machine duration   |     due date        |       priority    |     Available date
  //  1         |         15:30                 |   2024/8/30/6:00    |         1         |     2024/8/28/6:00
  //  2         |         20:41                 |   2024/8/30/6:00    |         3         |     2024/8/28/6:00
  //  3         |         01:25                 |   2024/8/30/6:00    |         2         |     2024/8/28/6:00

  //List<Tuple6<int, Duration, DateTime, DateTime, DateTime, Duration>> output = [];
  List<SingleMachineOutput> output = [];
  //the output goes like a table of type
  //  job id   |   processing time   |   start date    |     End date    |     due date        |     Delay (Retraso)
  //  1         |       01:30         |  26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       02:30         |  26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule,
  ) {
    switch (rule) {
      //case "JHONSON":jhonsonRule();break;
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
        eddRuleAdapted();
        break;
      case "SPT_ADAPTADO":
        sptRuleAdapted();
        break;
      case "LPT_ADAPTADO":
        lptRuleAdapted();
        break;
      case "FIFO_ADAPTADO":
        fifoRuleAdapted();
        break;
      case "WSPT_ADAPTADO":
        wsptRuleAdapted();
        break;
      case "MINSLACK":
        scheduleMinimumSlack();
        break;
      case "CR":
        scheduleCriticalRatio();
        break;
    }
  }

  DateTime _getStartTime(DateTime availableDate) {
    DateTime workStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute);
    return availableDate.isBefore(workStart) ? workStart : availableDate;
  }

  DateTime _getAvailableStartTime(DateTime current, Duration duration) {
    int workEndMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;
    int currentMinutes =
        current.hour * 60 + current.minute + duration.inMinutes;
    if (currentMinutes > workEndMinutes) {
      DateTime nextDay = current.add(const Duration(days: 1));
      return DateTime(nextDay.year, nextDay.month, nextDay.day,
          workingSchedule.value1.hour, workingSchedule.value1.minute);
    }
    return current;
  }

  void eddRule() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    DateTime startWorkDateTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      workingSchedule.value1.hour,
      workingSchedule.value1.minute,
    );

    DateTime earliestJobAvailableTime = input[0].availableDate;
    DateTime scheduleTime = earliestJobAvailableTime.isBefore(startWorkDateTime)
        ? startWorkDateTime
        : earliestJobAvailableTime;

    for (var job in input) {
      DateTime start;
      DateTime end;
      Duration delay;

      int totalTime = (scheduleTime.hour * 60) +
          scheduleTime.minute +
          job.machineDuration.inMinutes;
      int endOfDay =
          workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

      if (totalTime < endOfDay) {
        start = scheduleTime;
      } else {
        scheduleTime = scheduleTime.add(const Duration(days: 1));
        scheduleTime = DateTime(
          scheduleTime.year,
          scheduleTime.month,
          scheduleTime.day,
          workingSchedule.value1.hour,
          workingSchedule.value1.minute,
        );
        start = scheduleTime;
      }

      scheduleTime = scheduleTime.add(job.machineDuration);
      end = scheduleTime;

      delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;

      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
    }
  }

  void sptRule() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);

    for (var job in input) {
      DateTime start =
          _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;

      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = end;
    }
  }

  void lptRule() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);

    for (var job in input) {
      DateTime start =
          _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;

      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = end;
    }
  }

  void fifoRule() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);
    for (var job in input) {
      DateTime start =
          _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;
      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = end;
    }
  }

  void wsptRule() {
    input.sort((a, b) => (b.priority / b.machineDuration.inMinutes)
        .compareTo(a.priority / a.machineDuration.inMinutes));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);
    for (var job in input) {
      DateTime start =
          _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;
      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = end;
    }
  }

  void eddRuleAdapted() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    DateTime scheduleTime = _getStartTime(input[0].availableDate);

    for (var job in input) {
      DateTime start =
          _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate)
          ? end.difference(job.dueDate)
          : Duration.zero;

      output.add(SingleMachineOutput(
          job.jobId, job.machineDuration, start, end, job.dueDate, delay));
      scheduleTime = end;
    }
  }

  void sptRuleAdapted() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    eddRuleAdapted();
  }

  void lptRuleAdapted() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    eddRuleAdapted();
  }

  void fifoRuleAdapted() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    eddRuleAdapted();
  }

  void wsptRuleAdapted() {
    input.sort((a, b) => (b.priority / b.machineDuration.inMinutes)
        .compareTo(a.priority / a.machineDuration.inMinutes));
    eddRuleAdapted();
  }

  ///////////////////////////////////////////////////
///////////////////Reglas DINÁMICAS////////////////////
  ///////////////////////////////////////////////////
  // Implementación de la regla de Minimum Slack
  void scheduleMinimumSlack() {
    input.sort((a, b) => _slack(a) < _slack(b) ? -1 : 1);
    eddRuleAdapted();
  }

  int _slack(SingleMachineInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    return remainingMinutes - job.machineDuration.inMinutes;
  }

  void scheduleCriticalRatio() {
    input.sort((a, b) => _criticalRatio(a).compareTo(_criticalRatio(b)));
    eddRuleAdapted();
  }

  double _criticalRatio(SingleMachineInput job) {
    int remainingMinutes = job.dueDate.difference(job.availableDate).inMinutes;
    return remainingMinutes / job.machineDuration.inMinutes;
  }
}
