// lib/services/adapters/flexible_flow_shop_adapter.dart
//
// Changes from merged version:
//   • Accepts SetupTimeService and attaches the in-memory matrix cache to the
//     OrderEntity before calling the algorithm.
//   • buildMachineStateSetupMatrix / buildJobMachineStates imported from
//     shared/functions/functions.dart.

import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import '../../shared/utils/task_time_utils.dart';

class FlexibleFlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService; // <── added

  FlexibleFlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  int toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flexibleFlowShopAdapter(
      int orderId, String rule) async {
    // ── 1. Load order and attach setup matrices ────────────────────────────
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? baseOrder = responseOrder.fold((f) => null, (o) => o);
    if (baseOrder == null || baseOrder.orderJobs == null) return null;

    final attachedSetupTimeMatrix = <String, Map<String, Map<String, int>>>{};
    if (baseOrder.setupTimeMatrix != null) {
      attachedSetupTimeMatrix.addAll(baseOrder.setupTimeMatrix!);
    }
    attachedSetupTimeMatrix.addAll(setupTimeService.allCachedMatrices);

    final OrderEntity order = OrderEntity(
      baseOrder.orderId,
      baseOrder.regDate,
      baseOrder.orderJobs,
      setupTimeMatrix:
          attachedSetupTimeMatrix.isNotEmpty ? attachedSetupTimeMatrix : null,
    );

    // ── 2. Resolve machines ────────────────────────────────────────────────
    final List<int> machineTypeIds = order.orderJobs!
        .expand((job) => job.sequence!.tasks!.map((t) => t.machineTypeId))
        .toSet()
        .toList();
    final List<MachineEntity> machines = [];
    for (final typeId in machineTypeIds) {
      final responseMachines =
          await machineRepository.getAllMachinesFromType(typeId);
      final machineList = responseMachines.fold((_) => null, (m) => m);
      if (machineList == null || machineList.isEmpty) return null;
      machines.addAll(machineList);
    }

    // ── 3. Build setup data ────────────────────────────────────────────────
    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machines);

    // ── 4. Build FlexibleFlowInput list ───────────────────────────────────
    final List<FlexibleFlowInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final List<Tuple2<int, Map<int, Duration>>> taskSequence = [];
      for (final task in job.sequence!.tasks!) {
        final Map<int, Duration> machineDurations = {};
        for (final machine
            in machines.where((m) => m.machineTypeId == task.machineTypeId)) {
          final explicit =
              getExplicitProcessingDuration(job, task.id!, machine);
          if (explicit != null) {
            machineDurations[machine.id!] = explicit;
          } else if (machine.processingPercentage == 100 ||
              machine.processingPercentage <= 0) {
            machineDurations[machine.id!] = task.processingUnits;
          } else {
            final ratio = machine.processingPercentage / 100.0;
            final scaledMillis =
                (task.processingUnits.inMilliseconds * ratio).round();
            machineDurations[machine.id!] =
                Duration(milliseconds: scaledMillis);
          }
        }
        taskSequence.add(Tuple2(task.id!, machineDurations));
      }
      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(FlexibleFlowInput(
          job.jobId!,
          job.dueDate,
          job.priority,
          job.availableDate,
          taskSequence,
        ));
      }
    }

    // ── 5. Initial machine availability ───────────────────────────────────
    final Map<int, DateTime> machinesAvailability = {
      for (final machine in machines) machine.id!: order.regDate,
    };

    // ── 6. Run algorithm ──────────────────────────────────────────────────
    List<FlexibleFlowOutput> output;
    try {
      output = FlexibleFlowShop(
        order.regDate,
        Tuple2(START_SCHEDULE, END_SCHEDULE),
        inputJobs,
        machinesAvailability,
        rule.toUpperCase(),
        stateSetupMatrix: stateSetupMatrix,
        jobStates: jobStates,
      ).output;
    } catch (error, stack) {
      print('FlexibleFlowShopAdapter error: $error');
      print(stack.toString());
      return null;
    }

    // Crear mapa de inactividades por máquina
    final Map<int, List<MachineInactivityEntity>> machineInactivitiesMap = {};
    final Map<int, int> machineContinueCapacityMap = {};
    final Map<int, Duration?> machineRestTimeMap = {};
    for (final machine in machines) {
      machineInactivitiesMap[machine.id!] = machine.scheduledInactivities;
      machineContinueCapacityMap[machine.id!] = machine.continueCapacity;
      machineRestTimeMap[machine.id!] =
          Duration(minutes: (60 * machine.restPercentage / 100).round());
    }

    // Ejecutar el algoritmo Flexible Flow Shop
    final output = FlexibleFlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity: machineContinueCapacityMap,
      machineRestTime: machineRestTimeMap,
    ).output;

    // Transformar la salida en PlanningMachineEntity
    final List<PlanningMachineEntity> planningMachines = [];
    for (final machine in machines) {
      planningMachines.add(PlanningMachineEntity(
        machine.id!,
        machine.name,
        [],
        scheduledInactivities: machine.scheduledInactivities,
      ));
    }

    final Map<int, int> jobCounter = {};
    for (final out in output) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final sequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1 ? jobName : '$jobName (${current - 1})';

      for (final taskEntry in out.scheduling.entries) {
        final taskId = taskEntry.key;
        final machineId = taskEntry.value.value1;
        final timeRange = taskEntry.value.value2;
        final task = sequence.tasks!.firstWhere((t) => t.id == taskId);

        final jobName = job.jobName ?? 'Job ${out.jobId}';
        final displayName = current == 1
            ? jobName
            : '$jobName (${current - 1})';

        final planningTask = PlanningTaskEntity(
          sequenceId: sequence.id!,
          sequenceName: sequence.name,
          displayName: displayName,
          taskId: task.id!,
          numberProcess: taskId,
          startDate: timeRange.startDate,
          endDate: timeRange.endDate,
          retarded: out.dueDate.isBefore(timeRange.endDate),
          jobId: job.jobId!,
          orderId: orderId,
        );

        planningMachines
            .firstWhere((m) => m.machineId == machineId)
            .tasks
            .add(planningTask);
      }
    }

    // ── 8. Metrics ────────────────────────────────────────────────────────
    final jobsDates = output.map((out) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      return Tuple5(out.jobId, out.startDate, out.endTime, out.dueDate,
          job.priority);
    }).toList();

    return Tuple2(
        planningMachines, getMetricts(planningMachines, jobsDates));
  }
}
