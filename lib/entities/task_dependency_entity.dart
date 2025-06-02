class TaskDependencyEntity {
  int? id;
  final int taskId;
  final int dependsOnTaskId;
  final int sequenceId;
  final String? description;

  TaskDependencyEntity({
    this.id,
    required this.taskId,
    required this.dependsOnTaskId,
    required this.sequenceId,
    this.description,
  });
}