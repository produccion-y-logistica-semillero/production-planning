
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';

class PlanningMachineEntity {
  final int machineId;
  final String machineName;
  List<PlanningTaskEntity> tasks;
  final List<MachineInactivityEntity> scheduledInactivities;

  PlanningMachineEntity(this.machineId, this.machineName, this.tasks,
      {this.scheduledInactivities = const []});
}