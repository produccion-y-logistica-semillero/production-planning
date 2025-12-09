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
import '../../shared/utils/task_time_utils.dart';

class ParallelMachineAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  ParallelMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });


  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(
      int orderId, String rule) async {
    //getting full order
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (or) => or);
    if (order == null) return null;

    //we get all machines from this machine type
    int machineTypeid = order.orderJobs![0].sequence!.tasks![0].machineTypeId;

    final responseMachines =
        await machineRepository.getAllMachinesFromType(machineTypeid);
    List<MachineEntity>? machineEntities =
        responseMachines.fold((f) => null, (machines) => machines);
    if (machineEntities == null) return null;

    //we create the input and expand jobs by their `amount` (cantidad)
    final List<ParallelInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      Map<int, Duration> durationsInMachines = {};
      //we get the duration it would take on each machine and add it to the map
      for (final machine in machineEntities) {
        final task = job.sequence!.tasks![0];
        // prefer explicit per-job time for this task-machine
        final explicit = getExplicitProcessingDuration(job, task.id!, machine);
        // Calculate duration from machine percentage (100% = 1 hour base)
        final baseDuration = Duration(
            minutes: (60 * machine.processingPercentage / 100).round());
        durationsInMachines[machine.id!] =
            explicit ?? ruleOf3(baseDuration, task.processingUnits);
      }
      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(ParallelInput(job.jobId!, job.dueDate, job.priority,
            job.availableDate, durationsInMachines));
      }
    }

    //we create an the empy input struct for machines
    final Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
    for (final machine in machineEntities) {

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

    final Map<int, int> jobCounter = {};
    for (var out in output) {
      final job = order.orderJobs!.firstWhere((job) => job.jobId == out.jobId);
      final jobSequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final displayName = current == 1
          ? (job.sequence?.name ?? jobSequence.name)
          : '${job.sequence?.name ?? jobSequence.name}.${current - 1}';
      final task = PlanningTaskEntity(
        sequenceId: jobSequence.id!,
        sequenceName: jobSequence.name,
        displayName: displayName,
        taskId: jobSequence.tasks![0].id!,
        numberProcess: current,
        startDate: out.startDate,
        endDate: out.endDate,
        retarded: out.dueDate.isBefore(out.endDate),

        jobId: job.jobId!,
        orderId: orderId,
      );

      if (!machineTasksMap.containsKey(out.machineId)) {
        machineTasksMap[out.machineId] = [];
      }
      machineTasksMap[out.machineId]!.add(task);
    }


    final List<PlanningMachineEntity> machinesResult =
        machineTasksMap.entries.map((entry) {
      final machine = machineEntities.where((m) => m.id == entry.key).first;
      return PlanningMachineEntity(
        entry.key,
        machine.name,
        entry.value,
        scheduledInactivities: machine.scheduledInactivities,
      );
    }).toList();

    final metrics = getMetricts(
      machinesResult,
      output.map((out) {
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
        return Tuple4(out.startDate, out.endDate, out.dueDate, job.priority);
      }).toList(),

    );

    return Tuple2(machinesResult, metrics);
  }

}

