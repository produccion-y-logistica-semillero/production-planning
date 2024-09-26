

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/single_machine.dart';

void main(){
  test('Single machine test with jhonson', () async{
    //setup
    int machineId = 55;
    DateTime startDate = DateTime.now();
    final workingSchedule = Tuple2<TimeOfDay, TimeOfDay>(
      TimeOfDay.now(),
      TimeOfDay(hour: 22, minute: 60)
    );

    //expectation
    List<Tuple5<int, Duration, DateTime, DateTime, Duration>> output = [];
    output.add(Tuple5(1, Durations.long1, DateTime.now(), DateTime.now(), Durations.extralong2));

    //do
    final instance = SingleMachine(machineId, startDate, workingSchedule, 'JHONSON');

    //assert
    for(int i = 0; i < output.length; i++){
      print('${output[i].value1} / ${output[i].value2} / ${output[i].value3} / ${output[i].value4} / ${output[i].value5}');
    }
    expect(instance.output, equals(output));
  });
}