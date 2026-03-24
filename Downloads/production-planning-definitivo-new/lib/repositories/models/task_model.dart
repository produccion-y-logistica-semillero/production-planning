import 'package:production_planning/entities/task_entity.dart';


class TaskModel{

  int? taskId;
  final Duration nProcUnits;
  final String description;
  final int sequenceId;
  final int machineTypeId;
  final bool allowPreemption;

  TaskModel({
    this.taskId,
    required this.nProcUnits,
    required this.description,
    required this.sequenceId,
    required this.machineTypeId,
    this.allowPreemption = false,
  });

  factory TaskModel.fromEntity(TaskEntity entity, int sequenceId) {
    return TaskModel(
      nProcUnits: entity.processingUnits,
      description: entity.description,
      sequenceId: sequenceId,
      machineTypeId: entity.machineTypeId,
      allowPreemption: entity.allowPreemption,
    );
  }

  factory TaskModel.fromJson(Map<String, dynamic> map) {
    return TaskModel(
      taskId: map["task_id"],
      nProcUnits: Duration(
          hours: int.parse(map["n_proc_units"].toString().substring(11, 13)),
          minutes: int.parse(map["n_proc_units"].toString().substring(14, 16))),
      description: map["description"],
      sequenceId: map["sequence_id"],
      machineTypeId: map["machine_type_id"],
      allowPreemption: map["allow_preemption"] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    String timeStamp =
        '${nProcUnits.inHours.toString().padLeft(2, '0')}:${(nProcUnits.inMinutes - nProcUnits.inHours * 60).toString().padLeft(2, '0')}:00';
    return {
      "sequence_id": sequenceId,
      "machine_type_id": machineTypeId,
      "n_proc_units":
          '1970-01-01 $timeStamp', //the default date since we only care about the time, not date
      "description": description,
      "allow_preemption": allowPreemption ? 1 : 0
    };
  }

  TaskEntity toEntity() {
    return TaskEntity(
      id: taskId,
      processingUnits: nProcUnits,
      description: description,
      machineTypeId: machineTypeId,
      machineName: null,
      allowPreemption: allowPreemption,
    );
  }
}