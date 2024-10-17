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
 
  List<List<Duration>> timeMatrix = []; //matrix of time it takes the task in each machine type
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
      case "JHONSON":  jhonson2();break;
      case "JHONSON_2": jhonson2(); break;
    }
  }

  void jhonsonRule() {
    
  }
  
  void jhonson2(){
  }
}

