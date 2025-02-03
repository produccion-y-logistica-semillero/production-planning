import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/parallel_machine.dart';
import 'package:production_planning/services/algorithms/single_machine.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/shared/functions/functions.dart';

import '../../entities/machine_entity.dart';

class SingleMachineAdapter {

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  SingleMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> singleMachineAdapter(int orderId, String rule) async{
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f){}, (or)=>order = or);
    if(order == null) return null;

    MachineEntity? machineEntity;
    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachine.fold((f){}, (m)=> machineEntity = m[0]);
    if(machineEntity == null) return null;

    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f){}, (name)=>machineTypeName = name);

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

    final output = SingleMachine(
      0,
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      input,
      rule
    ).output;
    
    final tasks = output.map((out)=>PlanningTaskEntity(
        sequenceId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.id!,
        sequenceName: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.name,
        taskId: order!.orderJobs!.where((job)=> job.jobId == out.value1).first.sequence!.tasks![0].id!,
        numberProcess:  1,    //to change later depending on amount of a sequence
        startDate: out.value3,
        endDate: out.value4,
        retarded: !out.value4.isBefore(out.value5),
        jobId: out.value1,
        orderId: orderId,
      )
    ).toList();

    final machinesResult = [
      PlanningMachineEntity(
        machineEntity!.id!,
        machineTypeName,
        tasks
      )
    ];

    final metrics = getMetricts(
      machinesResult, 
      output.map(
        (out)=> Tuple3(out.value3, out.value4,out.value5)
      )
      .toList()
    );

    return Tuple2(machinesResult, metrics);
  }
}