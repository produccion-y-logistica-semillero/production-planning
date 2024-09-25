import 'package:production_planning/features/2_orders/presentation/dtos/gantt_task_dto.dart';

class GanttMachineDTO{
  final int machineId;
  final String machineName;
  List<GanttTaskDTO> tasks;
  GanttMachineDTO(this.machineId, this.machineName): tasks = [];
}