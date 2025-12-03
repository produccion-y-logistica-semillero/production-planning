import 'package:production_planning/entities/planning_task_entity.dart';

class PlanningMachineEntity{
  final int machineId;
  final String machineName;
  List<PlanningTaskEntity> tasks;
  PlanningMachineEntity(this.machineId, this.machineName, this.tasks);
}