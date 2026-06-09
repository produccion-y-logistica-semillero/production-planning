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
import '../../entities/job_entity.dart';
import '../../entities/machine_entity.dart';
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

    // ── 2. Resolve the single machine ──────────────────────────────────────
    final int machineTypeId =
        order.orderJobs![0].sequence!.tasks![0].machineTypeId;
    final responseMachine =
        await machineRepository.getAllMachinesFromType(machineTypeId);
    final MachineEntity? machineEntity =
        responseMachine.fold((f) => null, (m) => m[0]);
    if (machineEntity == null) return null;

    final responseTypeMachine =
        await machineRepository.getMachineTypeName(machineTypeId);
    final String machineTypeName =
        responseTypeMachine.fold((f) => "", (name) => name);

    // ── 3. Build state-based setup matrix ──────────────────────────────────
    // Single machine: one machine, so buildMachineStateSetupMatrix returns a
    // map with a single entry keyed by machineEntity.id!.
    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix([machineEntity], order.setupTimeMatrix);

    // ── 4. Build per-job state lookup (machineId → state) ─────────────────
    // buildJobMachineStates reads job.machineFinalStates — the actual field on
    // JobEntity. job.jobState does NOT exist; states are always stored
    // per-machine inside machineFinalStates.
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, [machineEntity]);

    // ── 5. Build SingleMachineInput list ───────────────────────────────────
    final List<SingleMachineInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final taskId = job.sequence!.tasks![0].id!;
      final explicit = getExplicitProcessingDuration(job, taskId, machineEntity);

      late final Duration duration;
      if (explicit != null) {
        duration = explicit;
      } else if (machineEntity.processingPercentage == 100 ||
          machineEntity.processingPercentage <= 0) {
        duration = job.sequence!.tasks![0].processingUnits;
      } else {
        final ratio = machineEntity.processingPercentage / 100.0;
        final scaledMillis =
            (job.sequence!.tasks![0].processingUnits.inMilliseconds * ratio)
                .round();
        duration = Duration(milliseconds: scaledMillis);
      }

      // Resolve the job-state label from machineFinalStates (the real field).
      // jobStates[jobId][machineId] is populated by buildJobMachineStates.
      final String jobState = _resolveJobState(
        jobStates[job.jobId!],
        machineEntity.id!,
      );

      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(SingleMachineInput(
          job.jobId!,
          duration,
          job.dueDate,
          job.priority,
          job.availableDate,
          jobState: jobState,
        ));
      }
    }

    // ── 6. Run algorithm ──────────────────────────────────────────────────
    final output = SingleMachine(
            0, order.regDate, Tuple2(START_SCHEDULE, END_SCHEDULE), input, rule,
            machineInactivities: machineEntity.scheduledInactivities,
            continueCapacity: machineEntity.continueCapacity,
            restTime: Duration(minutes: (60 * machineEntity.restPercentage / 100).round()),
    )
        .output;

    final Map<int, int> jobCounter = {};
    final tasks = output.map((out) {
      final jobSequence = order.orderJobs!
          .firstWhere((j) => j.jobId == out.jobId)
          .sequence!;
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
      final current = (jobCounter[out.jobId] ?? 0) + 1;
      jobCounter[out.jobId] = current;
      final jobName = job.jobName ?? 'Job ${out.jobId}';
      final displayName = current == 1
          ? jobName
          : '$jobName (${current - 1})';
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

    //since its single machine we know that there's only 1 planning machine
    final machinesResult = [
      PlanningMachineEntity(
        machineEntity.id!,
        machineTypeName,
        tasks,
        scheduledInactivities: machineEntity.scheduledInactivities,
      )
    ];

    // ── 8. Metrics ────────────────────────────────────────────────────────
    final metrics = getMetricts(
      machinesResult,
      output.map((out) {
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
        return Tuple5(out.jobId, out.startDate, out.endDate, out.dueDate,
            job.priority);
      }).toList(),
    );

    return Tuple2(machinesResult, metrics);
  }

  /// Resolves the product-family label for a job on [machineId].
  ///
  /// [statesForJob] comes from buildJobMachineStates, which reads
  /// job.machineFinalStates — the actual field on JobEntity.
  ///
  /// Priority:
  ///   1. statesForJob[machineId]     — exact match for this machine
  ///   2. statesForJob.values.first   — any recorded state for this job
  ///   3. 'A'                         — hard default (no state configured)
  String _resolveJobState(Map<int, String>? statesForJob, int machineId) {
    if (statesForJob == null || statesForJob.isEmpty) return 'A';
    return statesForJob[machineId] ?? statesForJob.values.first;
  }
}