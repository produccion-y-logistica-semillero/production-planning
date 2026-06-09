// lib/services/adapters/flow_shop_Adapter.dart
//
// Changes from merged version:
//   • Accepts SetupTimeService and uses OrdersService helper to load the
//     order WITH the in-memory setup matrices attached.
//   • buildMachineStateSetupMatrix / buildJobMachineStates are imported from
//     shared/functions/functions.dart (where they now live).
//   • _buildDefaultChangeoverMatrix now produces ZERO durations so it no
//     longer corrupts the Gantt when no sequence-based setup times are stored
//     in the DB.  The state-based matrix takes precedence via _getSetupDuration.

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
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import '../../entities/machine_entity.dart';
import '../../shared/utils/task_time_utils.dart';

class FlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService; // <── added

  FlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flowShopAdapter(
    int orderId,
    String rule, {
    Map<int, Map<int?, Map<int, Duration>>>? changeoverMatrix,
  }) async {
    // ── 1. Load order WITH setup matrices attached ─────────────────────────
    // We use the orderRepository directly here since OrdersService would
    // create a circular dependency.  Instead we manually attach the cache.
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? baseOrder = responseOrder.fold((f) => null, (or) => or);
    if (baseOrder == null) return null;

    // Attach cached matrices to the entity, but preserve any persisted
    // setup matrix values already loaded from the order.
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
      final machinesSpecific =
          await machineRepository.getAllMachinesFromType(typeId);
      final machineList = machinesSpecific.fold((_) => null, (m) => m);
      if (machineList == null || machineList.isEmpty) return null;
      machines.addAll(machineList);
    }

    // ── 3. Build setup data ────────────────────────────────────────────────
    final sequenceIds = order.orderJobs!
        .where((job) => job.sequence != null && job.sequence!.id != null)
        .map((job) => job.sequence!.id!)
        .toSet();

    // Default changeover matrix uses ZERO durations — the state-based matrix
    // takes precedence, so non-zero defaults would add spurious setup time.
    final defaultMatrix =
        _buildZeroChangeoverMatrix(machines, sequenceIds);
    final mergedMatrix =
        _mergeChangeoverMatrices(defaultMatrix, changeoverMatrix);

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machines);

    // ── 4. Build FlowShopInput list ────────────────────────────────────────
    final List<FlowShopInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final Map<int, Duration> taskTimes = {};
      final List<Tuple2<int, int>> taskSequence = [];
      for (final task in job.sequence!.tasks!) {
        final machineOfTask =
            machines.firstWhere((m) => m.machineTypeId == task.machineTypeId);
        final explicit =
            getExplicitProcessingDuration(job, task.id!, machineOfTask);
        if (explicit != null) {
          taskTimes[task.id!] = explicit;
        } else if (machineOfTask.processingPercentage == 100 ||
            machineOfTask.processingPercentage <= 0) {
          taskTimes[task.id!] = task.processingUnits;
        } else {
          final ratio = machineOfTask.processingPercentage / 100.0;
          final scaledMillis =
              (task.processingUnits.inMilliseconds * ratio).round();
          taskTimes[task.id!] = Duration(milliseconds: scaledMillis);
        }
        taskSequence.add(Tuple2(task.id!, machineOfTask.id!));
      }
      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(FlowShopInput(
          job.jobId!,
          job.sequence!.id!,
          job.dueDate,
          job.priority,
          job.availableDate,
          taskSequence,
          taskTimes,
        ));
      }
    }

    // ── 5. Initial machine availability ───────────────────────────────────
    final Map<int, DateTime> machinesAvailability = {
      for (final m in machines)
        if (m.id != null) m.id!: order.regDate,
    };

    // ── 6. Run algorithm ──────────────────────────────────────────────────
    final output = FlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule.toUpperCase(),
      changeoverMatrix: mergedMatrix,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
    ).output;

    // ── 7. Build PlanningMachineEntity list ────────────────────────────────
    final List<PlanningMachineEntity> planningMachines = [
      for (final m in machines)
        if (m.id != null)
          PlanningMachineEntity(
            m.id!,
            m.name,
            [],
            scheduledInactivities: m.scheduledInactivities,
          ),
    ];

    final Map<int, int> jobCounter = {};
    for (final out in output) {
      int i = 0;
      final job =
          order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final jobSequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1 ? jobName : '$jobName (${current - 1})';

      for (final machineScheduling in out.machinesScheduling.entries) {
        final planningMachineEntity = planningMachines
            .firstWhere((pm) => pm.machineId == machineScheduling.key);
        final taskStart = machineScheduling.value.value2.startDate;
        final taskEnd = machineScheduling.value.value2.endDate;
        planningMachineEntity.tasks.add(PlanningTaskEntity(
          sequenceId: jobSequence.id!,
          sequenceName: jobSequence.name,
          displayName: displayName,
          taskId: machineScheduling.value.value1,
          numberProcess: i++,
          startDate: taskStart,
          endDate: taskEnd,
          retarded: out.dueDate.isBefore(out.endTime),
          orderId: orderId,
          jobId: out.jobId,
        ));
      }
    }

    // ── 8. Metrics ────────────────────────────────────────────────────────
    final jobsDates = output.map((out) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      return Tuple5(out.jobId, out.startDate, out.endTime, out.dueDate,
          job.priority);
    }).toList();

    return Tuple2(planningMachines, getMetricts(planningMachines, jobsDates));
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Returns a changeover matrix with Duration.zero for every transition.
  /// Used as the base so that if no DB or state-based setup times are
  /// configured, no spurious delay appears in the Gantt.
  Map<int, Map<int?, Map<int, Duration>>> _buildZeroChangeoverMatrix(
    List<MachineEntity> machines,
    Set<int> sequenceIds,
  ) {
    final result = <int, Map<int?, Map<int, Duration>>>{};
    for (final machine in machines) {
      if (machine.id == null) continue;
      final Map<int, Duration> zeroTargets = {
        for (final seqId in sequenceIds) seqId: Duration.zero,
      };
      result[machine.id!] = {
        null: Map.from(zeroTargets),
        for (final previous in sequenceIds)
          previous: Map.from(zeroTargets),
      };
    }
    return result;
  }

  Map<int, Map<int?, Map<int, Duration>>> _mergeChangeoverMatrices(
    Map<int, Map<int?, Map<int, Duration>>> baseMatrix,
    Map<int, Map<int?, Map<int, Duration>>>? overrideMatrix,
  ) {
    if (overrideMatrix == null || overrideMatrix.isEmpty) return baseMatrix;

    final result = <int, Map<int?, Map<int, Duration>>>{};
    final machineIds = <int>{...baseMatrix.keys, ...overrideMatrix.keys};
    for (final machineId in machineIds) {
      final baseMachine = baseMatrix[machineId] ?? {};
      final overrideMachine = overrideMatrix[machineId] ?? {};
      final previousIds = <int?>{...baseMachine.keys, ...overrideMachine.keys};
      final mergedMachine = <int?, Map<int, Duration>>{};
      for (final previousId in previousIds) {
        final baseDurations = baseMachine[previousId] ?? {};
        final overrideDurations = overrideMachine[previousId] ?? {};
        final currentIds = <int>{...baseDurations.keys, ...overrideDurations.keys};
        final mergedDurations = <int, Duration>{};
        for (final currentId in currentIds) {
          mergedDurations[currentId] = overrideDurations.containsKey(currentId)
              ? overrideDurations[currentId]!
              : baseDurations[currentId]!;
        }
        mergedMachine[previousId] = mergedDurations;
      }
      result[machineId] = mergedMachine;
    }
    return result;
  }
}