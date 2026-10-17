
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/planning_task_entity.dart';

class PlanningMachineEntity {
  final int machineId;
  final String machineName;
  List<PlanningTaskEntity> tasks;
  final List<MachineInactivityEntity> scheduledInactivities;

  /// Work station (machine type) the machine belongs to; null when the
  /// adapter did not provide it.
  final String? stationName;

  PlanningMachineEntity(this.machineId, this.machineName, this.tasks,
      {this.scheduledInactivities = const [], this.stationName});
}