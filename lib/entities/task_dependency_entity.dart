class TaskDependencyEntity {
  int? id;
  final int successor_id;
  final int predecessor_id;
  final int sequenceId;
  final String? description;

  TaskDependencyEntity({
    this.id,
    required this.successor_id,
    required this.predecessor_id,
    required this.sequenceId,
    this.description,
  });
}