import 'package:production_planning/features/sequences/domain/entities/job_entity.dart';

class SequenceModel{
  int? jobId;
  final String name;

  SequenceModel({
    this.jobId,
    required this.name
  });

  factory SequenceModel.fromEntity(JobEntity entity){
    return SequenceModel(name: entity.name);
  }

  Map<String, dynamic> toJson(){
    return  {
      "name" : name
    };
  }
}