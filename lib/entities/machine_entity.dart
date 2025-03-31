
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

  factory MachineEntity.defaultMachine(){
    return MachineEntity(
      status: null, 
      name: '', 
      processingTime: Duration.zero, 
      preparationTime: null, 
      restTime: null, 
      continueCapacity: 0
    );
  }

}