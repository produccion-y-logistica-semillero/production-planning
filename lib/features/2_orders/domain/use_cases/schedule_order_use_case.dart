import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/single_machine.dart';
import 'package:production_planning/features/2_orders/domain/entities/metrics.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/shared/functions/rule_3_duration.dart';

class ScheduleOrderUseCase implements UseCase<List<PlanningMachineEntity>, Tuple3<int, String, String>>{

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  ScheduleOrderUseCase({
    required this.orderRepository,
    required this.machineRepository,
  });

  @override
  Future<Either<Failure, List<PlanningMachineEntity>>> call({required Tuple3<int, String, String> p}) async{  //tuple < orderid, rule name, enviroment name>
    return switch(p.value3){
      'SINGLE MACHINE' => Right(await singleMachineAdapter(p.value1, p.value2)),
      String() => Left(EnviromentNotCorrectFailure()),
    };
  }

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>> singleMachineAdapter(int orderId, String rule) async{
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f){}, (or)=>order = or);
    if(order == null) return [];

    //getting the unique machine
    MachineEntity? machineEntity;
    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachine.fold((f){}, (m)=> machineEntity = m[0]);
    if(machineEntity == null) return [];

    //getting machine type for the name
    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f){}, (name)=>machineTypeName = name);


    //creating input format
    final List<Tuple5<int, Duration, DateTime, int, DateTime>> input =  order!.orderJobs!
      .map((job)=> Tuple5<int, Duration, DateTime, int, DateTime>(
          job.jobId!,
          ruleOf3(
            machineEntity!.processingTime,
            job.sequence!.tasks![0].processingUnits 
          ),
          job.dueDate,
          job.priority,
          job.availableDate
        )
      ).toList();



    //TO DO LATER, SCHEDULE SHOULD BE TAKEN FROM CONFIGURATION IN DATABASE, FOR NOW WE WILL IMAGINE THE TYPICAL 8-5
    final output = SingleMachine(
      order!.regDate,
      Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0)),
      input,
      rule
    ).output;
    

    //get tasks
    final tasks = output.map((out)=>PlanningTaskEntity(
        sequenceId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.id!,
        sequenceName: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.name,
        taskId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.tasks![0].id!,
        numberProcess:  1,    //to change later depending on amount of a sequence
        startDate: out.value2,
        endDate: out.value3,
        retarded: !out.value2.isBefore(out.value4)
      )
    ).toList();

    final machinesResult = [
      PlanningMachineEntity(
        machineEntity!.id!,
        machineTypeName,
        tasks
      )
    ];

    //get metricts


    return Tuple2(machinesResult, Metrics());
  }


  Metrics getMetricts(List<PlanningMachineEntity> machines, List<Tuple3<DateTime, DateTime, DateTime>> jobsDates){  //(start date, end date, due date)
    machines.forEach((machine)=>machine.tasks.orderByStartDate());

    //IDLE METRIC (TIME OF MACHINES NOT BEING USED)
    Duration totalIdle = Duration.zero;
    for(final machine in machines){
      DateTime? previousEnd = null;
      for(final task in machine.tasks){
        if(previousEnd == null){
          previousEnd = task.endDate;
        }
        else{
          final currentIdle = task.startDate.difference(previousEnd);
          totalIdle = Duration(minutes: (totalIdle.inMinutes + currentIdle.inMinutes));
        }
      }
    }
    final Duration idle = Duration(minutes:  (totalIdle.inMinutes / machines.length).toInt()); 

    /////////other metrics

    //avarage processing time
    final avarageProcessingMinutes = jobsDates.map((tuple)=>  tuple.value2.difference(tuple.value1))
      .reduce((previous, time)=> Duration(minutes: (previous.inMinutes + time.inMinutes)))
      .inMinutes / jobsDates.length;
    final avarageProcessingTime = Duration(minutes: avarageProcessingMinutes.toInt());

    // avarage delay
    final avarageDelayMinutes = jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .reduce((previous, delay)=> Duration(minutes: (previous.inMinutes + delay.inMinutes))).inMinutes / jobsDates.length;
    final avarageDelay = Duration(minutes: avarageDelayMinutes.toInt());

    // max delay
    final maxDelay =jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? dates.value2.difference(dates.value3) : Duration.zero)
      .reduce((previous, delay)=> delay.inMinutes > previous.inMinutes ? delay : previous);
    
    //avarage lateness (can be negative)
    final avarageLatenessMinutes = jobsDates.map((dates)=> dates.value2.difference(dates.value3))
      .reduce((previous, delay)=> Duration(minutes: (previous.inMinutes + delay.inMinutes))).inMinutes / jobsDates.length;
    final avarageLateness = Duration(minutes: avarageLatenessMinutes.toInt());

    //late jobs
    final delayedJobs = jobsDates.map((dates)=> dates.value2.isAfter(dates.value3) ? 1 : 0).reduce((p, c) => p+c);

    return Metrics(
      idle: idle, 
      totalJobs: jobsDates.length, 
      maxDelay: maxDelay, 
      avarageProcessingTime: avarageProcessingTime, 
      avarageDelayTime: avarageDelay, 
      avarageLatenessTime: avarageLateness, 
      delayedJobs: delayedJobs
    );

  }
}

extension on List<PlanningTaskEntity>{

  void orderByStartDate(){
    for(int i = 0; i < this.length; i++){
      for(int j = i+1; j < this.length; j++){
        if(this[i].startDate.isAfter(this[j].startDate)){
          PlanningTaskEntity auxStartDate = this[i];
          this[i] = this[j];
          this[j] = auxStartDate;
        }
      }
    }
  }
}