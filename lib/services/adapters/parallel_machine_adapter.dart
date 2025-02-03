import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/algorithms/parallel_machine.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/shared/functions/functions.dart';

import '../../entities/machine_entity.dart';

class ParallelMachineAdapter {

  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  ParallelMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(int orderId, String rule) async {
    OrderEntity? order;
    final responseOrder = await orderRepository.getFullOrder(orderId);
    responseOrder.fold((f) {}, (or) => order = or);
    if (order == null) return null;

    int machineTypeid = order!.orderJobs![0].sequence!.tasks![0].machineTypeId;
    List<MachineEntity> machineEntities = [];
    final responseMachines = await machineRepository.getAllMachinesFromType(machineTypeid);
    responseMachines.fold((f) {}, (m) => machineEntities = m);
    if (machineEntities.isEmpty) return null;

    String machineTypeName = "";
    final responseTypeMachine = await machineRepository.getMachineTypeName(machineTypeid);
    responseTypeMachine.fold((f) {}, (name) => machineTypeName = name);

    final List<Tuple5<int, DateTime, int, DateTime, List<Duration>>> inputJobs = order!.orderJobs!
        .map((job) => Tuple5<int, DateTime, int, DateTime, List<Duration>>(
            job.jobId!,
            job.dueDate,
            job.priority,
            job.availableDate,
            job.sequence!.tasks!.map((task) => task.processingUnits).toList()))
        .toList();

    final List<Tuple2<int, List<Tuple2<DateTime, DateTime>>>> machines = machineEntities
        .map((machine) => Tuple2<int, List<Tuple2<DateTime, DateTime>>>(machine.id!, []))
        .toList();

    final output = ParallelMachine(
      order!.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machines,
      rule,
    ).output;

    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    for (var out in output) {
      final job = order!.orderJobs!.firstWhere((job) => job.jobId == out.value1);
      final task = PlanningTaskEntity(
        sequenceId: job.sequence!.id!,
        sequenceName: job.sequence!.name,
        taskId: job.sequence!.tasks![0].id!,
        numberProcess: 1,
        startDate: out.value3,
        endDate: out.value4,
        retarded: out.value5 > Duration.zero,
        jobId: job.jobId!,
        orderId: orderId,
      );

      if (!machineTasksMap.containsKey(out.value2)) {
        machineTasksMap[out.value2] = [];
      }
      machineTasksMap[out.value2]!.add(task);
    }
    machineEntities.forEach((m)=>print(m.id));
    final List<PlanningMachineEntity> machinesResult = machineTasksMap.entries
        .map((entry) => PlanningMachineEntity(
            entry.key,
            machineEntities.where((m)=>m.id == entry.key).first.name,
            entry.value,
          ))
        .toList();

    final metrics = getMetricts(
      machinesResult,
      output.map((out) => Tuple3(out.value3, out.value4, out.value6)).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }
}