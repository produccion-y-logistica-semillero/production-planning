import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;

  List<Tuple5<int, DateTime, int, DateTime, List<List<Tuple2<int, Duration>>>>>
      inputJobs = [];
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
      case "JHONSON_2_MACHINES":
        jhonson2();
        break;
      case "JHONSON_3_MACHINES":
        jhonson3();
        break;
      case "JHONSON_CDS":
        jhonsonCDS();
        break;
    }
  }

  List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonRule(List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable) {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> group1 = [];
    List<Tuple2<int, List<Tuple2<int, Duration>>>> group2 = [];
    jhonsonTable.forEach((line) {
      if (line.value2[0].value2 < line.value2[1].value2) {
        group1.add(line);
      } else {
        group2.add(line);
      }
    });
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonSorted = [];
    jhonsonSorted.addAll(jhonsonSort(group1, 0));
    jhonsonSorted.addAll(jhonsonSort(group2, 1));
    return jhonsonSorted;
  }

  void jhonson2() {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable =
        generateJhonsonTable();
    toOutput(jhonsonRule(jhonsonTable));
  }

  void jhonson3() {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable =
      generateJhonsonTable();
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonSorted = 
      jhonsonRule(toJhonson2(jhonsonTable, 2));
    toOutput(copySort(jhonsonTable, jhonsonSorted));
  }

  List<Tuple2<int, List<Tuple2<int, Duration>>>> copySort(
    List<Tuple2<int, List<Tuple2<int, Duration>>>> unsorted,
    List<Tuple2<int, List<Tuple2<int, Duration>>>> guide
  ){
    List<Tuple2<int, List<Tuple2<int, Duration>>>> sorted = [];
    guide.forEach((guideLine){
      unsorted.forEach((unsortedLine){
        if(guideLine.value1 == unsortedLine.value1){
          sorted.add(unsortedLine);
        }
      });
    });
    print("cpy sorted $sorted");
    return sorted;
  }
  

  // Takes any Jhonson Table and turns it into a Jhonson Table for two machines
  List<Tuple2<int, List<Tuple2<int, Duration>>>> toJhonson2(
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable,
    int groupSize
    ){
      List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonson2Table = [];
      jhonsonTable.forEach((jhonsonLine){
        Tuple2<int, List<Tuple2<int, Duration>>> jhonson2Line;
        int jobId = jhonsonLine.value1;
        Duration p1 = const Duration(hours: 0);
        Duration p2 = const Duration(hours: 0);
        for(int i = 0; i < groupSize; i++){
          p1 += jhonsonLine.value2[i].value2;
        }
        for(int i = jhonsonLine.value2.length - 1; i >= jhonsonLine.value2.length - groupSize; i--){
          p2 += jhonsonLine.value2[i].value2;
        }
        jhonson2Line =  Tuple2(
                  jobId, [
                            Tuple2(1, p1),
                            Tuple2(2, p2)
                          ]
                        );
        jhonson2Table.add(jhonson2Line);
      });
      print("jhonson2Table $jhonson2Table");
      return jhonson2Table;
    }

  void jhonsonCDS() {}

  // List<Tuple5<int, DateTime, int, DateTime, List<List<Tuple2<int, Duration>>>>> inputJobs = [];

  //  id job  | [machine 1 id | task 1 duration , machine 2 id  | task 2 duration , ...]
  //    1     | [ 10          |   12:22         , 12            |   22:33         , ...]
  //    2     | [ 20          |   32:25         , 32            |   11:43         , ...]
  List<Tuple2<int, List<Tuple2<int, Duration>>>> generateJhonsonTable() {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable = [];
    inputJobs.forEach((job) {
      List<Tuple2<int, Duration>> chosenMachines = [];
      job.value5.forEach((task) {
        Tuple2<int, Duration> chosenMachine = chooseMachine(task);
        chosenMachines.add(chosenMachine);
      });
      Tuple2<int, List<Tuple2<int, Duration>>> line =
          Tuple2(job.value1, chosenMachines);
      jhonsonTable.add(line);
    });
    return jhonsonTable;
  }

  //  machine id  | task duration
  //    1         |   12:20
  Tuple2<int, Duration> chooseMachine(
      List<Tuple2<int, Duration>> elegibleMachines) {
    Tuple2<int, Duration> chosenMachine =
        const Tuple2(-1, Duration(days: 9999999));
    elegibleMachines.forEach((elegibleMachine) {
      machines.forEach((machine) {
        bool elegible = (machine.value1 == elegibleMachine.value1);
        bool faster = (elegibleMachine.value2 < chosenMachine.value2);
        if (elegible && faster) {
          chosenMachine = Tuple2(machine.value1, elegibleMachine.value2);
        }
      });
    });
    return chosenMachine;
  }

  bool containsRange(
      Tuple2<DateTime, DateTime> range1, Tuple2<DateTime, DateTime> range2) {
    final start1 = range1.value1;
    final end1 = range1.value2;
    final start2 = range2.value1;
    final end2 = range2.value2;
    return start1.isBefore(start2) ||
        start1.isAtSameMomentAs(start2) && end1.isAfter(end2) ||
        end1.isAtSameMomentAs(end2);
  }

  List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonSort(
      List<Tuple2<int, List<Tuple2<int, Duration>>>> disorganized,
      int mode // spt [0] or lpt [1]
      ) {
    List<Tuple2<int, List<Tuple2<int, Duration>>>> organized = disorganized;
    for (int i = 0; i < organized.length; i++) {
      for (int j = 0; j < organized.length - 1; j++) {
        if (organized[j].value2[mode].value2 <
            organized[j + 1].value2[mode].value2) {
          dynamic aux = organized[j];
          organized[j] = organized[j + 1];
          organized[j + 1] = aux;
        }
      }
    }
    return organized;
  }

