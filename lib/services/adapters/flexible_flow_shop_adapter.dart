import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/metrics.dart';
import 'package:production_planning/services/algorithms/flexible_flow_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'package:production_planning/shared/utils/changeover_matrix_utils.dart';
import '../../entities/machine_inactivity_entity.dart';
import '../../shared/utils/machine_downtime_utils.dart';
import '../../shared/utils/task_time_utils.dart';

class FlexibleFlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

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
    // Obtener la orden completa
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? order = responseOrder.fold((f) => null, (order) => order);
    if (order == null || order.orderJobs == null) return null;

    // Obtener todas las máquinas necesarias para los tipos de máquina en las tareas
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
      machines.addAll(machineList); // Agregar todas las máquinas del tipo
    }

    // Crear el input para el algoritmo Flexible Flow Shop y expandir por `amount` (cantidad)
    final List<FlexibleFlowInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final List<Tuple2<int, Map<int, Duration>>> taskSequence = [];
      for (final task in job.sequence!.tasks!) {
        final Map<int, Duration> machineDurations = {};
        for (final machine
            in machines.where((m) => m.machineTypeId == task.machineTypeId)) {
          // Priority 1: Explicit per-job per-task per-machine time
          final explicit = getExplicitProcessingDuration(job, task.id!, machine);
          if (explicit != null) {
            machineDurations[machine.id!] = explicit;
          } else {
            // Priority 2: Use task processingUnits directly, scaled only if machine is not standard (100%)
            if (machine.processingPercentage == 100 || machine.processingPercentage <= 0) {
              // Standard machine: use processingUnits as-is
              machineDurations[machine.id!] = task.processingUnits;
            } else {
              // Non-standard machine: scale processingUnits by machine percentage
              final ratio = machine.processingPercentage / 100.0;
              final scaledMillis = (task.processingUnits.inMilliseconds * ratio).round();
              machineDurations[machine.id!] = Duration(milliseconds: scaledMillis);
            }
          }
        }
        taskSequence.add(Tuple2(task.id!, machineDurations));
      }

      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(FlexibleFlowInput(
          job.jobId!,
          job.sequence!.id!,
          job.dueDate,
          job.priority,
          job.availableDate,
          taskSequence,
        ));
      }
    }

    // Crear la disponibilidad inicial de las máquinas
    final Map<int, DateTime> machinesAvailability = {};
    for (final machine in machines) {
      machinesAvailability[machine.id!] = order.regDate;
    }

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
    final machineInactivitiesMap = <int, List<MachineInactivityEntity>>{};
    final machineContinueCapacityMap = <int, int>{};
    final machineRestTimeMap = <int, Duration?>{};
    buildMachineDowntimeMaps(
      machines,
      inactivities: machineInactivitiesMap,
      continueCapacity: machineContinueCapacityMap,
      restTime: machineRestTimeMap,
    );

    // Ejecutar el algoritmo Flexible Flow Shop en un isolate
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
            'taskSequence': job.taskSequence.map((task) => {
                  'taskId': task.value1,
                  'machineDurations': task.value2.map(
                    (machineId, duration) => MapEntry(
                      machineId.toString(),
                      duration.inMilliseconds,
                    ),
                  ),
                }).toList(),
          }).toList(),
      'machinesAvailability': machinesAvailability.map(
        (machineId, date) => MapEntry(
          machineId.toString(),
          date.millisecondsSinceEpoch,
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
      'changeoverMatrix': changeoverMatrix.map(
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

    List<FlexibleFlowOutput> output;
    try {
      final rawOutput = await compute(flexibleFlowShopSchedule, payload);
      output = rawOutput.map((jobMap) {
        return FlexibleFlowOutput(
          jobMap['jobId'] as int,
          DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
          DateTime.fromMillisecondsSinceEpoch(jobMap['startDate'] as int),
          DateTime.fromMillisecondsSinceEpoch(jobMap['endTime'] as int),
          (jobMap['scheduling'] as Map<String, dynamic>).map(
            (taskId, taskEntry) {
              final entry = taskEntry as Map<String, dynamic>;
              return MapEntry(
                int.parse(taskId),
                Tuple2(
                  entry['machineId'] as int,
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
    } catch (error, stack) {
      print('FlexibleFlowShopAdapter.flexibleFlowShopAdapter error: ${error.toString()}');
      print(stack.toString());
      return null;
    }

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

        final planningMachine =
            planningMachines.firstWhere((m) => m.machineId == machineId);
        planningMachine.tasks.add(planningTask);
      }
    }

    // Calcular métricas
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
