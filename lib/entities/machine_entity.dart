import 'package:production_planning/entities/machine_inactivity_entity.dart';

class MachineEntity {
  int? id;
  int? machineTypeId;
  String? status;
  double processingPercentage;
  double preparationPercentage;
  double restPercentage;
  String name;
  int continueCapacity;
  DateTime? availabilityDateTime;
  List<MachineInactivityEntity> scheduledInactivities;

  MachineEntity({
    this.id,
    required this.status,
    this.machineTypeId,
    required this.name,
    required this.processingPercentage,
    required this.preparationPercentage,
    required this.restPercentage,
    required this.continueCapacity,
    this.availabilityDateTime,
    this.scheduledInactivities = const [],
  });

  factory MachineEntity.defaultMachine() {
    return MachineEntity(
      status: null,
      name: '',
      processingPercentage: 100.0,
      preparationPercentage: 100.0,
      restPercentage: 100.0,
      continueCapacity: 0,
      availabilityDateTime: null,
      scheduledInactivities: const [],
    );
  }
}
