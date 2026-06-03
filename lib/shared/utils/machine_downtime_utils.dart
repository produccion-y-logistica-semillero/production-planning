import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/task_scheduling_utils.dart';

void buildMachineDowntimeMaps(
  List<MachineEntity> machines, {
  required Map<int, List<MachineInactivityEntity>> inactivities,
  required Map<int, int> continueCapacity,
  required Map<int, Duration?> restTime,
}) {
  for (final machine in machines) {
    if (machine.id == null) continue;
    inactivities[machine.id!] = machine.scheduledInactivities;
    continueCapacity[machine.id!] = machine.continueCapacity;
    restTime[machine.id!] = machineRestDuration(machine.restPercentage);
  }
}
