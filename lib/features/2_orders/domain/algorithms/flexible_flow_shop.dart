import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';


class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; 

  List<Tuple5<int, DateTime, int, DateTime, List<List<Tuple2<int, Duration>>>>> inputJobs = [];
  // Input format:
  // job id   |   due date       | priority | available date    |  LIST OF TASKS, FOR EACH TASK THERES A LIST OF ALL THE MACHINES OF THE MACHINE TYPE THAT THE TASK USES, WITH THE TIME IT'D TAKE THAT TASK IN THAT MACHINE, THE LIST IS IN ORDER OF TASKS
  //    1     |  2024/08/30/6:00 |     1    | 2024/08/30/6:00   |     [ [(105, 40:00), (506, 65:00)],  [(5, 36:00), (9, 45:00), (85, 20:00)], .... ]
  //    2     |  2024/08/30/6:00 |     2    | 2024/08/30/6:00   |      [ [(105, 40:00), (506, 65:00)],  [(5, 36:00), (9, 45:00), (85, 20:00)], .... ]
  //    3     |  2024/08/30/6:00 |     3    | 2024/08/30/6:00   |      [ [(105, 40:00), (506, 65:00)],  [(5, 36:00), (9, 45:00), (85, 20:00)], .... ]


  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = []; 
  //list of machines, and each one has its scheduling times, so we can check availability
  //  machine Id  |                   Scheduling
  //    1         |  [<2024-10-15-10:30, 2024-10-15-11:30> , <2024-10-15-10:30, 2024-10-15-11:30>]
  //    2         |  [<2024-10-15-10:30, 2024-10-15-11:30> , <2024-10-15-10:30, 2024-10-15-11:30>]

  List<Tuple2<int, List<Tuple2<int, Tuple2<DateTime, DateTime>>>>> output = [];
  // job id | list of <selected machine id, <start time, end time>>
  // job id   | machine schedule
  //    1     | [
  //              <101, <2024-09-26 08:00, 2024-09-26 09:12>>,  // Machine 101 selected for the first task
  //              <201, <2024-09-26 10:00, 2024-09-26 10:30>>   // Machine 201 selected for the second task
  //            ]
  //    2     | [
  //              <102, <2024-09-26 09:00, 2024-09-26 10:24>>,
  //              <202, <2024-09-26 11:00, 2024-09-26 11:30>>
  //            ]

  FlexibleFlowShop(
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
    
  }
  
  void jhonson2(){
  }
}
