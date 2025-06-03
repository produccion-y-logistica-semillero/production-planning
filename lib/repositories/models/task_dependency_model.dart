import 'package:production_planning/entities/task_dependency_entity.dart';

class TaskDependencyModel {
  int? id;
  final int successor_id ;           
  final int predecessor_id;
  final String? description;
  final int sequenceId;

  TaskDependencyModel({
    this.id,
    required this.successor_id,
    required this.predecessor_id,
    required this.sequenceId,
    this.description,
  });

  factory TaskDependencyModel.fromEntity(TaskDependencyEntity entity, int sequenceId) {
    return TaskDependencyModel(
      id: entity.id,
      successor_id: entity.successor_id,
      predecessor_id: entity.predecessor_id,
      sequenceId: sequenceId,
      description: entity.description,
    );
  }

  factory TaskDependencyModel.fromJson(Map<String, dynamic> map) {
    return TaskDependencyModel(
      id: map["id"],
      successor_id: map["successor_id"],
      predecessor_id: map["predecessor_id"],
      sequenceId: map["sequence_id"],
      description: map["description"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "predecessor_id": predecessor_id,
      "successor_id": successor_id,
      "sequence_id": sequenceId,
      "description": description,
    };
  }

  TaskDependencyEntity toEntity() {
    return TaskDependencyEntity(
      id: id,
      predecessor_id: predecessor_id,
      sequenceId: sequenceId,
      successor_id: successor_id,
      description: description,
    );
  }
}