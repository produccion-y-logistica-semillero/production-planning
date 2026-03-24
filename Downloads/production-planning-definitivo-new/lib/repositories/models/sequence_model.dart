import 'package:production_planning/entities/sequence_entity.dart';

import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/repositories/models/task_dependency_model.dart';

class SequenceModel{

  int? sequenceId;
  final String name;
  final List<TaskDependencyModel>? dependencies;

  SequenceModel({
    this.sequenceId,
    required this.name,
    this.dependencies
  });

  factory SequenceModel.fromEntity(SequenceEntity entity){
    return SequenceModel(
      sequenceId: entity.id,
      name: entity.name
    );
  }

  factory SequenceModel.fromJson(Map<String, dynamic> map){
    return  SequenceModel(
      sequenceId: map["sequence_id"],
      name: map["name"]
    );
  }


  SequenceEntity toEntity() {
    return SequenceEntity(sequenceId, null, name, dependencies?.map((e) => e.toEntity()).toList());
  }

  Map<String, dynamic> toJson(){
    return  {
      if(sequenceId != null) "sequence_id" : sequenceId,
      "name" : name
    };
  }
}

