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
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/utils/changeover_matrix_utils.dart';
import 'package:production_planning/shared/utils/machine_downtime_utils.dart';
import '../../shared/utils/task_time_utils.dart';

class JobShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  JobShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> jobShopAdapter(
      int orderId, String rule) async {
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (o) => o);
    if (order == null || order.orderJobs == null) return null;

    // Collect all machines used by tasks (one machine per type expected)
    final List<int> machineTypeIds = order.orderJobs!
        .expand((job) => job.sequence!.tasks!.map((t) => t.machineTypeId))
        .toSet()
        .toList();

    final List<MachineEntity> machines = [];
    for (final typeId in machineTypeIds) {
      final resp = await machineRepository.getAllMachinesFromType(typeId);
      final machineList = resp.fold((_) => null, (m) => m);
      if (machineList == null || machineList.isEmpty) return null;
      // Expecting exactly one machine per type for JOB SHOP; take the first
      machines.add(machineList.first);
    }

    // Build inputJobs and jobRoutes
    final List<FlexibleJobInput> inputJobs = [];

    for (final job in order.orderJobs!) {
      final sequence = job.sequence!;
      final List<Tuple2<int, Map<int, Duration>>> taskSequence = [];
      for (final task in sequence.tasks!) {
        final Map<int, Duration> machineDurations = {};
        final machine = machines.firstWhere((m) => m.machineTypeId == task.machineTypeId);
        
        final explicit = getExplicitProcessingDuration(job, task.id!, machine);
        if (explicit != null) {
          machineDurations[machine.id!] = explicit;
        } else {
          if (machine.processingPercentage == 100 || machine.processingPercentage <= 0) {
            machineDurations[machine.id!] = task.processingUnits;
          } else {
            final ratio = machine.processingPercentage / 100.0;
            final scaledMillis = (task.processingUnits.inMilliseconds * ratio).round();
            machineDurations[machine.id!] = Duration(milliseconds: scaledMillis);
          }
        }
        taskSequence.add(Tuple2(task.id!, machineDurations));
      }

      for (var i = 0; i < job.amount; i++) {
        final uniqueJobId = job.jobId! * 1000 + i;
        inputJobs.add(FlexibleJobInput(
          uniqueJobId,
          job.jobId!,
          job.sequence!.id!,
          job.dueDate,
          job.priority,
          job.availableDate,
          taskSequence,
          dependencies: job.sequence!.dependencies ?? [],
        ));
      }
    }

    // Create initial availability for machines
    final Map<int, DateTime> machinesAvailability = {};
    for (final machine in machines) {
      machinesAvailability[machine.id!] = order.regDate;
    }

    // Setup inactivities, resting, and capacity
    final Map<int, List<MachineInactivityEntity>> machineInactivitiesMap = {};
    final Map<int, int> machineContinueCapacityMap = {};
    final Map<int, Duration?> machineRestTimeMap = {};
    buildMachineDowntimeMaps(
      machines,
      inactivities: machineInactivitiesMap,
      continueCapacity: machineContinueCapacityMap,
      restTime: machineRestTimeMap,
    );

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machines);

    final sequenceIds = order.orderJobs!
        .where((j) => j.sequence?.id != null)
        .map((j) => j.sequence!.id!)
        .toSet();
    final changeoverMatrix = await loadMergedChangeoverMatrix(
      setupTimeService,
      machines,
      sequenceIds,
    );
    final jobInterruptionPolicies =
        buildJobInterruptionPolicies(order.orderJobs!);

    // Run Flexible Job Shop algorithm (highly optimized Non-delay & DAG-enabled)
    List<FlexibleJobOutput> output;
    try {
      output = FlexibleJobShop(
        order.regDate,
        Tuple2(START_SCHEDULE, END_SCHEDULE),
        inputJobs,
        machinesAvailability,
        rule.toUpperCase(),
        machineInactivities: machineInactivitiesMap,
        machineContinueCapacity: machineContinueCapacityMap,
        machineRestTime: machineRestTimeMap,
        changeoverMatrix: changeoverMatrix,
        stateSetupMatrix: stateSetupMatrix,
        jobStates: jobStates,
        jobInterruptionPolicies: jobInterruptionPolicies,
      ).output;
    } catch (error, stack) {
      print('JobShopAdapter.jobShopAdapter error: ${error.toString()}');
      print(stack.toString());
      return null;
    }

    // Transform output into PlanningMachineEntity
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
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.dbJobId);
      final sequence = job.sequence!;
      final current = (jobCounter[out.dbJobId] ?? 0) + 1;
      jobCounter[out.dbJobId] = current;

      for (final taskEntry in out.scheduling.entries) {
        final taskId = taskEntry.key;
        final machineId = taskEntry.value.value1;
        final timeRange = taskEntry.value.value2;

        final task = sequence.tasks!.firstWhere((t) => t.id == taskId);

        final jobName = job.jobName ?? 'Job ${out.dbJobId}';
        final displayName = current == 1 ? jobName : '$jobName (${current - 1})';

        final planningTask = PlanningTaskEntity(
          sequenceId: sequence.id!,
          sequenceName: sequence.name,
          displayName: displayName,
          taskId: task.id!,
          numberProcess: taskId,
          startDate: timeRange.start,
          endDate: timeRange.end,
          retarded: out.dueDate.isBefore(timeRange.end),
          jobId: job.jobId!,
          orderId: orderId,
        );

        final planningMachine =
            planningMachines.firstWhere((m) => m.machineId == machineId);
        planningMachine.tasks.add(planningTask);
      }
    }

    // Calculate metrics
    final List<Tuple4<DateTime, DateTime, DateTime, int>> jobsDates = [];
    for (final out in output) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.dbJobId);
      jobsDates.add(Tuple4(
          job.availableDate, out.endTime, out.dueDate, job.priority));
    }

    final metrics = getMetricts(planningMachines, jobsDates);
    return Tuple2(planningMachines, metrics);
  }
}
