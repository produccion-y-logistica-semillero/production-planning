import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/parallel_machine.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/single_machine.dart';
import 'package:production_planning/features/2_orders/domain/entities/metrics.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/shared/functions/rule_3_duration.dart';

class ScheduleOrderUseCase implements UseCase<Tuple2<List<PlanningMachineEntity>, Metrics>?, Tuple3<int, String, String>>{

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  ScheduleOrderUseCase({
    required this.orderRepository,
    required this.machineRepository,
  });

  @override
  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>> call({required Tuple3<int, String, String> p}) async{  //tuple < orderid, rule name, enviroment name>
    return switch(p.value3){
      'SINGLE MACHINE' => Right(await singleMachineAdapter(p.value1, p.value2)),
      'PARALLEL MACHINES' => Right(await parallelMachineAdapter(p.value1, p.value2)),
      String() => Left(EnviromentNotCorrectFailure()),
    };
  }


  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(int orderId, String rule) async {
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f) {}, (or) => order = or);
    if (order == null) return null;

    // Getting all machines of the specified type
    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    List<MachineEntity> machineEntities = [];
    final responseMachines = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachines.fold((f) {}, (m) => machineEntities = m);
    if (machineEntities.isEmpty) return null;

    // Getting machine type name
    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f) {}, (name) => machineTypeName = name);

    // Creating input format for ParallelMachine
    final List<Tuple5<int, DateTime, int, DateTime, List<Duration>>> inputJobs = order!.orderJobs!
        .map((job) => Tuple5<int, DateTime, int, DateTime, List<Duration>>(
            job.jobId!,
            job.dueDate,
            job.priority,
            job.availableDate,
            job.sequence!.tasks!.map((task) => task.processingUnits).toList()))
        .toList();

    // Creating initial machine availability list
    final List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = machineEntities
        .map((machine) => Tuple2<int, List<Tuple2<DateTime, DateTime>>>(machine.id!, []))
        .toList();

    // TO DO LATER: Working schedule should be fetched from configuration, using 8-5 as default for now
    final output = ParallelMachine(
      order!.regDate,
      const Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0)),
      inputJobs,
      machines,
      rule,
    ).output;

    // Creating PlanningMachineEntity list grouped by machine ID
    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    for (var out in output) {
      final job = order!.orderJobs!.firstWhere((job) => job.jobId == out.value1);
      print('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ${out.value3} ::::  ${out.value4}');
      final task = PlanningTaskEntity(
        sequenceId: job.sequence!.id!,
        sequenceName: job.sequence!.name,
        taskId: job.sequence!.tasks![0].id!,
        numberProcess: 1, // To change later based on job's sequence amount
        startDate: out.value3,
        endDate: out.value4,
        retarded: out.value5 > Duration.zero,
      );

      if (!machineTasksMap.containsKey(out.value2)) {
        machineTasksMap[out.value2] = [];
      }
      machineTasksMap[out.value2]!.add(task);
    }

    final List<PlanningMachineEntity> machinesResult = machineTasksMap.entries
        .map((entry) => PlanningMachineEntity(
            entry.key,
            machineTypeName,
            entry.value,
          ))
        .toList();

    // Calculate Metrics
    final metrics = getMetricts(
      machinesResult,
      output.map((out) => Tuple3(out.value3, out.value4, out.value6)).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }


  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> singleMachineAdapter(int orderId, String rule) async{
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f){}, (or)=>order = or);
    if(order == null) return null;

    //getting the unique machine
    MachineEntity? machineEntity;
    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachine.fold((f){}, (m)=> machineEntity = m[0]);
    if(machineEntity == null) return null;

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
      0,
      order!.regDate,
      const Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0)),
      input,
      rule
    ).output;
    

    //get tasks
    final tasks = output.map((out)=>PlanningTaskEntity(
        sequenceId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.id!,
        sequenceName: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.name,
        taskId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.tasks![0].id!,
        numberProcess:  1,    //to change later depending on amount of a sequence
        startDate: out.value3,
        endDate: out.value4,
        retarded: !out.value4.isBefore(out.value5)
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
    final metrics = getMetricts(
      machinesResult, 
      output.map(
        (out)=> Tuple3(out.value3, out.value4,out.value5)
      )
      .toList()
    );

    return Tuple2(machinesResult, metrics);
  }


 


  Metrics getMetricts(List<PlanningMachineEntity> machines, List<Tuple3<DateTime, DateTime, DateTime>> jobsDates){  //(start date, end date, due date)
    machines.forEach((machine)=>machine.tasks.orderByStartDate());

    //IDLE METRIC (TIME OF MACHINES NOT BEING USED)
    Duration totalIdle = Duration.zero;
    for(final machine in machines){
      DateTime? previousEnd;
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
    final Duration idle = Duration(minutes:  totalIdle.inMinutes ~/ machines.length); 

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
    for(int i = 0; i < length; i++){
      for(int j = i+1; j < length; j++){
        if(this[i].startDate.isAfter(this[j].startDate)){
          PlanningTaskEntity auxStartDate = this[i];
          this[i] = this[j];
          this[j] = auxStartDate;
        }
      }
    }
  }
}