import 'package:production_planning/entities/task_dependency_entity.dart';

class TaskDependencyModel {
  int? id;
  final int successor_id ;           

  final int predecessor_id;
  final int sequenceId;

  TaskDependencyModel({
    this.id,
    required this.successor_id,
    required this.predecessor_id,
    required this.sequenceId,
  });


  factory TaskDependencyModel.fromEntity(
      TaskDependencyEntity entity, int sequenceId) {
    return TaskDependencyModel(
      id: entity.id,
      successor_id: entity.successor_id,
      predecessor_id: entity.predecessor_id,
      sequenceId: sequenceId,
    );
  }

  factory TaskDependencyModel.fromJson(Map<String, dynamic> map) {
    return TaskDependencyModel(
      id: map["id"],
      successor_id: map["successor_id"],
      predecessor_id: map["predecessor_id"],
      sequenceId: map["sequence_id"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "predecessor_id": predecessor_id,
      "successor_id": successor_id,
      "sequence_id": sequenceId,
    };
  }

  TaskDependencyEntity toEntity() {
    return TaskDependencyEntity(
      id: id,
      predecessor_id: predecessor_id,
      sequenceId: sequenceId,
      successor_id: successor_id,
    );
  }
}
