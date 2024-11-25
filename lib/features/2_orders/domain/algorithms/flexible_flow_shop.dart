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
      case "JHONSON":  jhonsonRule();break;
      case "JHONSON_2": jhonson2(); break;
      case "JHONSON_CDS": jhonsonCDS(); break;
    }
  }

  void jhonsonRule() {


  }
  
  void jhonson2(){
  }

  void jhonsonCDS(){

  }

  int getMachineIndexById(int id){
    for(int i  = 0; i < machines.length; i++){
      if(machines[i].head == id){
        return i;
      }
    }
    return -1;
  }

  List<Tuple2<int, List<Tuple2<int, Duration>>>> generateJhonsonTable(){
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable = [];
    inputJobs.forEach((job){
      job.value5.forEach((task){
        Tuple2<int, List<Tuple2<int, Duration>>> line = Tuple2(job.value1, chooseMachines(task));
        jhonsonTable.add(line);
      });
    });
    return jhonsonTable;
  }

  List<Tuple2<int, Duration>> chooseMachines(List<Tuple2<int, Duration>> elegibleMachines){
    List<Tuple2<int, Duration>> chosenMachines = [];
    elegibleMachines.forEach((elegibleMachine){
      Tuple2<int, Duration> chosenMachine = const Tuple2(-1, Duration(days: 9999999));
      machines.forEach((machine){
        bool elegible = (machine.value1 == elegibleMachine.value1);
        bool faster = (elegibleMachine.value2 < chosenMachine.value2);
        if(elegible && faster){
          chosenMachine = Tuple2(machine.value1, elegibleMachine.value2);
        }
      });
      chosenMachines.add(chosenMachine);
    });
    return chosenMachines;
  }

  bool containsRange(Tuple2<DateTime, DateTime> range1, Tuple2<DateTime, DateTime> range2) {
  final start1 = range1.value1;
  final end1 = range1.value2;
  final start2 = range2.value1;
  final end2 = range2.value2;
  return start1.isBefore(start2) || start1.isAtSameMomentAs(start2) &&
         end1.isAfter(end2) || end1.isAtSameMomentAs(end2);
}
  
}

void main(){

}
