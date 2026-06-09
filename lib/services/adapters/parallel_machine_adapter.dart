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
import '../../entities/job_entity.dart';
import '../../entities/machine_entity.dart';
import '../../shared/utils/task_time_utils.dart';

class ParallelMachineAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService; // <── added

  ParallelMachineAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService, // <── added
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> parallelMachineAdapter(
      int orderId, String rule) async {
    // ── 1. Load order and attach any in-memory setup matrices ──────────────
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? baseOrder = responseOrder.fold((f) => null, (or) => or);
    if (baseOrder == null) return null;

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
    final int machineTypeId = order.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachines = await machineRepository.getAllMachinesFromType(machineTypeId);
    final List<MachineEntity>? machineEntities = responseMachines.fold((f) => null, (m) => m);
    if (machineEntities == null) return null;

    // ── 3. Build state-based setup matrix ──────────────────────────────────
    // buildMachineStateSetupMatrix converts the order's setupTimeMatrix
    // (machineName → fromState → toState → minutes) into a lookup keyed by
    // machineId, matching the structure used by Flow Shop and the other
    // environments that already support setup times.
    //
    // For Parallel Machines every machine is of the SAME type (that is the
    // definition of the environment), so all machines share the same
    // fromState → toState costs.  buildMachineStateSetupMatrix handles this
    // transparently because it iterates over the provided machine list.
    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machineEntities, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machineEntities);

    // ── 4. Build ParallelInput list ────────────────────────────────────────
    final List<ParallelInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final Map<int, Duration> durationsInMachines = {};
      final task = job.sequence!.tasks![0];

      for (final machine in machineEntities) {
        final explicit = getExplicitProcessingDuration(job, task.id!, machine);
        if (explicit != null) {
          durationsInMachines[machine.id!] = explicit;
        } else if (machine.processingPercentage == 100 || machine.processingPercentage <= 0) {
          durationsInMachines[machine.id!] = task.processingUnits;
        } else {
          final ratio = machine.processingPercentage / 100.0;
          final scaledMillis = (task.processingUnits.inMilliseconds * ratio).round();
          durationsInMachines[machine.id!] = Duration(milliseconds: scaledMillis);
        }
      }

      final statesForJob = jobStates[job.jobId!];
      final defaultJobState = _resolveJobState(
        job,
        statesForJob,
        machineTypeId,
      );

      // Expand by amount; carry per-machine states for setup matrix lookups.
      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(ParallelInput(
          job.jobId!,
          job.dueDate,
          job.priority,
          job.availableDate,
          durationsInMachines,
          jobState: defaultJobState,
          jobStatesByMachine: statesForJob,
        ));
      }
    }

    // ── 5. Build empty machine slot map ───────────────────────────────────
    final Map<int, List<Tuple2<DateTime, DateTime>>> machineSlots = {
      for (final machine in machineEntities) machine.id!: [],
    };

    // ── 6. Run algorithm ──────────────────────────────────────────────────
    final output = ParallelMachine(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machineSlots,
      rule.toUpperCase(),
      stateSetupMatrix: stateSetupMatrix, // <── passed through
    ).output;

    // ── 7. Transform output into PlanningMachineEntity ────────────────────
    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    final Map<int, int> jobCounter = {};
    for (final out in output) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final jobSequence = job.sequence!;
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1 ? jobName : '$jobName (${current - 1})';

      final planningTask = PlanningTaskEntity(
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

      machineTasksMap.putIfAbsent(out.machineId, () => []).add(planningTask);
    }

    final List<PlanningMachineEntity> machinesResult =
        machineTasksMap.entries.map((entry) {
      final machine = machineEntities.firstWhere((m) => m.id == entry.key);
      return PlanningMachineEntity(
        entry.key,
        machine.name,
        entry.value,
        scheduledInactivities: machine.scheduledInactivities,
      );
    }).toList();

    // ── 8. Metrics ────────────────────────────────────────────────────────
    final metrics = getMetricts(
      machinesResult,
      output.map((out) {
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
        return Tuple5(out.jobId, job.availableDate, out.endDate, out.dueDate,
            job.priority);
      }).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }

  /// Resolves the product/state label used in the setup-time matrix for this job.
  String _resolveJobState(
    JobEntity job,
    Map<int, String>? statesForJob,
    int machineTypeId,
  ) {
    if (statesForJob != null && statesForJob.isNotEmpty) {
      return statesForJob.values.first;
    }
    final fromJob = job.machineFinalStates?[machineTypeId];
    if (fromJob != null && fromJob.isNotEmpty) {
      return fromJob;
    }
    return 'A';
  }
}