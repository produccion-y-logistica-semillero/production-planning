import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class MachineModel{
  int? id;
  String name;
  String description;

   MachineModel({required this.id, required this.name,  required this.description});

   factory  MachineModel.fromJson(Map<String, dynamic> data){
    return MachineModel(id: data["machine_type_id"], name: data["name"], description: data["description"]);
   }

   factory MachineModel.fromEntity(MachineTypeEntity machine){
    return MachineModel(id: machine.id, name: machine.name, description: machine.description);
   }

   MachineTypeEntity toEntity(){
    return MachineTypeEntity(id: id, name: name, description: description);
   }

   Map<String, dynamic> toJson(){
    return {
      if(id != null) "machine_type_id" : id,
      "name" : name,
      "description" : description,
    };
   }

}