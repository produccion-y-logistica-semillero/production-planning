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
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f) {}, (or) => order = or);
    if (order == null) return null;
    // Getting all machines of the specified type
    final List<int> machinesIds = order!.orderJobs![0].sequence!.tasks!.map((t)=>t.machineTypeId).toList();
    final List<MachineEntity> machines =[];
    for(final m in machinesIds){
      final machinesSpecific = await machineRepository.getAllMachinesFromType(m);
      final machine = machinesSpecific.fold((_)=>MachineEntity.defaultMachine(), (r)=>r.first);
      machines.add(machine);
    }
    final List<Tuple4<int, DateTime, int, DateTime>> inputJobs = [];
    for(final j in order!.orderJobs!){
      inputJobs.add(Tuple4(j.jobId!, j.dueDate, j.priority, j.availableDate));
    }
    final List<List<Duration>> timeMatrix = [];
    for(final j in order!.orderJobs!){
      final List<Duration> jobDurations = [];
      int i = 0;
      for(final t in j.sequence!.tasks!){
        jobDurations.add(ruleOf3(machines[i].processingTime, t.processingUnits));
        i++;
      }
      timeMatrix.add(jobDurations);
    }
    final output = FlowShop(
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      timeMatrix,
      rule,
    ).output;
    final List<PlanningMachineEntity> planningMachines = [];
    for(final m in machines){
      planningMachines.add(PlanningMachineEntity(m.id!, m.name, []));
    }
    final List<DateTime> endDateJobs = [];
    for(final jr in output){
      int i = 0;
      DateTime? aux;
      for(final plan in jr.value2){
        if(aux == null || aux.isBefore(plan.value2)){
          aux = plan.value2;
        }
        planningMachines[i].tasks.add(
          PlanningTaskEntity(
            sequenceId: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.id!, 
            sequenceName: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.name!, 
            taskId: order!.orderJobs!.where((j)=>j.jobId == jr.value1).first.sequence!.tasks![i].id!, 
            numberProcess: i+1, 
            startDate: plan.value1, 
            endDate: plan.value2, 
            retarded: false, 
            orderId: orderId, 
            jobId: jr.value1
            )
          );
        i++;
      }
      endDateJobs.add(aux!);
    }
    final List<Tuple3<DateTime, DateTime, DateTime>> jobsDates = [];
    int i = 0;
    for(final j in order!.orderJobs!){
      jobsDates.add(Tuple3(j.availableDate, endDateJobs[i], j.dueDate));
      i++;
    }
    final metrics = getMetricts(
      planningMachines,
      jobsDates,
    );
    return Tuple2(planningMachines, metrics);
  }
}