import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

class SequenceModel{
  int? jobId;
  final String name;

  SequenceModel({
    this.jobId,
    required this.name
  });

  factory SequenceModel.fromEntity(SequenceEntity entity){
    return SequenceModel(name: entity.name);
  }

  Map<String, dynamic> toJson(){
    return  {
      "name" : name
    };
  }
}