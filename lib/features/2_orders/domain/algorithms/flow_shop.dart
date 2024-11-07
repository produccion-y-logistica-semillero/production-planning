// ignore_for_file: avoid_print

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  List<List<Duration>> timeMatrix =
      []; //matrix of time it takes the task in each machine type
  //  The first list (rows) are the indexes of jobs, and the inside list (columns) are the times in each machine type
  //  the indexes in these lists (matrix) point to the same indexes in the list of inputJobs and machineId's
  //          :   0   |   1   |   2   |   3   |
  //      0     10:25 | 01:30 | 02:45 | 00:45 |
  //      1     08:25 | 00:30 | 02:50 | 00:12 |

  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> output = [];
  //         |   Machine index 0   |   Machine index 1  |  Machine index 2
  // job 1   |   <10:00, 12:00>    |   <14:00, 17:00>   |    <18:00, 20:30>
  // job 2   |   <12:00, 13:45>    |   <17:00, 18:00>   |    <20:30, 21:30>

  FlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.timeMatrix,
    String rule,
  ) {
    switch (rule) {
      case "JHONSON":
        johnsonRule();
        break;
      case "JHONSON_2":
        jhonson2();
        break;
    }
  }

  void johnsonRule() {
    /**
      1. create a list of jobs with their indexes
      2. sort the jobs with the rule
      3. schedule the jobs
      
     */

    try {
      if (timeMatrix.isEmpty || timeMatrix[0].length != 2) {
        throw Exception(
            "The Johnson's rule can only be applied to exactly two machines.");
      }

      for (var row in timeMatrix) {
        if (row.length != 2) {
          throw Exception(
              "Each job must have exactly two durations specified for the two machines.");
        }
      }

      // duration in machine 1 < duration in machine 2
      List<int> conjuntoI = [];
      // duration in machine 1 > duration in machine 2
      List<int> conjuntoII = [];

      for (int i = 0; i < timeMatrix.length; i++) {
        if (timeMatrix[i][0] < timeMatrix[i][1]) {
          conjuntoI.add(i);
        } else {
          conjuntoII.add(i);
        }
      }

      // SPT = sort from smallest to largest
      conjuntoI.sort((a, b) => timeMatrix[a][0].compareTo(timeMatrix[b][0]));
      // LPT = sort fromt largest to smallest
      conjuntoII.sort((a, b) => timeMatrix[b][1].compareTo(timeMatrix[a][1]));

      print("Sorted set I: $conjuntoI");
      print("Sorted set II: $conjuntoII");

      List<int> jobIndices = [...conjuntoI, ...conjuntoII];
      print("Sorted jobIndices: $jobIndices");

      DateTime currentTimeMachine1 = startDate;
      DateTime currentTimeMachine2 = startDate;

      for (int jobIndex in jobIndices) {
        // these store the job's duration  in the machine
        Duration timeOnMachine1 = timeMatrix[jobIndex][0];
        Duration timeOnMachine2 = timeMatrix[jobIndex][1];

        // current time in the machine 1
        DateTime startTimeMachine1 = currentTimeMachine1;
        // end time is equal to currentTime plus timeOnMachine
        DateTime endTimeMachine1 = currentTimeMachine1.add(timeOnMachine1);
        currentTimeMachine1 = endTimeMachine1;

        DateTime startTimeMachine2 =
            // if currentTimeMachine2 is after endTimeMachine is because this is busy; so startTimeMachine goint to be the hour where Machine2 is free. Otherwise
            // startTime2 can be the same endTime1
            (currentTimeMachine2.isAfter(endTimeMachine1))
                ? currentTimeMachine2
                : endTimeMachine1;
        DateTime endTimeMachine2 = startTimeMachine2.add(timeOnMachine2);
        currentTimeMachine2 = endTimeMachine2;

        // add the job id and its schedule for machine 1 and machine 2 (is the same tuple created before)
        output.add(Tuple2(
          jobIndex,
          [
            Tuple2(startTimeMachine1, endTimeMachine1),
            Tuple2(startTimeMachine2, endTimeMachine2),
          ],
        ));

        // Print statements to observe the scheduling process (error tests)
        print(
            "Job $jobIndex scheduled on Machine 1: $startTimeMachine1 - $endTimeMachine1");
        print(
            "Job $jobIndex scheduled on Machine 2: $startTimeMachine2 - $endTimeMachine2");
      }
    } catch (e) {
      print("Error while applying Johnson's rule: $e");
      throw Exception("An error occurred during job scheduling: $e");
    }
  }

  void jhonson2() {}
}
