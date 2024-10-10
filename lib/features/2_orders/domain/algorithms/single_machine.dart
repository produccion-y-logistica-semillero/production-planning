import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class SingleMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple5<int, Duration, DateTime, int, DateTime>> input = [];
  //the input comes like a table of type
  //  job id   |     unique machine duration   |     due date        |       priority  | Available date
  //  1         |         15:30                 |   2024/8/30/6:00    |         1       | 2024/8/30/6:00
  //  2         |         20:41                 |   2024/8/30/6:00    |         3       | 2024/8/30/6:00
  //  3         |         01:25                 |   2024/8/30/6:00    |         2       | 2024/8/30/6:00

  List<Tuple5<int, DateTime, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  job id   |    start date    |     End date    |     due date        |     Rest       
  //  1         |   26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |   26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  SingleMachine(
    this.startDate,
    this.workingSchedule,
    this.input,
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
    
    Duration accumulator = const Duration();
    for(int i = input.length-1; i >= 0; i--){
      //logica, llamadas a fucniones
      if(i != input.length-1){
        int hours =  accumulator.inHours + input[i+1].value2.inHours;
        int minutes =  (accumulator.inMinutes - (accumulator.inHours *60 )) +
                      (input[i+1].value2.inMinutes - (input[i+1].value2.inHours *60 ));
        
        accumulator = Duration(hours: hours, minutes: minutes);
      }
        
      final workStartDate =  startDate.add(accumulator);
      output.add(Tuple5(
        input[i].value1,
        workStartDate,
        workStartDate.add(input[i].value2),
        input[i].value3,
        const Duration(hours:0)
      ));
    }
  }
}

