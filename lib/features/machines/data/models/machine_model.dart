import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

class MachineModel{
  String name;
  String description;

   MachineModel({required this.name,  required this.description});

   factory  MachineModel.fromJson(Map<String, dynamic> data){
    return MachineModel(name: data["name"], description: data["description"]);
   }

   factory MachineModel.fromEntity(MachineEntity machine){
    return MachineModel(name: machine.name, description: machine.description);
   }

   MachineEntity toEntity(){
    return MachineEntity(name: name, description: description);
   }

   Map<String, dynamic> toJson(){
    return {
      "name" : name,
      "description" : description,
    };
   }

}