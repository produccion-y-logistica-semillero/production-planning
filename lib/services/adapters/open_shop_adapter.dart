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
import 'package:production_planning/services/algorithms/open_shop.dart';
import 'package:production_planning/services/setup_time_service.dart';
import 'package:production_planning/shared/functions/functions.dart';
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
          // prefer explicit per-job times when available
          final explicit =
              getExplicitProcessingDuration(job, task.id!, machine);
          // Calculate duration from machine percentage (100% = 1 hour base)
          final baseDuration = Duration(
              minutes: (60 * machine.processingPercentage / 100).round());
          final Duration duration =
              explicit ?? ruleOf3(baseDuration, task.processingUnits);

          if (duration == Duration.zero) {
            continue;
          }
          machineDurations[machine.id!] = duration;
        }

        if (machineDurations.isNotEmpty) {
          operations.add(Tuple2(task.id!, machineDurations));
        }
      }

      for (var i = 0; i < job.amount; i++) {
        inputJobs.add(OpenShopInput(
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

    // Ejecutar el algoritmo Open Shop

    final output = OpenShop(
      order.regDate,
      Tuple2(START_SCHEDULE, END_SCHEDULE),
      inputJobs,
      machinesAvailability,
      rule,
      machineInactivities: machineInactivitiesMap,
      machineContinueCapacity: machineContinueCapacityMap,
      machineRestTime: machineRestTimeMap,
      changeoverMatrix: changeoverMatrix,
    ).output;

    // Transformar la salida en PlanningMachineEntity
    final Map<int, List<PlanningTaskEntity>> machineTasksMap = {};

    final Map<int, int> jobCounter = {};
    for (var jobOutput in output) {
      final job =
          order.orderJobs!.firstWhere((j) => j.jobId == jobOutput.jobId);
      final current = (jobCounter[jobOutput.jobId] ?? 0) + 1;
      jobCounter[jobOutput.jobId] = current;

      for (var entry in jobOutput.scheduling.entries) {
        final taskId = entry.key;
        final machineId = entry.value.value1;
        final range = entry.value.value2;

        final task = job.sequence!.tasks!.firstWhere((t) => t.id == taskId);

        final displayName = current == 1
            ? (job.sequence?.name ?? '')
            : '${job.sequence?.name ?? ''}.${current - 1}';

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
        final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
        return Tuple4(out.startDate, out.endTime, out.dueDate, job.priority);
      }).toList(),
    );

    return Tuple2(planningMachines, metrics);
  }
}
