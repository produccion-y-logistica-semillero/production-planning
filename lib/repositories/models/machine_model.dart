import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';

class MachineModel {
  int? id;
  int? machineTypeId;
  String? status;
  double processingPercentage;
  double preparationPercentage;
  double restPercentage;
  int continueCapacity;
  String name;

  MachineModel(
      {required this.id,
      this.machineTypeId,
      required this.name,
      required this.status,
      required this.processingPercentage,
      required this.preparationPercentage,
      required this.restPercentage,
      required this.continueCapacity});

  factory MachineModel.fromJson(Map<String, dynamic> data) {
    return MachineModel(
        id: data["machine_id"],
        name: data["machine_name"],
        machineTypeId: data["machine_type_id"],
        status: data["status_id"]?.toString(),
        processingPercentage:
            (data["processing_percentage"] as num?)?.toDouble() ?? 100.0,
        preparationPercentage:
            (data["preparation_percentage"] as num?)?.toDouble() ?? 100.0,
        restPercentage: (data["rest_percentage"] as num?)?.toDouble() ?? 100.0,
        continueCapacity: data["continue_capacity"] ?? 0);
  }

  MachineEntity toEntity() {
    return MachineEntity(
      machineTypeId: machineTypeId,
      status: status,
      name: name,
      processingPercentage: processingPercentage,
      preparationPercentage: preparationPercentage,
      restPercentage: restPercentage,
      continueCapacity: continueCapacity,
      scheduledInactivities: const <MachineInactivityEntity>[],
    );
  }
}
