import 'package:production_planning/entities/task_dependency_entity.dart';

class TaskDependencyModel {
  int? id;
  final int taskId;            
  final int dependsOnTaskId;
  final String? description;
  final int sequenceId;

  TaskDependencyModel({
    this.id,
    required this.taskId,
    required this.dependsOnTaskId,
    required this.sequenceId,
    this.description,
  });

  factory TaskDependencyModel.fromEntity(TaskDependencyEntity entity, int sequenceId) {
    return TaskDependencyModel(
      id: entity.id,
      taskId: entity.taskId,
      dependsOnTaskId: entity.dependsOnTaskId,
      sequenceId: sequenceId,
      description: entity.description,
    );
  }

  factory TaskDependencyModel.fromJson(Map<String, dynamic> map) {
    return TaskDependencyModel(
      id: map["id"],
      taskId: map["successor_id"],
      dependsOnTaskId: map["predecessor_id"],
      sequenceId: map["sequence_id"],
      description: map["description"],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "predecessor_id": dependsOnTaskId,
      "successor_id": taskId,
      "sequence_id": sequenceId,
      "description": description,
    };
  }

  TaskDependencyEntity toEntity() {
    return TaskDependencyEntity(
      id: id,
      taskId: taskId,
      sequenceId: sequenceId,
      dependsOnTaskId: dependsOnTaskId,
      description: description,
    );
  }
}