// List<Tuple2<int, List<Tuple2<int, Tuple2<DateTime, DateTime>>>>> output = [];
  void toOutput(List<Tuple2<int, List<Tuple2<int, Duration>>>> jhonsonTable) {
    Map<int, DateTime> lastMachineUse = {};
    Map<int, DateTime> lastJobUse = {};
    jhonsonTable.forEach((line) {
      lastJobUse[line.value1] = startDate;
      line.value2.forEach((machine) {
        lastMachineUse[machine.value1] = startDate;
      });
    });
    jhonsonTable.forEach((line) {
      int jobId = line.value1;
      List<Tuple2<int, Tuple2<DateTime, DateTime>>> outputMachines = [];
      for (int i = 0; i < line.value2.length; i++) {
        Tuple2<int, Tuple2<DateTime, DateTime>> outputMachine;
        if (i == 0) {
          outputMachine = Tuple2(
              line.value2[i].value1,
              Tuple2(
                  lastMachineUse[line.value2[i].value1]!,
                  lastMachineUse[line.value2[i].value1]!
                      .add(line.value2[i].value2)));
        } else {
          DateTime auxDT;
          if (lastJobUse[jobId]!
              .isBefore(lastMachineUse[line.value2[i].value1]!)) {
            auxDT = lastMachineUse[line.value2[i].value1]!;
          } else {
            auxDT = lastJobUse[jobId]!;
          }
          outputMachine = Tuple2(line.value2[i].value1,
              Tuple2(auxDT, auxDT.add(line.value2[i].value2)));
        }
        lastJobUse[jobId] = outputMachine.value2.value2;
        lastMachineUse[line.value2[i].value1] = outputMachine.value2.value2;
        outputMachines.add(outputMachine);
      }
      output.add(Tuple2(jobId, outputMachines));
    });
    print("output: $output");
  }
}

void main() {
  DateTime startDate = DateTime(2024, 11, 24);
  Tuple2<TimeOfDay, TimeOfDay> workingSchedule = const Tuple2(
      TimeOfDay(hour: 10, minute: 11), TimeOfDay(hour: 10, minute: 11));
  List<Tuple5<int, DateTime, int, DateTime, List<List<Tuple2<int, Duration>>>>>
      inputJobs = [
    Tuple5(1, DateTime(2024, 11, 24), 1, DateTime(2024, 11, 24), [
      [const Tuple2(1, Duration(hours: 2))],
      [const Tuple2(2, Duration(hours: 3))],
      [const Tuple2(3, Duration(hours: 1))]
    ]),
    Tuple5(2, DateTime(2024, 11, 24), 1, DateTime(2024, 11, 24), [
      [const Tuple2(1, Duration(hours: 4))],
      [const Tuple2(2, Duration(hours: 1))],
      [const Tuple2(3, Duration(hours: 3))]
    ]),
    Tuple5(3, DateTime(2024, 11, 25), 2, DateTime(2024, 11, 25), [
      [const Tuple2(1, Duration(hours: 3))],
      [const Tuple2(2, Duration(hours: 5))],
      [const Tuple2(3, Duration(hours: 4))]
    ]),
    Tuple5(4, DateTime(2024, 11, 25), 3, DateTime(2024, 11, 25), [
      [const Tuple2(1, Duration(hours: 6))],
      [const Tuple2(2, Duration(hours: 2))],
      [const Tuple2(3, Duration(hours: 5))]
    ]),
    Tuple5(5, DateTime(2024, 11, 26), 1, DateTime(2024, 11, 26), [
      [const Tuple2(1, Duration(hours: 2))],
      [const Tuple2(2, Duration(hours: 4))],
      [const Tuple2(3, Duration(hours: 1))]
    ]),
    Tuple5(6, DateTime(2024, 11, 26), 2, DateTime(2024, 11, 26), [
      [const Tuple2(1, Duration(hours: 1))],
      [const Tuple2(2, Duration(hours: 3))],
      [const Tuple2(3, Duration(hours: 7))]
    ])
  ];

  List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = [
    Tuple2(1, [Tuple2(DateTime(2024, 11, 24), DateTime(2024, 11, 24))]),
    Tuple2(2, [Tuple2(DateTime(2024, 11, 24), DateTime(2024, 11, 24))]),
    Tuple2(3, [Tuple2(DateTime(2024, 11, 24), DateTime(2024, 11, 24))]),
    Tuple2(4, [Tuple2(DateTime(2024, 11, 24), DateTime(2024, 11, 24))])
  ];
  String rule = "JHONSON_3_MACHINES";
  FlexibleFlowShop(startDate, workingSchedule, inputJobs, machines, rule);
}
