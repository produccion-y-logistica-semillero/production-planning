import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple5<int, DateTime, int, DateTime, List<Duration>>> inputJobs = [];
  //the input comes like a table of type
  //  job id   |     due date        |       priority  | Available date   |           Times
  //  1         |   2024/8/30/6:00    |         1       | 2024/8/30/6:00  |    [10:20, 01:30, 00:45]
  //  2         |   2024/8/30/6:00    |         3       | 2024/8/30/6:00  |    [10:20, 01:30, 00:45]
  //  3         |   2024/8/30/6:00    |         2       | 2024/8/30/6:00  |    [10:20, 01:30, 00:45]

  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = []; 
  //list of machines, and each one has its scheduling times, so we can check availability
  //  machine Id  |                   Scheduling
  //    1         |  [<2024-10-15-10:30, 2024-10-15-11:30> , <2024-10-15-10:30, 2024-10-15-11:30>]
  //    2         |  [<2024-10-15-10:30, 2024-10-15-11:30> , <2024-10-15-10:30, 2024-10-15-11:30>]
  

  List<Tuple5<int, DateTime, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  job id   | Assigned machine ID  |  start date    |     End date    |     due date        |     Rest       
  //  1         |       14544         | 26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       114           | 26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
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

