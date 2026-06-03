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
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/utils/changeover_matrix_utils.dart';
import '../../entities/machine_entity.dart';
import '../../entities/machine_inactivity_entity.dart';
import '../../shared/utils/machine_downtime_utils.dart';
import '../../shared/utils/task_time_utils.dart';

class ParallelMachineAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  ParallelMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(
      int orderId, String rule) async {
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (or) => or);
    if (order == null) return null;

    int machineTypeid = order.orderJobs![0].sequence!.tasks![0].machineTypeId;

    final responseMachines =
        await machineRepository.getAllMachinesFromType(machineTypeid);
    List<MachineEntity>? machineEntities =
        responseMachines.fold((f) => null, (machines) => machines);
    if (machineEntities == null || machineEntities.isEmpty) return null;

    final sequenceIds = order.orderJobs!
        .where((j) => j.sequence?.id != null)
        .map((j) => j.sequence!.id!)
        .toSet();
    final changeoverMatrix = await loadMergedChangeoverMatrix(
      setupTimeService,
      machineEntities,
      sequenceIds,
    );
    final stateSetupMatrix =
        buildMachineStateSetupMatrix(machineEntities, order.setupTimeMatrix);
    final jobStates = buildJobMachineStates(order.orderJobs!, machineEntities);
    final jobInterruptionPolicies =
        buildJobInterruptionPolicies(order.orderJobs!);

    final machineInactivitiesMap = <int, List<MachineInactivityEntity>>{};
    final machineContinueCapacityMap = <int, int>{};
    final machineRestTimeMap = <int, Duration?>{};
    buildMachineDowntimeMaps(
      machineEntities,
      inactivities: machineInactivitiesMap,
      continueCapacity: machineContinueCapacityMap,
      restTime: machineRestTimeMap,
    );

    final List<ParallelInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      Map<int, Duration> durationsInMachines = {};
      for (final machine in machineEntities) {
        final task = job.sequence!.tasks![0];
        final explicit = getExplicitProcessingDuration(job, task.id!, machine);
        if (explicit != null) {
          durationsInMachines[machine.id!] = explicit;
        } else {
          if (machine.processingPercentage == 100 ||
              machine.processingPercentage <= 0) {
            durationsInMachines[machine.id!] = task.processingUnits;
          } else {
            final ratio = machine.processingPercentage / 100.0;
            final scaledMillis =
                (task.processingUnits.inMilliseconds * ratio).round();
            durationsInMachines[machine.id!] =
                Duration(milliseconds: scaledMillis);
          }
        }
      }
      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(ParallelInput(
          job.jobId!,
          job.sequence!.id!,
          job.dueDate,
          job.priority,
          job.availableDate,
          durationsInMachines,
        ));
      }
    }

    final Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
    for (final machine in machineEntities) {
      machines[machine.id!] = [];
    }

    final output = ParallelMachine(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machines,
      rule.toUpperCase(),
      changeoverMatrix: changeoverMatrix,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
      jobInterruptionPolicies: jobInterruptionPolicies,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity: machineContinueCapacityMap,
      machineRestTime: machineRestTimeMap,
    ).output;

    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    final Map<int, int> jobCounter = {};
    for (var out in output) {
      final job = order.orderJobs!.firstWhere((job) => job.jobId == out.jobId);
      final jobSequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName =
          current == 1 ? jobName : '$jobName (${current - 1})';
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

      machineTasksMap.putIfAbsent(out.machineId, () => []).add(task);
    }

    final List<PlanningMachineEntity> machinesResult =
        machineTasksMap.entries.map((entry) {
      final machine = machineEntities.where((m) => m.id == entry.key).first;
      return PlanningMachineEntity(
        machine.id!,
        machine.name,
        entry.value,
        scheduledInactivities: machine.scheduledInactivities,
      );
    }).toList();

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
