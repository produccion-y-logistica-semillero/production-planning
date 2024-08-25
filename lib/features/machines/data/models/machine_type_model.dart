import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class MachineTypeModel{
  int? id;
  String name;
  String description;

   MachineTypeModel({required this.id, required this.name,  required this.description});

   factory  MachineTypeModel.fromJson(Map<String, dynamic> data){
    return MachineTypeModel(id: data["machine_type_id"], name: data["name"], description: data["description"]);
   }

   factory MachineTypeModel.fromEntity(MachineTypeEntity machine){
    return MachineTypeModel(id: machine.id, name: machine.name, description: machine.description);
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