import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

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

  SequenceEntity toEntity(){
    return SequenceEntity(sequenceId, null, name);
  }

  Map<String, dynamic> toJson(){
    return  {
      if(sequenceId != null) "sequence_id" : sequenceId,
      "name" : name
    };
  }
}