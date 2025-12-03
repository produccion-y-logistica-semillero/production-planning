import 'package:production_planning/entities/machine_inactivity_entity.dart';

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
  List<MachineInactivityEntity> scheduledInactivities;

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
    this.scheduledInactivities = const [],
  });

  factory MachineEntity.defaultMachine() {
    return MachineEntity(
      status: null,
      name: '',
      processingTime: Duration.zero,
      preparationTime: null,
      restTime: null,
      continueCapacity: 0,
      availabilityDateTime: null,
      scheduledInactivities: const [],
    );
  }
}
