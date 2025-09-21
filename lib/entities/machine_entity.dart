class MachineEntity {
  int? id;
  int? machineTypeId;
  String? status;
  Duration processingTime;
  Duration? preparationTime;
  Duration? restTime;
  String name;
  int continueCapacity;
  DateTime? availabilityDateTime;
  int? supportsPreemption;

  MachineEntity({
    this.id,
    required this.status,
    this.machineTypeId,
    required this.name,
    required this.processingTime,
    required this.preparationTime,
    required this.restTime,
    required this.continueCapacity,
    this.availabilityDateTime,
  });
  MachineEntity.withPreemption(
      {this.id,
      required this.status,
      this.machineTypeId,
      required this.name,
      required this.processingTime,
      required this.preparationTime,
      required this.restTime,
      required this.continueCapacity,
      this.availabilityDateTime,
      this.supportsPreemption});

  factory MachineEntity.defaultMachine() {
    return MachineEntity.withPreemption(
        status: null,
        name: '',
        processingTime: Duration.zero,
        preparationTime: null,
        restTime: null,
        continueCapacity: 0,
        availabilityDateTime: null,
        supportsPreemption: null);
  }
}
