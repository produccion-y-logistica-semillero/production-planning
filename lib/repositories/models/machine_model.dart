
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';

class MachineModel {
  int? id;
  int? machineTypeId;
  String? status;
  Duration processingTime;
  Duration preparationTime;
  Duration restTime;
  int continueCapacity;
  String name;

  MachineModel({
  required this.id, 
  this.machineTypeId,
  required this.name,
  required this.status, 
  required this.processingTime,
  required this.preparationTime,
  required this.restTime,
  required this.continueCapacity
  });

  factory MachineModel.fromJson(Map<String, dynamic> data){
    return MachineModel(
      id: data["machine_id"],
      name: data["machine_name"],
      machineTypeId: data["machine_type_id"],
      status: data["status_id"],
      processingTime: data["processing_time"],
      preparationTime: data["preparation_time"], 
      restTime: data["rest_time "], 
      continueCapacity: data["continue_capacity"]
    );
  }

  MachineEntity toEntity(){
    return MachineEntity(
      machineTypeId: machineTypeId,
      status: status,
      name: name,
      processingTime: processingTime,
      preparationTime: preparationTime,
      restTime: restTime,
      continueCapacity: continueCapacity,
      scheduledInactivities: const <MachineInactivityEntity>[],
    );
  }
  
}

