import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
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
import 'package:production_planning/shared/types/rnage.dart';
import 'package:production_planning/services/algorithms/flexible_job_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import '../../shared/utils/task_time_utils.dart';

class FlexibleJobShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  FlexibleJobShopAdapter({
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

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flexibleJobShopAdapter(
      int orderId, String rule) async {
    // Obtener la orden completa
    final responseOrder = await orderRepository.getFullOrder(orderId);
    OrderEntity? baseOrder = responseOrder.fold((f) => null, (order) => order);
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

    // Crear el input para el algoritmo Flexible Job Shop y expandir por `amount` (cantidad)
    final List<FlexibleJobInput> inputJobs = [];
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

    // Crear la disponibilidad inicial de las máquinas
    final Map<int, DateTime> machinesAvailability = {};
    for (final machine in machines) {
      machinesAvailability[machine.id!] = order.regDate;
    }

    // Crear mapa de inactividades por máquina
    final Map<int, List<MachineInactivityEntity>> machineInactivitiesMap = {};
    final Map<int, int> machineContinueCapacityMap = {};
    final Map<int, Duration?> machineRestTimeMap = {};
    for (final machine in machines) {
      machineInactivitiesMap[machine.id!] = machine.scheduledInactivities;
      machineContinueCapacityMap[machine.id!] = machine.continueCapacity;
      // Calculate rest duration directly (if percentage != 100, scale it)
      if (machine.restPercentage == 100 || machine.restPercentage <= 0) {
        // Standard rest: 1 hour as base
        machineRestTimeMap[machine.id!] = const Duration(hours: 1);
      } else {
        // Non-standard rest: scale 1 hour by machine percentage
        final ratio = machine.restPercentage / 100.0;
        final scaledMillis = (Duration(hours: 1).inMilliseconds * ratio).round();
        machineRestTimeMap[machine.id!] = Duration(milliseconds: scaledMillis);
      }
    }

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
        buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
        buildJobMachineStates(order.orderJobs!, machines);

    // Ejecutar el algoritmo Flexible Job Shop en un isolate
    final payload = <String, dynamic>{
      'startDate': order.regDate.millisecondsSinceEpoch,
      'workingStartHour': START_SCHEDULE.hour,
      'workingStartMinute': START_SCHEDULE.minute,
      'workingEndHour': END_SCHEDULE.hour,
      'workingEndMinute': END_SCHEDULE.minute,
      'rule': rule.toUpperCase(),
      'inputJobs': inputJobs.map((job) {
        return {
          'jobId': job.jobId,
          'dbJobId': job.dbJobId,
          'sequenceId': job.sequenceId,
          'dueDate': job.dueDate.millisecondsSinceEpoch,
          'priority': job.priority,
          'availableDate': job.availableDate.millisecondsSinceEpoch,
          'taskSequence': job.taskSequence.map((task) {
            return {
              'taskId': task.value1,
              'machineDurations': task.value2.map((machineId, duration) => MapEntry(machineId, duration.inMilliseconds)),
            };
          }).toList(),
          'dependencies': job.dependencies
              .map((dep) => {
                    'predecessor_id': dep.predecessor_id,
                    'successor_id': dep.successor_id,
                    'sequenceId': dep.sequenceId,
                  })
              .toList(),
        };
      }).toList(),
      'machinesAvailability': machinesAvailability.map((machineId, date) => MapEntry(machineId, date.millisecondsSinceEpoch)),
      'machineInactivities': machineInactivitiesMap.map((machineId, inactivities) {
        return MapEntry(machineId, inactivities.map((inactivity) {
          return {
            'machineId': inactivity.machineId,
            'name': inactivity.name,
            'weekdays': inactivity.weekdays.map((wd) => wd.index).toList(),
            'startTimeMinutes': inactivity.startTime.inMinutes,
            'durationMinutes': inactivity.duration.inMinutes,
          };
        }).toList());
      }),
      'machineContinueCapacity': machineContinueCapacityMap,
      'machineRestTime': machineRestTimeMap.map((machineId, duration) => MapEntry(machineId, duration?.inMilliseconds)),
      'stateSetupMatrix': stateSetupMatrix,
      'jobStates': jobStates,
    };

    List<Map<String, dynamic>> rawOutput;
    try {
      rawOutput = await compute(flexibleJobShopSchedule, payload);
    } catch (error, stack) {
      print('FlexibleJobShopAdapter.flexibleJobShopAdapter compute error: ${error.toString()}');
      print(stack.toString());
      return null;
    }

    final List<FlexibleJobOutput> output = rawOutput.map((out) {
      final schedulingMap = (out['scheduling'] as Map<dynamic, dynamic>).map((key, value) {
        final entry = Map<String, dynamic>.from(value as Map);
        return MapEntry(
          int.parse(key as String),
          Tuple2(
            entry['machineId'] as int,
            Range(
              DateTime.fromMillisecondsSinceEpoch(entry['start'] as int),
              DateTime.fromMillisecondsSinceEpoch(entry['end'] as int),
            ),
          ),
        );
      });
      return FlexibleJobOutput(
        out['jobId'] as int,
        out['dbJobId'] as int,
        DateTime.fromMillisecondsSinceEpoch(out['dueDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(out['startDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(out['endTime'] as int),
        schedulingMap,
      );
    }).toList();

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
        final displayName = current == 1
            ? jobName
            : '$jobName (${current - 1})';

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

    // Calcular métricas
    final List<Tuple5<int, DateTime, DateTime, DateTime, int>> jobsDates = [];
    for (final out in output) {
      final job = order.orderJobs!.firstWhere((j) => j.jobId == out.dbJobId);
      jobsDates.add(Tuple5(out.dbJobId, job.availableDate, out.endTime,
          out.dueDate, job.priority));
    }

    final metrics = getMetricts(
      planningMachines,
      jobsDates,
    );

    return Tuple2(planningMachines, metrics);
  }
}
