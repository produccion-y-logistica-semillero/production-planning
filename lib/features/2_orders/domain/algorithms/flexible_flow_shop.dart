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
  // job id   | list of <selected machine id, <start time, end time>>
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
      case "JHONSON_2_MACHINES":  jhonsonRule();break;
      case "JHONSON_3_MACHINES": jhonson3(); break;
      case "JHONSON_CDS": jhonsonCDS(); break;
    }
  }

  void jhonsonRule() {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable = generateJhonsonTable();
    List<Tuple2<int, List<Tuple2<int, Duration>>>> group1 = [];
    List<Tuple2<int, List<Tuple2<int, Duration>>>> group2 = [];
    jhonsonTable.forEach((line){
      if(line.value2[0].value2 < line.value2[1].value2){
        group1.add(line);
      }
      else{
        group2.add(line);
      }
    });
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonSorted = [];
    jhonsonSorted.addAll(jhonsonSort(group1, 0));
    jhonsonSorted.addAll(jhonsonSort(group2, 1));
  }
  
  void jhonson3(){
  }

  void jhonsonCDS(){

  }

  //  id job  | [machine 1 id | task 1 duration , machine 2 id  | task 2 duration , ...]
  //    1     | [ 10          |   12:22         , 12            |   22:33         , ...]
  //    2     | [ 20          |   32:25         , 32            |   11:43         , ...]
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

  //  machine id  | task duration
  //    1         |   12:20     
  //    2         |   11:12
  //    4         |   14:11     
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

List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonSort(
  List<Tuple2<int, List<Tuple2<int, Duration>>>> disorganized, int mode // spt [0] or lpt [1]
){
  List<Tuple2<int, List<Tuple2<int, Duration>>>> organized = disorganized;
  for(int i = 0; i < organized.length; i++){
    for(int j = 0; j < organized.length - 1; j++){
      if(organized[j].value2[mode].value2 < organized[j+1].value2[mode].value2){
        dynamic aux = organized[j];
        organized[j] = organized[j+1];
        organized[j+1] = aux;
      }
    }
  }
  return organized;
}
// List<Tuple2<int, List<Tuple2<int, Tuple2<DateTime, DateTime>>>>> output = [];
void toOutput(List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable){
  Map<int, DateTime> lastMachineUse = {};
  jhonsonTable.forEach((line){
    int jobId = line.value1;
    line.value2.forEach((machine){
      lastMachineUse[machine.value1] = startDate;
    });
    List<Tuple2<int, Tuple2<DateTime, DateTime>>> outputMachines = [];
    line.value2.forEach((machine){
      Tuple2<int, Tuple2<DateTime, DateTime>> outputMachine;
        outputMachine = 
          Tuple2(
            jobId, 
            Tuple2(
              lastMachineUse[machine.value1]!, 
              lastMachineUse[machine.value1]!.add(machine.value2)
            )
          );
        outputMachines.add(outputMachine);
        output.add(Tuple2(jobId, outputMachines));
    });
  });
}
  
}

void main(){
  DateTime startDate = DateTime(2024, 11, 24);
  Tuple2<TimeOfDay, TimeOfDay> workingSchedule = 
    const Tuple2(TimeOfDay(hour: 10, minute: 11), TimeOfDay(hour: 10, minute: 11));
  List<Tuple5<int, DateTime, int, DateTime, List<List<Tuple2<int, Duration>>>>> inputJobs = 
    [
      Tuple5(1, 
        DateTime(2024, 11, 24), 
        1, 
        DateTime(2024, 11, 24),
        [
          [
            const Tuple2(
              1, 
              Duration(hours: 2)
            ),
            const Tuple2(
              2,
              Duration(hours: 1)
            )
          ],
          [
            const Tuple2(
              3, 
              Duration(hours: 2)
            ),
            const Tuple2(
              4,
              Duration(hours: 1)
            )
          ]
        ]
      )
    ];
  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = 
    [
      Tuple2(
        1,
        [
          Tuple2(
            DateTime(2024, 11, 24),
            DateTime(2024, 11, 24)
          )
        ]
      ),
      Tuple2(
        2,
        [
          Tuple2(
            DateTime(2024, 11, 24),
            DateTime(2024, 11, 24)
          )
        ]
      ),
      Tuple2(
        3,
        [
          Tuple2(
            DateTime(2024, 11, 24),
            DateTime(2024, 11, 24)
          )
        ]
      ),
      Tuple2(
        4,
        [
          Tuple2(
            DateTime(2024, 11, 24),
            DateTime(2024, 11, 24)
          )
        ]
      )
    ];
  String rule = "JHONSON_2_MACHINES";
  FlexibleFlowShop(startDate, workingSchedule, inputJobs, machines, rule);
}
