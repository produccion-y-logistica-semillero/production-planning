import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/shared/types/rnage.dart';

class FlowShopInput{
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //this list has the order of the tasks, it has a tuple of 2 <task id, machine id>
  final List<Tuple2<int,int>> taskSequence;
  //in this map we have the durations, the id is the task id, and the duration is how long it takes (since we know there's only one machine, and we already have that time)
  final Map<int, Duration> taskTimesInMachines;
  FlowShopInput(this.jobId, this.dueDate, this.priority,this.availableDate,this.taskSequence,this.taskTimesInMachines);
}

class FlowShopOutput{
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //the output, the map has the key the machine id, the value is a tuple of <task id, range start to end time> 
  final Map<int, Tuple2<int,Range>> machinesScheduling;
  FlowShopOutput(this.jobId,this.startDate, this.dueDate , this.endTime,this.machinesScheduling);
}

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17

  //List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  List<FlowShopInput> inputJobs = [];
  //List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  //this is to help in the algorithm, here we check until what date the machine of this ID is not available
  Map<int, DateTime> machinesAvailability = {};
  //List<List<Duration>> timeMatrix =[]; //matrix of time it takes the task in each machine type
  //  The first list (rows) are the indexes of jobs, and the inside list (columns) are the times in each machine type
  //  the indexes in these lists (matrix) point to the same indexes in the list of inputJobs and machineId's
  //          :   0   |   1   |   2   |   3   |
  //      0     10:25 | 01:30 | 02:45 | 00:45 |
  //      1     08:25 | 00:30 | 02:50 | 00:12 |

  List<FlowShopOutput> output = [];
  //List<Tuple3<int, List<Tuple2<DateTime, DateTime>>, DateTime>> output = [];
  //         |   Machine index 0   |   Machine index 1  |  Machine index 2    ....| DUE DATE
  // job 1   |   <10:00, 12:00>    |   <14:00, 17:00>   |    <18:00, 20:30>   ....|
  // job 2   |   <12:00, 13:45>    |   <17:00, 18:00>   |    <20:30, 21:30>   ....|

  FlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule,
  ) {
    switch (rule) {
      case "EDD":eddRule();break;
      case "SPT":sptRule();break;
      case "LPT":lptRule();break;
      case "FIFO":fifoRule();break;
      case "JOHNSON":johnsonRule();break;
      case "JOHNSON3":johnsonRule3();break;
      case "CDS":cdsAlgorithm();break;
    }
  }

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule((a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)));
  void lptRule() => _schedule((a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)));
  void fifoRule() => _schedule((a, b) => a.availableDate.compareTo(b.availableDate));


  void _schedule(int Function(FlowShopInput, FlowShopInput) comparator) {
    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  void _assignJobToMachines(FlowShopInput job) {
    DateTime jobStartTime = job.availableDate;
    Map<int, Tuple2<int, Range>> scheduling = {};

    for (var task in job.taskSequence) {
      int taskId = task.value1;
      int machineId = task.value2;
      Duration duration = job.taskTimesInMachines[taskId]!;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
      DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
      startTime = _adjustForWorkingSchedule(startTime);
      DateTime endTime = startTime.add(duration);
      endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

      scheduling[machineId] = Tuple2(taskId, Range(startTime, endTime));
      machinesAvailability[machineId] = endTime;
      jobStartTime = endTime;
    }

    output.add(FlowShopOutput(job.jobId, job.availableDate, job.dueDate, jobStartTime, scheduling));
  }

  int _totalProcessingTime(FlowShopInput job) {
    return job.taskTimesInMachines.values.fold(0, (sum, duration) => sum + duration.inMinutes);
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
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

  void johnsonRule() {
    if (inputJobs.isEmpty || inputJobs.any((job) => job.taskSequence.length != 2)) {
      throw Exception("Johnson's rule requires exactly two machines per job.");
    }

    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in inputJobs) {
      int machine1Id = job.taskSequence[0].value2;
      int machine2Id = job.taskSequence[1].value2;
      Duration timeOnMachine1 = job.taskTimesInMachines[job.taskSequence[0].value1]!;
      Duration timeOnMachine2 = job.taskTimesInMachines[job.taskSequence[1].value1]!;

      if (timeOnMachine1 < timeOnMachine2) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => a.taskTimesInMachines[a.taskSequence[0].value1]!.compareTo(
        b.taskTimesInMachines[b.taskSequence[0].value1]!));
    conjuntoII.sort((a, b) => b.taskTimesInMachines[b.taskSequence[1].value1]!.compareTo(
        a.taskTimesInMachines[a.taskSequence[1].value1]!));

    inputJobs = [...conjuntoI, ...conjuntoII];
    _schedule((a, b) => 0);  
  }

  void johnsonRule3() {
    if (inputJobs.isEmpty || inputJobs.any((job) => job.taskSequence.length != 3)) {
      throw Exception("Johnson's 3-machine rule requires exactly three machines per job.");
    }

    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in inputJobs) {
      int p1j = job.taskTimesInMachines[job.taskSequence[0].value1]!.inMinutes +
          job.taskTimesInMachines[job.taskSequence[1].value1]!.inMinutes;
      int p2j = job.taskTimesInMachines[job.taskSequence[1].value1]!.inMinutes +
          job.taskTimesInMachines[job.taskSequence[2].value1]!.inMinutes;

      if (p1j <= p2j) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)));
    conjuntoII.sort((a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)));

    inputJobs = [...conjuntoI, ...conjuntoII];
    _schedule((a, b) => 0);
  }

    void cdsAlgorithm() {
    if (inputJobs.isEmpty || inputJobs.any((job) => job.taskSequence.length < 3)) {
      throw Exception("The CDS algorithm requires at least three machines.");
    }

    int numJobs = inputJobs.length;
    int numMachines = inputJobs.first.taskSequence.length;

    List<FlowShopInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numMachines; k++) {
      List<FlowShopInput> tempJobs = [];

      for (var job in inputJobs) {
        int jobId = job.jobId;
        DateTime dueDate = job.dueDate;
        DateTime availableDate = job.availableDate;
        int priority = job.priority;
        List<Tuple2<int, int>> taskSequence = job.taskSequence;

        Map<int, Duration> reducedTimes = {};

        int firstTaskId = taskSequence[0].value1;
        int lastTaskIdK = taskSequence[k - 1].value1;
        Duration p1j = job.taskTimesInMachines.entries
            .where((entry) => entry.key <= lastTaskIdK)
            .map((entry) => entry.value)
            .reduce((a, b) => a + b);

        int firstTaskIdK = taskSequence[k].value1;
        int lastTaskIdM = taskSequence.last.value1;
        Duration p2j = job.taskTimesInMachines.entries
            .where((entry) => entry.key >= firstTaskIdK)
            .map((entry) => entry.value)
            .reduce((a, b) => a + b);

        reducedTimes[firstTaskId] = p1j;
        reducedTimes[lastTaskIdM] = p2j;

        tempJobs.add(FlowShopInput(jobId, dueDate, priority, availableDate, [taskSequence.first, taskSequence.last], reducedTimes));
      }

      List<FlowShopInput> conjuntoI = [];
      List<FlowShopInput> conjuntoII = [];

      for (var job in tempJobs) {
        int firstTaskId = job.taskSequence[0].value1;
        int lastTaskId = job.taskSequence[1].value1;
        Duration timeOnFirst = job.taskTimesInMachines[firstTaskId]!;
        Duration timeOnLast = job.taskTimesInMachines[lastTaskId]!;

        if (timeOnFirst <= timeOnLast) {
          conjuntoI.add(job);
        } else {
          conjuntoII.add(job);
        }
      }

      conjuntoI.sort((a, b) => a.taskTimesInMachines[a.taskSequence[0].value1]!.compareTo(
          b.taskTimesInMachines[b.taskSequence[0].value1]!));
      conjuntoII.sort((a, b) => b.taskTimesInMachines[b.taskSequence[1].value1]!.compareTo(
          a.taskTimesInMachines[a.taskSequence[1].value1]!));

      List<FlowShopInput> sequence = [...conjuntoI, ...conjuntoII];

      int makespan = _calculateMakespan(sequence);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = sequence;
      }
    }

    inputJobs = bestSequence;
    _schedule((a, b) => 0);
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  int _calculateMakespan(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> currentMachineAvailability = {};
    jobSequence.forEach((job) {
      for (var task in job.taskSequence) {
        int machineId = task.value2;
        currentMachineAvailability[machineId] = startDate;
      }
    });

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable = currentMachineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(duration);
        endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

        currentMachineAvailability[machineId] = endTime;
        jobStartTime = endTime;
      }

      makespanEndTime = jobStartTime.isAfter(makespanEndTime) ? jobStartTime : makespanEndTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }
}