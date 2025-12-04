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

    //We get all machines
    final List<int> machinesTypesIds = order
        .orderJobs![0]
        .sequence!
        .tasks!
        .map((t) => t.machineTypeId)
        .toList();
    final List<MachineEntity> machines = [];
    for (final typeId in machinesTypesIds) {
      final machinesSpecific = await machineRepository.getAllMachinesFromType(typeId);
      final machineList = machinesSpecific.fold((_) => null, (m) => m);
      if (machineList == null || machineList.isEmpty) return null;
      machines.addAll(machineList);
    }

    final sequenceIds = order.orderJobs!
        .where((job) => job.sequence != null && job.sequence!.id != null)
        .map((job) => job.sequence!.id!)
        .toSet();

    final defaultMatrix =
        _buildDefaultChangeoverMatrix(machines, sequenceIds);
    final mergedMatrix =
        _mergeChangeoverMatrices(defaultMatrix, changeoverMatrix);

    //we create the input
    final List<FlowShopInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final Map<int, Duration> taskTimes = {};
      final List<Tuple2<int, int>> taskSequence = [];
      //iterating over all tasks, and for each one, we get the time it takes on the machine we have for the machine type
      for (final task in job.sequence!.tasks!) {
        final machineOfTask =
            machines.where((m) => m.machineTypeId == task.machineTypeId).first;
        taskTimes[task.id!] = ruleOf3(machineOfTask.processingTime, task.processingUnits);
        taskSequence.add(Tuple2(task.id!, task.machineTypeId));
      }
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

    //we create the sequence
    final Map<int, DateTime> machinesAvailability = {};
    for (final task in order.orderJobs!.first.sequence!.tasks!) {
      machinesAvailability[task.machineTypeId] = DateTime.now();
    }

    //we call the algorithm and receive the output
    final output = FlowShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule,
      changeoverMatrix: mergedMatrix,
    ).output;

    //transform to planning machines
    final List<PlanningMachineEntity> planningMachines = [];
    for (final m in machines) {
      planningMachines.add(PlanningMachineEntity(m.machineTypeId!, m.name, []));
    }

    for (final out in output) {
      int i = 0;
      final jobSequence =
          order.orderJobs!.where((j) => j.jobId == out.jobId).first.sequence!;
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
    final List<Tuple3<DateTime, DateTime, DateTime>> jobsDates = [];
    for (final out in output) {
      jobsDates.add(Tuple3(out.startDate, out.endTime, out.dueDate));
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
      if (machine.machineTypeId == null) continue;
      final machineId = machine.machineTypeId!;
      if (matrix.containsKey(machineId)) continue;
      final Duration baseDuration = machine.preparationTime ?? Duration.zero;
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
        final currentIds = <int>{...baseDurations.keys, ...overrideDurations.keys};
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
