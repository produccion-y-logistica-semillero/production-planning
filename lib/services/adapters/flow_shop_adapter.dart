// lib/services/adapters/flow_shop_Adapter.dart
//
// buildMachineStateSetupMatrix / buildJobMachineStates (imported from
// shared/utils/task_time_utils.dart) build the sequence-dependent,
// state-based setup matrix directly from the order's persisted
// setupTimeMatrix (see OrderEntity / order_setup_matrix table).

import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import '../../entities/machine_entity.dart';
import '../../shared/utils/task_time_utils.dart';

class FlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  FlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flowShopAdapter(
    int orderId,
    String rule,
  ) async {
    // ── 1. Load order ───────────────────────────────────────────────────────
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (or) => or);
    if (order == null) return null;

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
    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machines);

    // ── 4. Build FlowShopInput list ────────────────────────────────────────
    final List<FlowShopInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final Map<int, Duration> taskTimes = {};
      final List<Tuple2<int, int>> taskSequence = [];
      final Map<int, bool> interruptibleByTask = {};
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
        interruptibleByTask[task.id!] =
            resolveInterruptible(job, task, machineOfTask.id!);
      }
      inputJobs.add(FlowShopInput(
        job.jobId!,
        job.sequence!.id!,
        job.dueDate,
        job.priority,
        job.availableDate,
        taskSequence,
        taskTimes,
        interruptibleByTask: interruptibleByTask,
      ));
    }

    // ── 5. Initial machine availability ───────────────────────────────────
    final Map<int, DateTime> machinesAvailability = {
      for (final m in machines)
        if (m.id != null) m.id!: order.regDate,
    };

    // ── 6. Run algorithm ──────────────────────────────────────────────────
    // continueCapacity is interpreted as minutes of continuous processing
    // before a mandatory rest (see PreemptionEngine), not a job count.
    final Map<int, List<MachineInactivityEntity>> machineInactivitiesMap = {};
    final Map<int, int> machineContinueCapacityMap = {};
    final Map<int, Duration?> machineRestTimeMap = {};
    for (final m in machines) {
      if (m.id == null) continue;
      machineInactivitiesMap[m.id!] = m.scheduledInactivities;
      machineContinueCapacityMap[m.id!] = m.continueCapacity;
      machineRestTimeMap[m.id!] =
          Duration(minutes: (60 * m.restPercentage / 100).round());
    }

    final output = FlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule.toUpperCase(),
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity: machineContinueCapacityMap,
      machineRestTime: machineRestTimeMap,
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

    for (final out in output) {
      int i = 0;
      final job =
          order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final jobSequence = job.sequence!;
      final jobName = job.jobName ?? 'Job ${out.jobId}';

      for (final machineScheduling in out.machinesScheduling.entries) {
        final planningMachineEntity = planningMachines
            .firstWhere((pm) => pm.machineId == machineScheduling.key);
        final taskStart = machineScheduling.value.value2.startDate;
        final taskEnd = machineScheduling.value.value2.endDate;
        planningMachineEntity.tasks.add(PlanningTaskEntity(
          sequenceId: jobSequence.id!,
          sequenceName: jobSequence.name,
          displayName: jobName,
          taskId: machineScheduling.value.value1,
          numberProcess: i++,
          startDate: taskStart,
          endDate: taskEnd,
          retarded: out.dueDate.isBefore(out.endTime),
          orderId: orderId,
          jobId: out.jobId,
          segments: out.segmentsByMachine[machineScheduling.key],
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
}