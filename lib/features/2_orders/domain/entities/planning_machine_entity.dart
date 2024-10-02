import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';

class PlanningMachineEntity{
  final int machineId;
  final String machineName;
  List<PlanningTaskEntity> tasks;
  PlanningMachineEntity(this.machineId, this.machineName): tasks = [];
}