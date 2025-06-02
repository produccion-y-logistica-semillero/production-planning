import 'package:production_planning/entities/sequence_entity.dart';

class SequenceModel{
  int? sequenceId;
  final String name;

  SequenceModel({
    this.sequenceId,
    required this.name
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

  get dependencies => null;

  SequenceEntity toEntity(){
    return SequenceEntity(sequenceId, null, name/*, null*/);
  }

  Map<String, dynamic> toJson(){
    return  {
      if(sequenceId != null) "sequence_id" : sequenceId,
      "name" : name
    };
  }
}