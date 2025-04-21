import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
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
import 'package:production_planning/shared/functions/functions.dart';
import 'package:production_planning/shared/types/rnage.dart';

class FlexibleFlowShopAdapter {
  final OrderRepository orderRepository;
  final MachineRepository machineRepository;

  FlexibleFlowShopAdapter({
    required this.orderRepository,
    required this.machineRepository,
  });

  int toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }


Future<Tuple2<List<PlanningMachineEntity>, Metrics>?> flexibleFlowShopAdapter(int orderId, String rule) async {
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
    final responseMachines = await machineRepository.getAllMachinesFromType(typeId);
    final machineList = responseMachines.fold((_) => null, (m) => m);
    if (machineList == null || machineList.isEmpty) return null;
    machines.addAll(machineList); // Agregar todas las máquinas del tipo
  }

  // Crear el input para el algoritmo Flexible Flow Shop

  final List<FlexibleFlowInput> inputJobs = [];
  for (final job in order.orderJobs!) {
    final List<Tuple2<int, Map<int, Duration>>> taskSequence = [];
    for (final task in job.sequence!.tasks!) {
      final Map<int, Duration> machineDurations = {};
      for (final machine in machines.where((m) => m.machineTypeId == task.machineTypeId)) {
        Duration processingTime = machine.processingTime;
        
        print("processing time: $processingTime, processing units: ${task.processingUnits}");
        final duration = ruleOf3(processingTime, task.processingUnits);
        
        if (duration == Duration.zero) {
          print('Error: Duración calculada es cero para la máquina ${machine.id}');
          continue;
        }
    machineDurations[machine.id!] = duration;
  }

  taskSequence.add(Tuple2(task.id!, machineDurations));
}

    inputJobs.add(FlexibleFlowInput(
      job.jobId!,
      job.dueDate,
      job.priority,
      job.availableDate,
      taskSequence,
    ));
  }

  // Crear la disponibilidad inicial de las máquinas
  final Map<int, DateTime> machinesAvailability = {};
  for (final machine in machines) {
    machinesAvailability[machine.id!] = order.regDate;
  }

  // Ejecutar el algoritmo Flexible Flow Shop
  final output = FlexibleFlowShop(
    order.regDate,
    Tuple2(START_SCHEDULE, END_SCHEDULE),
    inputJobs,
    machinesAvailability,
    rule,
  ).output;

  // Transformar la salida en PlanningMachineEntity
  final List<PlanningMachineEntity> planningMachines = [];
  for (final machine in machines) {
    planningMachines.add(PlanningMachineEntity(machine.id!, machine.name, []));
  }

for (final out in output) {
  final job = order.orderJobs!.firstWhere((j) => j.jobId == out.jobId);
  final sequence = job.sequence!;
  for (final taskEntry in out.scheduling.entries) {
    final taskId = taskEntry.key;
    final machineId = taskEntry.value.value1;
    final timeRange = taskEntry.value.value2;

    print('Task Range - Start: ${timeRange.startDate}, End: ${timeRange.endDate}');

    final task = sequence.tasks!.firstWhere((t) => t.id == taskId);

    final planningTask = PlanningTaskEntity(
      sequenceId: sequence.id!,
      sequenceName: sequence.name,
      taskId: task.id!,
      numberProcess: taskId,
      startDate: timeRange.startDate,
      endDate: timeRange.endDate,
      retarded: out.dueDate.isBefore(timeRange.endDate),
      jobId: job.jobId!,
      orderId: orderId,
    );

    final planningMachine = planningMachines.firstWhere((m) => m.machineId == machineId);
    planningMachine.tasks.add(planningTask);
  }
}

  // Calcular métricas
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
}