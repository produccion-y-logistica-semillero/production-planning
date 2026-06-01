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
import 'package:production_planning/shared/functions/functions.dart';
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
    String rule, {
    Map<int, Map<int?, Map<int, Duration>>>? changeoverMatrix,
  }) async {
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (or) => or);
    if (order == null) return null;

    // Obtener todas las máquinas necesarias para los tipos de máquina en las tareas
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

    final sequenceIds = order.orderJobs!
        .where((job) => job.sequence != null && job.sequence!.id != null)
        .map((job) => job.sequence!.id!)
        .toSet();

    final defaultMatrix = _buildDefaultChangeoverMatrix(machines, sequenceIds);
    final mergedMatrix =
        _mergeChangeoverMatrices(defaultMatrix, changeoverMatrix);

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
      buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
      buildJobMachineStates(order.orderJobs!, machines);

    //we create the input and expand jobs by their `amount` (cantidad)
    final List<FlowShopInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final Map<int, Duration> taskTimes = {};
      final List<Tuple2<int, int>> taskSequence = [];
      //iterating over all tasks, and for each one, we get the time it takes on the machine we have for the machine type
      for (final task in job.sequence!.tasks!) {
        final machineOfTask =
            machines.firstWhere((m) => m.machineTypeId == task.machineTypeId);
        
        // Priority 1: Explicit per-job per-task per-machine time
        final explicit = getExplicitProcessingDuration(job, task.id!, machineOfTask);
        if (explicit != null) {
          taskTimes[task.id!] = explicit;
        } else {
          // Priority 2: Use task processingUnits directly, scaled only if machine is not standard (100%)
          if (machineOfTask.processingPercentage == 100 || machineOfTask.processingPercentage <= 0) {
            // Standard machine: use processingUnits as-is
            taskTimes[task.id!] = task.processingUnits;
          } else {
            // Non-standard machine: scale processingUnits by machine percentage
            final ratio = machineOfTask.processingPercentage / 100.0;
            final scaledMillis = (task.processingUnits.inMilliseconds * ratio).round();
            taskTimes[task.id!] = Duration(milliseconds: scaledMillis);
          }
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

    //we create the sequence
    final Map<int, DateTime> machinesAvailability = {};
    for (final machine in machines) {
      if (machine.id != null) {
        machinesAvailability[machine.id!] = order.regDate;
      }
    }

    //we call the algorithm and receive the output
    final output = FlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule,
      changeoverMatrix: mergedMatrix,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
    ).output;

    //transform to planning machines
    final List<PlanningMachineEntity> planningMachines = [];
    for (final m in machines) {
      if (m.id != null) {
        planningMachines.add(PlanningMachineEntity(
          m.id!,
          m.name,
          [],
          scheduledInactivities: m.scheduledInactivities,
        ));
      }
    }

    final Map<int, int> jobCounter = {};
    for (final out in output) {
      int i = 0;
      final job = order.orderJobs!.where((j) => j.jobId == out.jobId).first;
      final jobSequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1
          ? jobName
          : '$jobName (${current - 1})';
      for (final machineScheduling in out.machinesScheduling.entries) {
        //we get the planning machine where this task belongs
        final planningMachineEntity = planningMachines
            .where((pm) => pm.machineId == machineScheduling.key)
            .first;
        final DateTime taskStart = machineScheduling.value.value2.startDate;
        final DateTime taskEnd = machineScheduling.value.value2.endDate;
        final planningTask = PlanningTaskEntity(
            sequenceId: jobSequence.id!,
            sequenceName: jobSequence.name,
            displayName: displayName,
            taskId: machineScheduling.value.value1,
            numberProcess: i++,
            startDate: taskStart,
            endDate: taskEnd,
            retarded: out.dueDate.isBefore(out.endTime),
            orderId: orderId,
            jobId: out.jobId);

        planningMachineEntity.tasks.add(planningTask);
      }
    }
    //we get the metrics

    final List<Tuple4<DateTime, DateTime, DateTime, int>> jobsDates = [];
    for (final out in output) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      jobsDates.add(Tuple4(
          job.availableDate, out.endTime, out.dueDate, job.priority));
    }

    final metrics = getMetricts(
      planningMachines,
      jobsDates,
    );
    return Tuple2(planningMachines, metrics);
  }

  Map<int, Map<int?, Map<int, Duration>>> _buildDefaultChangeoverMatrix(
    List<MachineEntity> machines,
    Set<int> sequenceIds,
  ) {
    final Map<int, Map<int?, Map<int, Duration>>> matrix = {};
    for (final machine in machines) {
      if (machine.id == null) continue;
      final machineId = machine.id!;
      if (matrix.containsKey(machineId)) continue;
      // Calculate preparation duration from percentage (100% = 1 hour base)
      final Duration baseDuration =
          Duration(minutes: (60 * machine.preparationPercentage / 100).round());
      final Map<int, Duration> defaultTargets = {
        for (final seqId in sequenceIds) seqId: baseDuration,
      };
      final Map<int?, Map<int, Duration>> machineMatrix = {
        null: Map<int, Duration>.from(defaultTargets),
      };
      for (final previous in sequenceIds) {
        machineMatrix[previous] = Map<int, Duration>.from(defaultTargets);
      }
      matrix[machineId] = machineMatrix;
    }
    return matrix;
  }

  Map<int, Map<int?, Map<int, Duration>>> _mergeChangeoverMatrices(
    Map<int, Map<int?, Map<int, Duration>>> baseMatrix,
    Map<int, Map<int?, Map<int, Duration>>>? overrideMatrix,
  ) {
    if (overrideMatrix == null || overrideMatrix.isEmpty) {
      return baseMatrix;
    }

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
        final currentIds = <int>{
          ...baseDurations.keys,
          ...overrideDurations.keys
        };
        final mergedDurations = <int, Duration>{};
        for (final currentId in currentIds) {
          if (overrideDurations.containsKey(currentId)) {
            mergedDurations[currentId] = overrideDurations[currentId]!;
          } else if (baseDurations.containsKey(currentId)) {
            mergedDurations[currentId] = baseDurations[currentId]!;
          }
        }
        mergedMachine[previousId] = mergedDurations;
      }
      result[machineId] = mergedMachine;
    }
    return result;
  }
}
