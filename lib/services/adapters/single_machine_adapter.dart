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
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/utils/changeover_matrix_utils.dart';

import '../../entities/machine_entity.dart';
import '../../entities/machine_inactivity_entity.dart';
import '../../shared/utils/machine_downtime_utils.dart';
import '../../shared/utils/task_time_utils.dart';

class SingleMachineAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  SingleMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> singleMachineAdapter(
      int orderId, String rule) async {
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (order) => order);
    if (order == null) return null;

    int machineTypeid = order.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine =
        await machineRepository.getAllMachinesFromType(machineTypeid);
    MachineEntity? machineEntity =
        responseMachine.fold((f) => null, (m) => m[0]);
    if (machineEntity == null || machineEntity.id == null) return null;

    final responseTypeMachine =
        await machineRepository.getMachineTypeName(machineTypeid);
    String machineTypeName =
        responseTypeMachine.fold((f) => "", (name) => name);

    final sequenceIds = order.orderJobs!
        .where((j) => j.sequence?.id != null)
        .map((j) => j.sequence!.id!)
        .toSet();
    final changeoverMatrix = await loadMergedChangeoverMatrix(
      setupTimeService,
      [machineEntity],
      sequenceIds,
    );
    final stateSetupMatrix =
        buildMachineStateSetupMatrix([machineEntity], order.setupTimeMatrix);
    final jobStates = buildJobMachineStates(order.orderJobs!, [machineEntity]);
    final jobInterruptionPolicies =
        buildJobInterruptionPolicies(order.orderJobs!);

    final machineInactivitiesMap = <int, List<MachineInactivityEntity>>{};
    final machineContinueCapacityMap = <int, int>{};
    final machineRestTimeMap = <int, Duration?>{};
    buildMachineDowntimeMaps(
      [machineEntity],
      inactivities: machineInactivitiesMap,
      continueCapacity: machineContinueCapacityMap,
      restTime: machineRestTimeMap,
    );

    final List<SingleMachineInput> input = [];
    for (final job in order.orderJobs!) {
      final taskId = job.sequence!.tasks![0].id!;
      final explicit = getExplicitProcessingDuration(job, taskId, machineEntity);

      late final Duration duration;
      if (explicit != null) {
        duration = explicit;
      } else {
        if (machineEntity.processingPercentage == 100 ||
            machineEntity.processingPercentage <= 0) {
          duration = job.sequence!.tasks![0].processingUnits;
        } else {
          final ratio = machineEntity.processingPercentage / 100.0;
          final scaledMillis =
              (job.sequence!.tasks![0].processingUnits.inMilliseconds * ratio)
                  .round();
          duration = Duration(milliseconds: scaledMillis);
        }
      }

      for (var i = 0; i < job.amount; i++) {
        input.add(SingleMachineInput(
          job.jobId!,
          job.sequence!.id!,
          duration,
          job.dueDate,
          job.priority,
          job.availableDate,
        ));
      }
    }

    final output = SingleMachine(
      machineEntity.id!,
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      input,
      rule.toUpperCase(),
      changeoverMatrix: changeoverMatrix,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
      jobInterruptionPolicies: jobInterruptionPolicies,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity:
          machineContinueCapacityMap[machineEntity.id!] ?? 0,
      machineRestTime: machineRestTimeMap[machineEntity.id!],
    ).output;

    final Map<int, int> jobCounter = {};
    final tasks = output.map((out) {
      final jobSequence = order.orderJobs!
          .where((job) => job.jobId == out.jobId)
          .first
          .sequence!;
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName =
          current == 1 ? jobName : '$jobName (${current - 1})';
      return PlanningTaskEntity(
        sequenceId: jobSequence.id!,
        sequenceName: jobSequence.name,
        displayName: displayName,
        taskId: jobSequence.tasks![0].id!,
        numberProcess: 1,
        startDate: out.startDate,
        endDate: out.endDate,
        retarded: out.dueDate.isBefore(out.endDate),
        jobId: out.jobId,
        orderId: orderId,
      );
    }).toList();

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
