import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/2_orders/domain/algorithms/single_machine.dart';
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
   /* PlanningMachineEntity machine1 = PlanningMachineEntity(1, 'Horno');
    PlanningMachineEntity machine2 = PlanningMachineEntity(2, 'Estufa');
    PlanningMachineEntity machine3 = PlanningMachineEntity(3, 'Liquadora');
    PlanningMachineEntity machine4 = PlanningMachineEntity(4, 'Nevera');

    //adding 1 unit of sequence galleta
    machine1.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 1,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 8),
        endDate: DateTime(2023, 9, 1, 17)));
    machine2.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 2,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 17),
        endDate: DateTime(2023, 9, 1, 22)));
    machine3.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 3,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 22),
        endDate: DateTime(2023, 9, 2, 10)));

    //adding 1 unit of sequence Pan
    machine4.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 1,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 8),
        endDate: DateTime(2023, 9, 2, 13)));
    machine1.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 2,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 13),
        endDate: DateTime(2023, 9, 2, 16)));
    machine2.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 3,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 16),
        endDate: DateTime(2023, 9, 2, 21)));
        return Right([
                machine1,
                machine2,
                machine3,
                machine4,
              ]);*/
  }

  Future<List<PlanningMachineEntity>> singleMachineAdapter(int orderId, String rule) async{
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
    final tasks = SingleMachine(
      order!.regDate,
      const Tuple2(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 17, minute: 0)),
      input,
      rule
    ).output.map((out)=>PlanningTaskEntity(
        sequenceId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.id!,
        sequenceName: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.name,
        taskId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.tasks![0].id!,
        numberProcess:  1,    //to change later depending on amount of a sequence
        startDate: out.value2,
        endDate: out.value3,
        retarded: !out.value2.isBefore(out.value4)
      )
    ).toList();
    print(tasks.length);
    return [PlanningMachineEntity(
      machineEntity!.id!,
      machineTypeName,
      tasks
    )];
  }
}