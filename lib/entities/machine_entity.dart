
import 'package:production_planning/entities/machine_inactivity_entity.dart';

/// How a machine's availability start date/time is determined.
enum MachineStartMode {
  /// Availability is set to DateTime.now() at save time.
  now,

  /// Availability is a manually picked date/time (default, preserves the
  /// original behavior for machines created before this mode existed).
  specificDate,
}

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
  MachineStartMode startMode;
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
    this.startMode = MachineStartMode.specificDate,
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
      startMode: MachineStartMode.specificDate,
      scheduledInactivities: const [],
    );
  }
}