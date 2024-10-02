import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; //like 8-17
  List<Tuple4<int, Duration, DateTime, int>> input = [];
  //the input comes like a table of type
  //  work id   |     unique machine duration   |     due date        |       priority
  //  1         |         15:30                 |   2024/8/30/6:00    |         1
  //  2         |         20:41                 |   2024/8/30/6:00    |         3
  //  3         |         01:25                 |   2024/8/30/6:00    |         2

  List<Tuple6<int, Duration, DateTime, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  work id   |   processing time   |   start date    |     End date    |     due date        |     Rest       
  //  1         |       01:30         |  26/09/24/10:00 | 26/09/24/11:30  |   2024/8/30/6:00    |     00:00
  //  2         |       02:30         |  26/09/24/11:30 | 26/09/24/14:00  |   2024/8/30/6:00    |     00:00

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule,
  ) {
    switch (rule) {
      case "JHONSON":jhonsonRule();break;
      case "JHONSON_2": jhonson2(); break;
    }
  }

  void jhonsonRule() {
    output.add(Tuple6(1, Durations.long1, DateTime.now(), DateTime.now(),DateTime.now(), Durations.extralong2));
  }
  
  void jhonson2(){
    
    Duration accumulator = Duration();
    for(int i = input.length-1; i >= 0; i--){
      //logica, llamadas a fucniones
      if(i != input.length-1){
        int hours =  accumulator.inHours + input[i+1].value2.inHours;
        int minutes =  (accumulator.inMinutes - (accumulator.inHours *60 )) +
                      (input[i+1].value2.inMinutes - (input[i+1].value2.inHours *60 ));
        
        accumulator = Duration(hours: hours, minutes: minutes);
      }
        
      final workStartDate =  startDate.add(accumulator);
      output.add(Tuple6(
        input[i].value1,
        input[i].value2,
        workStartDate,
        workStartDate.add(input[i].value2),
        input[i].value3,
        Duration(hours:0)
      ));
    }
  }
}


////////////////////////////////////////////////////////////
void main(){
  //single 
  final int machineId = 0;
  final startDate = DateTime(2024, 8,30,14,30);
  final workingSchedule = Tuple2(TimeOfDay(hour: 8, minute:0), TimeOfDay(hour: 17, minute:0));
  
  
  //input
  List<Tuple4<int, Duration, DateTime, int>> input = [];
  input.add(Tuple4(74, Duration(hours: 2, minutes: 30), DateTime(2024, 8,30,6), 1));
  input.add(Tuple4(41, Duration(days: 4, hours: 4, minutes: 16), DateTime(2024, 8,30,6), 3));
  input.add(Tuple4(3000, Duration(hours: 7, minutes: 47), DateTime(2024, 8,30,6),2 ));
  
  
  //use
  final instance = SingleMachine(machineId, startDate, workingSchedule, input, "JHONSON_2");
  
  final result = instance.output;
  
  
  //comprobation
  for(final tuple in result){
    print('id trabajo ${tuple.value1} tiempo procesamiento: ${tuple.value2.inMinutes} inicia en: ${tuple.value3} y termina en ${tuple.value4}');
    
  }
  
}


