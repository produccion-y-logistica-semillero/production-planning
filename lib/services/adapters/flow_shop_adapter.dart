import 'package:dartz/dartz.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/algorithms/flow_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'package:production_planning/shared/utils/changeover_matrix_utils.dart';
import '../../entities/machine_entity.dart';
import '../../entities/machine_inactivity_entity.dart';
import '../../shared/utils/machine_downtime_utils.dart';
import '../../shared/utils/task_time_utils.dart';

class FlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  FlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flowShopAdapter(
    int orderId,
    String rule,
  ) async {
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

    final mergedMatrix = await loadMergedChangeoverMatrix(
      setupTimeService,
      machines,
      sequenceIds,
    );

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
      buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
      buildJobMachineStates(order.orderJobs!, machines);
    final jobInterruptionPolicies =
        buildJobInterruptionPolicies(order.orderJobs!);

    final machineInactivitiesMap = <int, List<MachineInactivityEntity>>{};
    final machineContinueCapacityMap = <int, int>{};
    final machineRestTimeMap = <int, Duration?>{};
    buildMachineDowntimeMaps(
      machines,
      inactivities: machineInactivitiesMap,
      continueCapacity: machineContinueCapacityMap,
      restTime: machineRestTimeMap,
    );

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

    //we call the algorithm in a background isolate and receive the output
    final payload = {
      'startDate': order.regDate.millisecondsSinceEpoch,
      'workingStartHour': START_SCHEDULE.hour,
      'workingStartMinute': START_SCHEDULE.minute,
      'workingEndHour': END_SCHEDULE.hour,
      'workingEndMinute': END_SCHEDULE.minute,
      'rule': rule.toUpperCase(),
      'inputJobs': inputJobs.map((job) => {
            'jobId': job.jobId,
            'sequenceId': job.sequenceId,
            'dueDate': job.dueDate.millisecondsSinceEpoch,
            'priority': job.priority,
            'availableDate': job.availableDate.millisecondsSinceEpoch,
            'taskSequence': job.taskSequence
                .map((task) => {
                      'taskId': task.value1,
                      'machineId': task.value2,
                    })
                .toList(),
            'taskTimes': job.taskTimesInMachines.map(
              (taskId, duration) => MapEntry(
                taskId.toString(),
                duration.inMilliseconds,
              ),
            ),
          }).toList(),
      'machinesAvailability': machinesAvailability.map(
        (machineId, date) => MapEntry(
          machineId.toString(),
          date.millisecondsSinceEpoch,
        ),
      ),
      'changeoverMatrix': mergedMatrix.map(
        (machineId, prevMap) => MapEntry(
          machineId.toString(),
          prevMap.map(
            (prevSequence, currMap) => MapEntry(
              prevSequence?.toString() ?? 'null',
              currMap.map(
                (currSequence, duration) => MapEntry(
                  currSequence.toString(),
                  duration.inMinutes,
                ),
              ),
            ),
          ),
        ),
      ),
      'stateSetupMatrix': stateSetupMatrix?.map(
        (machineId, stateMap) => MapEntry(
          machineId.toString(),
          stateMap.map(
            (fromState, targetMap) => MapEntry(
              fromState,
              targetMap.map(
                (toState, minutes) => MapEntry(toState, minutes),
              ),
            ),
          ),
        ),
      ),
      'jobStates': jobStates.map(
        (jobId, machineStates) => MapEntry(
          jobId.toString(),
          machineStates.map(
            (machineId, state) => MapEntry(machineId.toString(), state),
          ),
        ),
      ),
      'jobInterruptionPolicies': jobInterruptionPolicies.map(
        (jobId, policy) => MapEntry(jobId.toString(), {
          'allowRestInterrupt': policy.allowRestInterrupt,
          'allowScheduledInterrupt': policy.allowScheduledInterrupt,
          'allowWorkHoursInterrupt': policy.allowWorkHoursInterrupt,
        }),
      ),
      'machineInactivities': machineInactivitiesMap.map(
        (machineId, inactivities) => MapEntry(
          machineId.toString(),
          inactivities.map((activity) => {
            'name': activity.name,
            'weekdays': activity.weekdays.map((d) => d.index).toList(),
            'startTimeMinutes': activity.startTime.inMinutes,
            'durationMinutes': activity.duration.inMinutes,
          }).toList(),
        ),
      ),
      'machineContinueCapacity': machineContinueCapacityMap.map(
        (machineId, capacity) => MapEntry(machineId.toString(), capacity),
      ),
      'machineRestTime': machineRestTimeMap.map(
        (machineId, restTime) => MapEntry(
          machineId.toString(),
          restTime?.inMinutes,
        ),
      ),
    };

    final rawOutput = await compute(flowShopSchedule, payload);
    final output = rawOutput.map((jobMap) {
      return FlowShopOutput(
        jobMap['jobId'] as int,
        DateTime.fromMillisecondsSinceEpoch(jobMap['startDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(jobMap['endTime'] as int),
        (jobMap['machinesScheduling'] as Map<String, dynamic>).map(
          (machineId, taskEntry) {
            final entry = taskEntry as Map<String, dynamic>;
            return MapEntry(
              int.parse(machineId),
              Tuple2(
                entry['taskId'] as int,
                Range(
                  DateTime.fromMillisecondsSinceEpoch(entry['startDate'] as int),
                  DateTime.fromMillisecondsSinceEpoch(entry['endDate'] as int),
                ),
              ),
            );
          },
        ),
      );
    }).toList();

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
}
