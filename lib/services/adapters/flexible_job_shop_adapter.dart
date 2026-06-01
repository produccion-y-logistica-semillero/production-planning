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
import 'package:production_planning/shared/functions/functions.dart';
import '../../shared/utils/task_time_utils.dart';

class FlexibleJobShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  FlexibleJobShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
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
        inputJobs.add(FlexibleJobInput(
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

    // Ejecutar el algoritmo Flexible Job Shop
    final output = FlexibleJobShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity: machineContinueCapacityMap,
      machineRestTime: machineRestTimeMap,
      stateSetupMatrix: stateSetupMatrix,
      jobStates: jobStates,
    ).output;

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
