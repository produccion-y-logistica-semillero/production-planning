import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
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

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> singleMachineAdapter(
      int orderId, String rule) async {
    //we get the current order
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (order) => order);
    if (order == null) return null;

    //we retrieve the machine type id of the first task, which we know is the one for all tasks
    int machineTypeid = order.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine =
        await machineRepository.getAllMachinesFromType(machineTypeid);
    MachineEntity? machineEntity =
        responseMachine.fold((f) => null, (m) => m[0]);

    //we get the machine type name
    final responseTypeMachine =
        await machineRepository.getMachineTypeName(machineTypeid);
    String machineTypeName =
        responseTypeMachine.fold((f) => "", (name) => name);

    //we get the input for the single machine
    final List<SingleMachineInput> input = order.orderJobs!
        .map((job) => SingleMachineInput(
            job.jobId!,
            ruleOf3(machineEntity!.processingTime,
                job.sequence!.tasks![0].processingUnits),
            job.dueDate,
            job.priority,
            job.availableDate))
        .toList();

    //we get the output
    final output = SingleMachine(
            0, order.regDate, Tuple2(START_SCHEDULE, END_SCHEDULE), input, rule)
        .output;

    final tasks = output.map((out) {
      //we get the job sequence for this job
      final jobSequence = order.orderJobs!
          .where((job) => job.jobId == out.jobId)
          .first
          .sequence!;
      return PlanningTaskEntity(
        sequenceId: jobSequence.id!,
        sequenceName: jobSequence.name,
        taskId: jobSequence.tasks![0].id!,
        numberProcess: 1, //to change later depending on amount of a sequence
        startDate: out.startDate,
        endDate: out.endDate,
        retarded: out.dueDate.isBefore(out.endDate),
        jobId: out.jobId,
        orderId: orderId,
      );
    }).toList();

    //since its single machine we know that there's only 1 planning machine
    final machinesResult = [
      PlanningMachineEntity(machineEntity!.id!, machineTypeName, tasks)
    ];

    final metrics = getMetricts(
        machinesResult,
        output
            .map((out) => Tuple3(out.startDate, out.endDate, out.dueDate))
            .toList());
    return Tuple2(machinesResult, metrics);
  }
}
