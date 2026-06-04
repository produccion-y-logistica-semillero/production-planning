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
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/types/rnage.dart';
import '../../shared/utils/task_time_utils.dart';

class OpenShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;
  final SetupTimeService setupTimeService;

  OpenShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
    required this.setupTimeService,
  });

  Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> openShopAdapter(
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
      if (machineList == null || machineList.isEmpty) {
        return null;
      }
      machines.addAll(machineList);
    }

    // Crear el input para el algoritmo Open Shop y expandir por `amount` (cantidad)
    final List<OpenShopInput> inputJobs = [];
    for (final job in order.orderJobs!) {
      final List<Tuple2<int, Map<int, Duration>>> operations = [];
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

        if (machineDurations.isNotEmpty) {
          operations.add(Tuple2(task.id!, machineDurations));
        }
      }

      for (var i = 0; i < job.amount; i++) {
        final uniqueJobId = job.jobId! * 1000 + i;
        inputJobs.add(OpenShopInput(
          uniqueJobId,
          job.jobId!,
          job.sequence!.id!,
          job.dueDate,
          job.priority,
          job.availableDate,
          operations,
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
      // Calculate rest duration from percentage (100% = 1 hour base)
      machineRestTimeMap[machine.id!] =
          Duration(minutes: (60 * machine.restPercentage / 100).round());
    }

    // Obtener la matriz de changeover
    final changeoverMatrixResult =
        await setupTimeService.buildChangeoverMatrix();
    final changeoverMatrix = changeoverMatrixResult.fold(
      (_) => const <int, Map<int?, Map<int, Duration>>>{},
      (matrix) => matrix,
    );

    final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix =
      buildMachineStateSetupMatrix(machines, order.setupTimeMatrix);
    final Map<int, Map<int, String>> jobStates =
      buildJobMachineStates(order.orderJobs!, machines);

    // Ejecutar el algoritmo Open Shop en un isolate y transformar la salida en PlanningMachineEntity
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
          'operations': job.operations.map((operation) {
            return {
              'taskId': operation.value1,
              'machineDurations': operation.value2.map((machineId, duration) => MapEntry(machineId, duration.inMilliseconds)),
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
      'changeoverMatrix': changeoverMatrix.map((machineId, prevMap) {
        return MapEntry(machineId, prevMap.map((prevSeqId, currMap) {
          return MapEntry(prevSeqId?.toString() ?? 'null', currMap.map((currSeqId, minutes) => MapEntry(currSeqId, minutes.inMinutes)));
        }));
      }),
      'stateSetupMatrix': stateSetupMatrix,
      'jobStates': jobStates,
    };

    List<Map<String, dynamic>> rawOutput;
    try {
      rawOutput = await compute(openShopSchedule, payload);
    } catch (error, stack) {
      print('OpenShopAdapter.openShopAdapter compute error: ${error.toString()}');
      print(stack.toString());
      return null;
    }

    final List<OpenShopOutput> output = rawOutput.map((out) {
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
      return OpenShopOutput(
        out['jobId'] as int,
        out['dbJobId'] as int,
        DateTime.fromMillisecondsSinceEpoch(out['dueDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(out['startDate'] as int),
        DateTime.fromMillisecondsSinceEpoch(out['endTime'] as int),
        schedulingMap,
      );
    }).toList();

    // Transformar la salida en PlanningMachineEntity
    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    final Map<int, int> jobCounter = {};
    for (var jobOutput in output) {
      final job =
          order.orderJobs!.firstWhere((j) => j.jobId == jobOutput.dbJobId);
      final current = (jobCounter[jobOutput.dbJobId] ?? 0) + 1;
      jobCounter[jobOutput.dbJobId] = current;

      for (var entry in jobOutput.scheduling.entries) {
        final taskId = entry.key;
        final machineId = entry.value.value1;
        final range = entry.value.value2;

        final task = job.sequence!.tasks!.firstWhere((t) => t.id == taskId);

        final jobName = job.jobName ?? 'Job ${job.jobId}';
        final displayName = current == 1
            ? jobName
            : '$jobName (${current - 1})';

        final planningTask = PlanningTaskEntity(
          sequenceId: job.sequence!.id!,
          sequenceName: job.sequence!.name,
          displayName: displayName,
          taskId: taskId,
          numberProcess: job.sequence!.tasks!.indexOf(task) + 1,
          startDate: range.start,
          endDate: range.end,
          retarded: range.end.isAfter(job.dueDate),
          jobId: job.jobId!,
          orderId: orderId,
        );

        if (!machineTasksMap.containsKey(machineId)) {
          machineTasksMap[machineId] = [];
        }
        machineTasksMap[machineId]!.add(planningTask);
      }
    }

    final List<PlanningMachineEntity> planningMachines =
        machineTasksMap.entries.map((entry) {
      final machine = machines.firstWhere((m) => m.id == entry.key);
      return PlanningMachineEntity(
        entry.key,
        machine.name,
        entry.value,
        scheduledInactivities: machine.scheduledInactivities,
      );
    }).toList();

    // Calcular métricas
    final metrics = getMetricts(
      planningMachines,
      output.map((out) {
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.dbJobId);
        return Tuple5(out.jobId, out.startDate, out.endTime, out.dueDate,
            job.priority);
      }).toList(),
    );

    return Tuple2(planningMachines, metrics);
  }
}
