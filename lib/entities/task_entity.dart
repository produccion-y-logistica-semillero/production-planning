class TaskEntity{

  int? id;
  final Duration processingUnits;
  final String description;
  final int machineTypeId;
  String? machineName;
  final bool allowPreemption;
  TaskEntity({
    this.id,
    required this.processingUnits,
    required this.description,
    required this.machineTypeId,
    required this.machineName,

    this.allowPreemption = false,
  });
}