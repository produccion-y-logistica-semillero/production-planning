class MachineEntity{
  int? id;
  int? machineTypeId;
  String? status;
  Duration processingTime;
  Duration? preparationTime;
  Duration? restTime;
  String name;
  int continueCapacity;

  MachineEntity({
    this.id,
    required this.status,
    this.machineTypeId,
    required this.name,
    required this.processingTime,
    required this.preparationTime,
    required this.restTime,
    required this.continueCapacity
  });

  

}