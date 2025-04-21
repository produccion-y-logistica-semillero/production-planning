import 'dart:developer' as developer;

import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/shared/functions/functions.dart';
import '../../entities/machine_entity.dart';

class FlowShopAdapter {

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  FlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flowShopAdapter(int orderId, String rule) async {
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) =>null, (or) => or);
    if (order == null) return null;

    //We get all machines
    final List<int> machinesTypesIds = order.orderJobs![0].sequence!.tasks!.map((t)=>t.machineTypeId).toList();
    final List<MachineEntity> machines =[];
    for(final typeId in machinesTypesIds){
      final machinesSpecific = await machineRepository.getAllMachinesFromType(typeId);
      final machineList = machinesSpecific.fold((_) => null, (m) => m);
      if (machineList == null || machineList.isEmpty) return null;
      machines.addAll(machineList);
      
    }

    //we create the input
    final List<FlowShopInput> inputJobs = [];
    for(final job in order.orderJobs!){
      final Map<int, Duration> taskTimes = {};
      final List<Tuple2<int, int>> taskSequence = [];
      //iterating over all tasks, and for each one, we get the time it takes on the machine we have for the machine type
      for(final task in job.sequence!.tasks!){
       // print("searching ${task.machineTypeId}");
        final machineOfTask = machines.where((m)=>m.machineTypeId==task.machineTypeId).first;
        taskTimes[task.id!] = ruleOf3(machineOfTask.processingTime, task.processingUnits);
        taskSequence.add(Tuple2(task.id!, task.machineTypeId));
      }
      inputJobs.add(FlowShopInput(
        job.jobId!, 
        job.dueDate, 
        job.priority, 
        job.availableDate, 
        taskSequence,
        taskTimes,
      ));
    }

    //we create the sequence
    final Map<int, DateTime> machinesAvailability= {};
    for(final task in order.orderJobs!.first.sequence!.tasks!){
      machinesAvailability[task.machineTypeId] = DateTime.now();
    }

    //we call the algorithm and receive the output
    final output = FlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule
    ).output;


    //transform to planning machines
    final List<PlanningMachineEntity> planningMachines = [];
    for(final m in machines){
      planningMachines.add(PlanningMachineEntity(m.machineTypeId!, m.name, []));
    }

    for(final out in output){
      int i = 0;
      final jobSequence = order.orderJobs!.where((j)=>j.jobId == out.jobId).first.sequence!;
      for(final machineScheduling in out.machinesScheduling.entries){
        //we get the planning machine where this task belongs
        final planningMachineEntity = planningMachines.where((pm) => pm.machineId == machineScheduling.key).first;
        final DateTime taskStart = machineScheduling.value.value2.startDate;
        final DateTime taskEnd = machineScheduling.value.value2.endDate;
        final planningTask = PlanningTaskEntity(
          sequenceId: jobSequence.id!, 
          sequenceName: jobSequence.name, 
          taskId:  machineScheduling.value.value1, 
          numberProcess: i++, 
          startDate: taskStart, 
          endDate: taskEnd,
          retarded: out.dueDate.isBefore(out.endTime), 
          orderId: orderId, 
          jobId: out.jobId
        );
        planningMachineEntity.tasks.add(planningTask);
      }
    }
    //we get the metrics
    final List<Tuple3<DateTime, DateTime, DateTime>> jobsDates = [];
    for(final out in output){
      jobsDates.add(Tuple3(out.startDate, out.endTime, out.dueDate));
    }



    
    final metrics = getMetricts(
      planningMachines,
      jobsDates,
    );
    return Tuple2(planningMachines, metrics);
  }
}