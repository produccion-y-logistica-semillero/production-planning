import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  List<int> machinesIds = []; //list of machines id's available for this parallel machine
  List<List<Duration>> timeMatrix = []; //matrix of time it takes the task in each machine
  //  The first list (rows) are the indexes of jobs, and the inside list (columns) are the times in each machine
  //  the indexes in these lists (matrix) point to the same indexes in the list of inputJobs and machineId's
  //          :   0   |   1   |   2   |   3   |
  //      0     10:25 | 01:30 | 02:45 | 00:45 |
  //      1     08:25 | 00:30 | 02:50 | 00:12 |

  List<Tuple5<int, DateTime, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  job id   | Assigned machine ID  |  start date    |     End date    |     due date        |     Rest       
  //  1         |       14544         | 26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       114           | 26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesIds,
    this.timeMatrix,
    String rule,
  ) {
    switch (rule) {
      case "JHONSON":  jhonson2();break;
      case "JHONSON_2": jhonson2(); break;
    }
  }

  void jhonsonRule() {
    output.add(Tuple5(1, DateTime.now(), DateTime.now(),DateTime.now(), Durations.extralong2));
  }
  
  void jhonson2(){
  }
}

