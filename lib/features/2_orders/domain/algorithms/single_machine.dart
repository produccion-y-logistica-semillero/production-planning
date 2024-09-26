import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';

class SingleMachine{
  final int machineId;
  final DateTime startDate;          
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;   //like 8-17
  List<Tuple2<int, Duration>> input = [];    
  //the input comes like a table of type
  //  work id   |     unique machine duration
  //  1         |         15:30
  //  2         |         20:41 
  //  3         |         01:25


  List<Tuple5<int, Duration, DateTime, DateTime, Duration>> output = [];
  //the output goes like a table of type
  //  work id   |   processing time   |   start date    |     End date    |   Rest time
  //  1         |       01:30         |  26/09/24/10:00 | 26/09/24/11:30  |     00:00
  //  2         |       02:30         |  26/09/24/11:30 | 26/09/24/14:00  |     00:00



  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    String rule,
  ){
    switch(rule){
      case "JHONSON" : jhonsonRule(); break;
    }
  }

  void jhonsonRule(){
    output.add(Tuple5(1, Durations.long1, DateTime.now(), DateTime.now(), Durations.extralong2));
  }


}