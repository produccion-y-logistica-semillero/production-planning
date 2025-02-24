import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
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
    //getting full order
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) =>null, (or) => or);
    if (order == null) return null;

    //we get all machines from this machine type
    int machineTypeid = order.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachines = await machineRepository.getAllMachinesFromType(machineTypeid);
    List<MachineEntity>? machineEntities = responseMachines.fold((f)=>null, (machines) => machines);
    if (machineEntities == null) return null;

    //we create the input 
    final List<ParallelInput> inputJobs = [];
    for(final job in order.orderJobs!){
      Map<int, Duration> durationsInMachines= {};
      //we get the duration it would take on each machine and add it to the map
      for(final machine in machineEntities){
        final task = job.sequence!.tasks![0];
        durationsInMachines[machine.id!] = ruleOf3(machine.processingTime, task.processingUnits);
      }
      inputJobs.add(ParallelInput(
        job.jobId!, job.dueDate, job.priority, job.availableDate, durationsInMachines)
      );
    } 

    //we create an the empy input struct for machines
    final Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
    for(final machine in machineEntities){
      machines[machine.id!] = [];
    }

    //we get the output, the result of the algorithm
    final output = ParallelMachine(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machines,
      rule,
    ).output;

    //we transform the output to planning machines
    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};
    for (var out in output) {
      final job = order.orderJobs!.firstWhere((job) => job.jobId == out.jobId);
      final jobSequence =job.sequence!;
      final task = PlanningTaskEntity(
        sequenceId: jobSequence.id!,
        sequenceName: jobSequence.name,
        taskId: jobSequence.tasks![0].id!,
        numberProcess: 1,
        startDate: out.startDate,
        endDate: out.endDate,
        retarded: out.dueDate.isBefore(out.dueDate),
        jobId: job.jobId!,
        orderId: orderId,
      );

      if (!machineTasksMap.containsKey(out.machineId)) {
        machineTasksMap[out.machineId] = [];
      }
      machineTasksMap[out.machineId]!.add(task);
    }

    final List<PlanningMachineEntity> machinesResult = machineTasksMap.entries
        .map((entry) => PlanningMachineEntity(
            entry.key,
            machineEntities.where((m)=>m.id == entry.key).first.name,
            entry.value,
          ))
        .toList();

    final metrics = getMetricts(
      machinesResult,
      output.map((out) => Tuple3(out.startDate, out.endDate, out.dueDate)).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }
}