class MachineEntity{
  int? id;
  String? status;
  Duration processingTime;
  Duration preparationTime;
  Duration restTime;
  int continueCapacity;

  MachineEntity({
    this.id,
    required this.status,
    required this.processingTime,
    required this.preparationTime,
    required this.restTime,
    required this.continueCapacity
  });

  

}