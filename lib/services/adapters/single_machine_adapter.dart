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

import '../../shared/utils/task_time_utils.dart';

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
    if (machineEntity == null) return null;

    //we get the machine type name
    final responseTypeMachine =
        await machineRepository.getMachineTypeName(machineTypeid);
    String machineTypeName =
        responseTypeMachine.fold((f) => "", (name) => name);

    //we get the input for the single machine
    // Expand jobs according to their `amount` (cantidad)
    final List<SingleMachineInput> input = [];
    for (final job in order.orderJobs!) {
      // Priority 1: Explicit per-job per-task per-machine time
      final taskId = job.sequence!.tasks![0].id!;
      final explicit = getExplicitProcessingDuration(job, taskId, machineEntity);
      
      late final Duration duration;
      if (explicit != null) {
        duration = explicit;
      } else {
        // Priority 2: Use task processingUnits directly, scaled only if machine is not standard (100%)
        if (machineEntity.processingPercentage == 100 || machineEntity.processingPercentage <= 0) {
          // Standard machine: use processingUnits as-is
          duration = job.sequence!.tasks![0].processingUnits;
        } else {
          // Non-standard machine: scale processingUnits by machine percentage
          final ratio = machineEntity.processingPercentage / 100.0;
          final scaledMillis = (job.sequence!.tasks![0].processingUnits.inMilliseconds * ratio).round();
          duration = Duration(milliseconds: scaledMillis);
        }
      }
      
      for (var i = 0; i < job.amount; i++) {
        input.add(SingleMachineInput(
          job.jobId!,
          duration,
          job.dueDate,
          job.priority,
          job.availableDate,
        ));
      }
    }

    //we get the output
        final output = SingleMachine(
          0, order.regDate, Tuple2(START_SCHEDULE, END_SCHEDULE), input, rule.toUpperCase())
        .output;

    final Map<int, int> jobCounter = {};
    final tasks = output.map((out) {
      //we get the job sequence for this job
      final jobSequence = order.orderJobs!
          .where((job) => job.jobId == out.jobId)
          .first
          .sequence!;
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1
          ? jobName
          : '$jobName (${current - 1})';
      return PlanningTaskEntity(
        sequenceId: jobSequence.id!,
        sequenceName: jobSequence.name,
        displayName: displayName,
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
      PlanningMachineEntity(
        machineEntity.id!,
        machineTypeName,
        tasks,
        scheduledInactivities: machineEntity.scheduledInactivities,
      )
    ];

    final metrics = getMetricts(
      machinesResult,
      output.map((out) {
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
        return Tuple4(job.availableDate, out.endDate, out.dueDate, job.priority);
      }).toList(),
    );
    return Tuple2(machinesResult, metrics);
  }
}
